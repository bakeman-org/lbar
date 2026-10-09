#!/usr/bin/env luajit
local function dir_of(p)
	local d = (p or ""):match("^(.*)/[^/]*$")
	if not d or d == "" then
		d = "."
	end
	return d
end

-- native (luastatic) deploy: the binary ships its lbar.so beside it, so the
-- executable's real directory wins over arg[0]/$PWD (argv[0] and the
-- build-time chunk name can both lie after copying to another prefix)
local SCRIPT_DIR = nil
do
	local ffi0 = require("ffi")
	ffi0.cdef("ssize_t readlink(const char *path, char *buf, size_t bufsiz);")
	local buf = ffi0.new("char[4096]")
	local n = ffi0.C.readlink("/proc/self/exe", buf, 4095)
	if n and n > 0 then
		local d = dir_of(ffi0.string(buf, n))
		local f = io.open(d .. "/lbar.so", "rb")
		if f then
			f:close()
			SCRIPT_DIR = d
		end
	end
end
if not SCRIPT_DIR then
	SCRIPT_DIR = dir_of(arg[0] or "lbar.lua")
	if SCRIPT_DIR:sub(1, 1) ~= "/" then
		local pwd = os.getenv("PWD")
		if pwd and pwd:sub(1, 1) == "/" and pwd ~= "" then
			SCRIPT_DIR = pwd:gsub("/$", "") .. "/" .. SCRIPT_DIR
		end
	end
end
package.path = SCRIPT_DIR .. "/?.lua;" .. package.path
package.cpath = SCRIPT_DIR .. "/?.so;" .. package.cpath

-- compositor-spawned sessions can carry a minimal PATH; make sure the
-- standard system dirs are present so tool probes (zenity, pactl, nmcli,
-- swww, grim…) resolve the same way they do from a user shell
do
	local ffi0 = require("ffi")
	local path = os.getenv("PATH") or ""
	local dirs = ":" .. path .. ":"
	local add = {}
	for _, d in ipairs({ "/usr/local/bin", "/usr/bin", "/bin" }) do
		if not dirs:find(":" .. d .. ":", 1, true) then
			add[#add + 1] = d
		end
	end
	if #add > 0 then
		ffi0.cdef("int setenv(const char *name, const char *value, int overwrite);")
		ffi0.C.setenv("PATH", table.concat(add, ":") .. ":" .. path, 1)
		print("[lbar] PATH extended with: " .. table.concat(add, ":"))
	end
end

local init = require("core.init")(SCRIPT_DIR)
local Bar = require("core.bar")
local PluginMgr = require("core.plugins")
local Keybinds = require("core.keybinds")
local Toast = require("core.toast")
local Screenshot = require("core.screenshot")
local Theme = require("core.theme")
local Util = require("core.util")
local I18n = require("core.i18n")
local ffi = init.ffi
local libc = init.libc
local L = init.L
local AUD = init.AUD
local log = Util.logger("lbar")

local CONFIG_PATH = (arg[1] and arg[1] ~= "") and arg[1] or (SCRIPT_DIR .. "/config.lua")

local function resolve_path(p)
	if not p or p == "" then
		return p
	end
	if p:sub(1, 1) == "~" then
		p = (os.getenv("HOME") or "") .. p:sub(2)
	end
	if p:sub(1, 1) == "/" then
		return p
	end
	return SCRIPT_DIR .. "/" .. p
end

local function normalize(cfg)
	cfg.font_path = resolve_path(cfg.font_path)
	cfg.fallback_font_paths = cfg.fallback_font_paths or {}
	for i, p in ipairs(cfg.fallback_font_paths) do
		cfg.fallback_font_paths[i] = resolve_path(p)
	end
	return cfg
end

local config = normalize(dofile(CONFIG_PATH))

local Lctx = L.lbar_open()
if Lctx == nil then
	error("lbar_open failed")
end
local kind = ffi.string(L.lbar_backend(Lctx))
log("backend: %s", kind)

if L.xft_init() ~= 0 then
	error("FreeType init failed")
end

local function load_font(cfg)
	local fb = table.concat(cfg.fallback_font_paths or {}, "\n")
	return L.xft_load(cfg.font_path, tonumber(cfg.font_size) or 14, #fb > 0 and fb or nil)
end

local ft_ctx = load_font(config)
if ft_ctx == nil then
	error("font load failed: " .. config.font_path)
end

local ctx = {
	SCRIPT_DIR = SCRIPT_DIR,
	config_path = CONFIG_PATH,
	ffi = ffi,
	L = L,
	Lctx = Lctx,
	ft_ctx = ft_ctx,
	config = config,
	theme = {},
	log = log,
	backend_kind = kind,
	actions = {},
	AUD = AUD,
	popup_visible = false,
	active_plugin_name = nil,
	active_panel = nil,
	_kbd_id = nil,
	_ime_on = false,
	_ptr_id = nil,
	_drag_panel = nil,
	_press_panel = nil,
	debug = false,
	lbar_dir = SCRIPT_DIR,
}
ctx.scr_w = L.lbar_screen_w(Lctx)
ctx.scr_h = L.lbar_screen_h(Lctx)

function ctx.get_text_size(s)
	local w, h = ffi.new("int[1]"), ffi.new("int[1]")
	L.xft_text_extent(ft_ctx, s, w, h)
	return w[0], h[0]
end
function ctx.get_line_height()
	return L.xft_primary_line_height(ft_ctx)
end

ctx.theme = Theme.build(config)
I18n.init(ctx)
ctx.toast = Toast.new(ctx)
ctx.notify = function(text, opts)
	ctx.toast:show(text, opts)
end

local panels = {}

function ctx.register_panel(name, panel)
	panels[name] = panel
	ctx.actions["toggle_" .. name] = function()
		ctx.toggle_panel(name)
	end
end

-- ── multi-panel support ──
-- several panels can be visible at once; exactly one of them is "active"
-- (the last clicked/shown one) and owns the exclusive keyboard grab. these
-- syncs are the single authority for grab ownership on both backends.

function ctx.sync_kbd()
	local p = ctx.active_panel
	local want = p and p.visible and not p.destroyed and p:kbd_wanted()
	if want then
		if ctx._kbd_id ~= p.id then
			ctx.L.lbar_kbd_grab(ctx.Lctx, p.id)
			ctx._kbd_id = p.id
		end
	elseif ctx._kbd_id then
		ctx.L.lbar_kbd_ungrab(ctx.Lctx)
		ctx._kbd_id = nil
	end
	-- wayland IME (zwp_text_input_v3): enabled while the active panel's text
	-- input holds focus; no-ops on X11 or without the manager
	local ime = want and p.input and p.input.focused
	if ime and not ctx._ime_on then
		ctx._ime_on = true
		local r = p.input
		ctx.L.lbar_ti_enable(ctx.Lctx, r.x or 0, r.y or 0, r.w or 0, r.h or 0)
	elseif not ime and ctx._ime_on then
		ctx._ime_on = false
		ctx.L.lbar_ti_disable(ctx.Lctx)
	end
	-- the focused panel owns the keyboard: blur inputs everywhere else
	for _, q in pairs(panels) do
		if q ~= p then
			if q.input and q.input.focused then
				q.input:blur()
			end
			if q.ui and q.ui.any_focus and q.ui:any_focus() and q.ui.blur_input then
				q.ui:blur_input()
			end
		end
	end
end

-- X11: one pointer grab delivers presses outside every panel (dismiss-on-
-- outside-click). wayland: an equivalent full-screen catcher surface is
-- toggled on the C side while any dismissable panel is visible.
function ctx.sync_ptr_grab()
	local on = false
	if ctx.backend_kind == "wayland" then
		for _, q in pairs(panels) do
			if q.visible and not q.destroyed and q.opts.ptr_grab ~= false then
				on = true
				break
			end
		end
		-- guard: tolerate a stale lbar.so built before the catcher existed
		if ctx.L.lbar_outside_catch then
			ctx.L.lbar_outside_catch(Lctx, on and 1 or 0)
		end
		return
	end
	local holder = nil
	local p = ctx.active_panel
	if p and p.visible and not p.destroyed and p.opts.ptr_grab ~= false then
		holder = p
	end
	if not holder then
		for _, q in pairs(panels) do
			if q.visible and not q.destroyed and q.opts.ptr_grab ~= false then
				holder = q
				break
			end
		end
	end
	local hid = holder and holder.id or nil
	if hid ~= ctx._ptr_id then
		if hid then
			ctx.L.lbar_ptr_grab(ctx.Lctx, hid)
		else
			ctx.L.lbar_ptr_ungrab(ctx.Lctx)
		end
		ctx._ptr_id = hid
	end
end

function ctx.show_panel(name, anchor_x, anchor_y, direction, align)
	local p = panels[name]
	if not p then
		return
	end
	if p.visible then
		p:hide()
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
		return
	end
	if anchor_x then
		p:show_at(anchor_x, anchor_y, direction, align)
	else
		p:show()
	end
	-- other panels stay visible (multi-panel); focus moved to this one
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

-- reopen a panel keeping how it was shown before: user-dragged position,
-- the configured free position (panels.<name>.pos, set in the Panels tab),
-- bar anchor (with left-align), or the center fallback
local function show_restored(name)
	local p = panels[name]
	if not p or p.destroyed then
		return
	end
	if p.user_pos then
		ctx.show_panel(name)
		return
	end
	local pcfg = ctx.config.panels and ctx.config.panels[name] or nil
	if pcfg and pcfg.pos and pcfg.pos ~= "auto" then
		ctx.show_panel(name)
		return
	end
	if p.last_anchor then
		local a = p.last_anchor
		ctx.show_panel(name, a.x, a.y, a.dir, a.align)
	else
		ctx.show_panel(name)
	end
end

function ctx.toggle_panel(name)
	local p = panels[name]
	if not p then
		return
	end
	if p.visible then
		ctx.show_panel(name)
		return
	end
	show_restored(name)
end

function ctx.close_panels()
	for _, p in pairs(panels) do
		if p.visible then
			p:hide()
		end
	end
	ctx.active_plugin_name = nil
	ctx.active_panel = nil
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

local actions = ctx.actions
actions.quit = function()
	os.exit(0)
end
actions.close_panels = function()
	ctx.close_panels()
end
actions.hot_reload = nil
actions.toggle_auto_reload = nil

local function build_bar(cfg)
	local bar, err = Bar.new(ctx, cfg)
	if not bar then
		return nil, err
	end
	PluginMgr.load_all(ctx, bar, cfg.plugins or {})
	return bar
end

local bar, err = build_bar(config)
if not bar then
	error("bar init: " .. tostring(err))
end
ctx.bar = bar

local keybinds = Keybinds.new(ctx)

local function watch_paths(cfg)
	local paths = { CONFIG_PATH }
	for _, name in ipairs(cfg.plugins or {}) do
		paths[#paths + 1] = SCRIPT_DIR .. "/plugins/" .. name .. ".lua"
	end
	return paths
end

local wpaths = watch_paths(config)
local wmtimes = PluginMgr.snapshot_mtimes(wpaths)
local auto_reload = true
ctx.auto_reload = true
local theme_dark = (config.theme_mode or "dark") ~= "light"

local function reload_all()
	local ok, newcfg = pcall(dofile, CONFIG_PATH)
	if not ok or type(newcfg) ~= "table" then
		log("config reload failed: %s", tostring(newcfg))
		ctx.notify(I18n.t("config reload failed: %s", tostring(newcfg)), { style = "error" })
		return
	end
	newcfg = normalize(newcfg)

	local font_changed = newcfg.font_path ~= config.font_path or newcfg.font_size ~= config.font_size
	if not font_changed then
		local a = table.concat(config.fallback_font_paths or {}, "\n")
		local b = table.concat(newcfg.fallback_font_paths or {}, "\n")
		font_changed = a ~= b
	end

	ctx.close_panels()
	ctx.toast:invalidate()
	bar:destroy()
	for _, p in pairs(ctx._panels or {}) do
		p:destroy()
	end
	ctx._panels = {}
	panels = {}
	ctx._panel_by_id = {}
	ctx._kbd_id = nil
	ctx._ptr_id = nil
	ctx._ime_on = false
	ctx._drag_panel = nil
	ctx._press_panel = nil

	config = newcfg
	ctx.config = config
	ctx.theme = Theme.build(config)
	I18n.init(ctx)
	theme_dark = (config.theme_mode or "dark") ~= "light"

	-- toasts are emitted after the backend reopen: a toast panel created
	-- before lbar_close would hold a popup id from the freed ctx
	local font_ok, font_err
	if font_changed then
		local ok_f, nf = pcall(load_font, config)
		if ok_f and nf then
			L.xft_done(ft_ctx)
			ft_ctx = nf
			ctx.ft_ctx = nf
			font_ok = true
			log("font reloaded: %s @ %d", config.font_path, config.font_size or 14)
		else
			font_err = tostring(nf)
			log("font reload failed: %s", font_err)
		end
	end

	L.lbar_close(Lctx)
	local newL = L.lbar_open()
	if not newL then
		log("reopen failed after reload, exiting")
		os.exit(1)
	end
	Lctx = newL
	ctx.Lctx = Lctx
	ctx.scr_w = L.lbar_screen_w(Lctx)
	ctx.scr_h = L.lbar_screen_h(Lctx)

	-- drop cached plugin modules: re-init from a clean state (stale M.panel
	-- refs to destroyed panels broke re-init and silently dropped bar items)
	for _, name in ipairs(config.plugins or {}) do
		package.loaded["plugins." .. name] = nil
	end
	bar, err = build_bar(config)
	if not bar then
		log("bar rebuild failed: %s", tostring(err))
		os.exit(1)
	end
	ctx.bar = bar

	keybinds.build(config.keybinds)

	wpaths = watch_paths(config)
	wmtimes = PluginMgr.snapshot_mtimes(wpaths)
	-- a reload resynced the mtimes already; a leftover skip flag from the
	-- settings writer must not swallow the next watcher cycle
	ctx.skip_reload_once = false
	if font_ok then
		ctx.notify(I18n.t("font reloaded: %s", config.font_path:match("[^/]+$") or config.font_path),
			{ style = "success" })
	elseif font_err then
		ctx.notify(I18n.t("font reload failed: %s", config.font_path), { style = "error" })
	else
		ctx.notify(I18n.t("config reloaded"), { style = "success" })
	end
	log("hot reload done: %s @ %s h=%d plugins=%d", kind, bar.pos, bar.h, #bar.plugins)
end

actions.hot_reload = reload_all
actions.toggle_auto_reload = function()
	auto_reload = not auto_reload
	ctx.auto_reload = auto_reload
	ctx.notify(I18n.t(auto_reload and "auto reload on" or "auto reload off"), { style = "info" })
end
-- ctrl+alt+d: toggle all panels hide/show (reopens the panels that were
-- visible when they were hidden)
local hidden_restore = nil
actions.hide_all_windows = function()
	-- the toast panel itself must not count: the "panels hidden" toast is
	-- visible right after hiding, and counting it made the second press take
	-- the hide branch again (toggle never reached the restore side)
	local any = false
	local names = {}
	for name, p in pairs(panels) do
		if name ~= "toast" and p.visible and not p.destroyed then
			any = true
			names[#names + 1] = name
		end
	end
	if any then
		hidden_restore = names
		ctx.close_panels()
		ctx.notify(I18n.t("panels hidden"), { style = "info" })
	else
		if not hidden_restore or #hidden_restore == 0 then
			ctx.notify(I18n.t("no panels to show"), { style = "info" })
			return
		end
		for _, name in ipairs(hidden_restore) do
			show_restored(name)
		end
		hidden_restore = nil
		ctx.notify(I18n.t("panels shown"), { style = "info" })
	end
end

local function save_theme_mode(mode)
	local fh = io.open(CONFIG_PATH, "r")
	if not fh then
		log("save theme_mode failed: cannot read %s", CONFIG_PATH)
		return
	end
	local text = fh:read("*a")
	fh:close()
	if text:find("theme_mode%s*=") then
		text = text:gsub("theme_mode%s*=%s*['\"][%w_]+['\"]", "theme_mode = '" .. mode .. "'")
	else
		local repl = "%1    theme_mode = '" .. mode .. "',\n"
		local new = text:gsub("(theme_light%s*=%s*['\"][^'\"]*['\"],%s*\n)", repl)
		if new == text then
			new = text .. "\ntheme_mode = '" .. mode .. "',\n"
		end
		text = new
	end
	local out = io.open(CONFIG_PATH, "w")
	if not out then
		log("save theme_mode failed: cannot write %s", CONFIG_PATH)
		return
	end
	out:write(text)
	out:close()
	-- our own write must not trigger the auto-reload watcher
	ctx.skip_reload_once = true
	log("theme_mode saved: %s", mode)
end

actions.toggle_theme = function()
	theme_dark = not theme_dark
	config.theme_mode = theme_dark and "dark" or "light"
	ctx.theme = Theme.build(config)
	for _, p in pairs(panels) do
		p.bg = ctx.theme.bg
	end
	if ctx.toast.panel then
		ctx.toast.panel.bg = ctx.theme.bg
	end
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
	for _, p in pairs(panels) do
		if p.visible then
			p:draw()
		end
	end
	ctx.notify("theme: " .. ctx.theme.name, { style = "info" })
end

actions.toggle_debug_mode = function()
	ctx.debug = not ctx.debug
	if ctx.debug then
		ctx.notify("debug on — toasts stay, ctrl+alt+shift+x to screenshot", { style = "info" })
	else
		ctx.toast:hide()
		ctx.notify("debug off", { style = "info" })
	end
end

actions.debug_screenshot = function()
	local tag = "screen"
	local p = ctx.active_panel
	if not (p and p.visible) then
		for _, q in pairs(panels) do
			if q.visible then
				p = q
				break
			end
		end
	end
	if p and p.visible then
		tag = p.name
	elseif ctx.toast and ctx.toast.visible then
		tag = "toast"
	end
	local path, err = Screenshot.capture(ctx, tag)
	if path then
		ctx.notify("saved " .. path, { style = "success", duration = 5000 })
	else
		ctx.notify("screenshot failed: " .. tostring(err), { style = "error" })
	end
end

actions.debug_dump_panel = function()
	local p = ctx.active_panel
	if not (p and p.visible) then
		for _, q in pairs(panels) do
			if q.visible then
				p = q
				break
			end
		end
	end
	if not (p and p.visible) then
		ctx.notify("no visible panel", { style = "warn" })
		return
	end
	local path = string.format("/tmp/lbar_%s.bmp", p.name)
	if p:dump_bmp(path) then
		ctx.notify("saved " .. path, { style = "info" })
	else
		ctx.notify("panel dump failed", { style = "crit" })
	end
end

keybinds.build(config.keybinds)

ffi.cdef([[
  typedef struct { long tv_sec; long tv_nsec; } lbar_ts;
]])
local ts = ffi.new("lbar_ts[1]")
local function now_ms()
	libc.clock_gettime(1, ts)
	return tonumber(ts[0].tv_sec) * 1000 + tonumber(ts[0].tv_nsec) / 1e6
end

local TICK_MS = 200
local WATCH_MS = 800
local watch_accum = 0
local last_tick = now_ms()
local ev = ffi.new("lbar_event_t")

local function panel_by_popup(id)
	if not id or id < 0 then
		return nil
	end
	return ctx._panel_by_id and ctx._panel_by_id[id] or nil
end

local function panel_hit_root(rx, ry)
	for _, p in pairs(panels) do
		if p.visible and not p.destroyed
			and rx >= p.sx and rx < p.sx + p.w and ry >= p.sy and ry < p.sy + p.h then
			return p
		end
	end
	return nil
end

-- route a pointer event to a panel. wayland identifies the source surface
-- in ev.a; x11 with a pointer grab delivers everything through the grab
-- window, so the true target comes from hit-testing root coordinates. an
-- in-flight press/drag gesture keeps routing to its panel until release.
local function route_panel(ev, kind)
	if kind ~= "press" then
		local dp = ctx._drag_panel
		if dp and dp.visible then
			return dp
		end
		local pp = ctx._press_panel
		if pp and pp.visible then
			return pp
		end
	end
	if ctx.backend_kind == "wayland" then
		return panel_by_popup(ev.a)
	end
	local hit = panel_hit_root(ev.root_x, ev.root_y)
	if hit then
		return hit
	end
	return panel_by_popup(ev.a)
end

-- pointer events carry grab-window-relative coords on x11; recompute
-- surface-local coords from the root position for the routed panel
local function local_coords(p)
	if ctx.backend_kind == "wayland" then
		return ev.x, ev.y
	end
	return ev.root_x - p.sx, ev.root_y - p.sy
end

local function dismiss_outside_panels()
	for _, q in pairs(panels) do
		if q.visible and not q.destroyed and q.opts.ptr_grab ~= false then
			q:hide()
		end
	end
end

log("lbar running (%s, %dx%d, plugins=%d)", kind, ctx.scr_w, ctx.scr_h, #bar.plugins)

local ipcbuf = ffi.new("char[256]")

local function dispatch_ipc()
	if L.lbar_ipc_take(Lctx, ipcbuf, 256) == 0 then
		return
	end
	local cmd = ffi.string(ipcbuf):gsub("^%s+", ""):gsub("%s+$", "")
	if cmd == "" then
		return
	end
	local action = cmd:gsub("%s+", "_")
	if actions[action] then
		local ok, aerr = pcall(actions[action])
		if not ok then
			log("ipc action %s error: %s", action, tostring(aerr))
		end
	else
		log("ipc unknown action: %s", cmd)
	end
end

while true do
	L.lbar_poll(Lctx, 16)
	dispatch_ipc()

	while L.lbar_next_event(Lctx, ev) ~= 0 do
		local t = ev.type
		local tgt = ev.target
		if t == 4 then
			if tgt == 0 then
				bar.needs_redraw = true
			else
				-- expose/configure for one popup: redraw just that panel
				local p = panel_by_popup(ev.a)
				if p and p.visible and not p.destroyed then
					p:draw()
				end
				local vis = L.lbar_popup_visible(Lctx) ~= 0
				ctx.popup_visible = vis
				if not vis then
					for _, q in pairs(panels) do
						q.visible = false
					end
					ctx.active_plugin_name = nil
					ctx.active_panel = nil
					bar.needs_redraw = true
				end
			end
		elseif t == 1 then
			if tgt == 1 then
				local p = route_panel(ev, "motion")
				if p and not p.destroyed then
					local lx, ly = local_coords(p)
					local ok, perr = pcall(p.on_motion, p, lx, ly, ev.root_x, ev.root_y)
					if not ok then
						log("panel motion error: %s", tostring(perr))
					end
				end
			else
				bar:on_motion(ev.x, ev.y)
			end
		elseif t == 2 then
			if tgt == 2 then
				-- wayland catcher surface: press outside every panel
				if ev.button ~= 4 and ev.button ~= 5 then
					dismiss_outside_panels()
				end
			elseif tgt == 1 then
				local p = route_panel(ev, "press")
				if p and not p.destroyed then
					local lx, ly = local_coords(p)
					local inside = lx >= 0 and ly >= 0 and lx < p.w and ly < p.h
					if not inside and p.opts.ptr_grab ~= false then
						-- x11 grab delivered a press outside every panel:
						-- dismiss the panels that opt in to outside-click
						dismiss_outside_panels()
					else
						if p.name ~= "toast" and ctx.active_panel ~= p then
							-- focus follows the press (keyboard + grabs)
							ctx.active_panel = p
							ctx.active_plugin_name = p.name
							ctx.sync_kbd()
						end
						ctx.sync_ptr_grab()
						local ok, perr = pcall(p.on_press, p, ev.button, lx, ly, ev.root_x, ev.root_y)
						if not ok then
							log("panel press error: %s", tostring(perr))
						end
					end
				end
			else
				bar:on_click(ev.button, ev.x, ev.y)
			end
		elseif t == 3 then
			if tgt == 1 then
				local p = route_panel(ev, "release")
				if p and not p.destroyed then
					local lx, ly = local_coords(p)
					local ok, perr = pcall(p.on_release, p, ev.button, lx, ly, ev.root_x, ev.root_y)
					if not ok then
						log("panel release error: %s", tostring(perr))
					end
				end
				ctx._press_panel = nil
			end
		elseif t == 5 then
			if tgt == 1 then
				if ctx.active_panel and ctx.active_panel.kbd then
					local ok, perr = pcall(ctx.active_panel.on_key, ctx.active_panel, ev.keycode, ev.keystate)
					if not ok then
						log("panel key error: %s", tostring(perr))
					end
				end
			else
				local action = keybinds.lookup(ev.keycode, ev.keystate)
				if action and actions[action] then
					local ok, aerr = pcall(actions[action])
					if not ok then
						log("action %s error: %s", action, tostring(aerr))
					end
				end
			end
		elseif t == 6 or t == 7 then
			-- IME (zwp_text_input_v3): commit_string inserts at the focused
			-- input cursor (same route as pasted text); preedit_string is the
			-- composition preview shown while typing
			local p = ctx.active_panel
			if not (p and p.visible and p.input and p.input.focused) then
				for _, q in pairs(panels) do
					if q.visible and q.input and q.input.focused then
						p = q
						break
					end
				end
			end
			if p and p.visible and p.input and p.input.focused then
				local ok, terr = pcall(function()
					local text = ffi.string(ev.text)
					if t == 6 then
						if #text > 0 then
							p.input:on_key(0, false, false, text)
						end
					else
						p.input.preedit = #text > 0 and text or nil
					end
				end)
				if not ok then
					log("ime event error: %s", tostring(terr))
				end
				p:draw()
			end
		end
	end

	for _, p in pairs(panels) do
		p:tick(16)
	end
	ctx.toast:tick(16)

	local now = now_ms()
	local dt = now - last_tick
	if dt >= TICK_MS then
		bar:tick(dt)
		last_tick = now

		if auto_reload then
			watch_accum = watch_accum + dt
			if watch_accum >= WATCH_MS then
				watch_accum = 0
				if ctx.skip_reload_once then
					ctx.skip_reload_once = false
					wmtimes = PluginMgr.snapshot_mtimes(wpaths)
				elseif PluginMgr.watch(ctx, bar, wpaths, wmtimes) then
					log("change detected, reloading...")
					local ok_r, rerr = pcall(reload_all)
					if not ok_r then
						log("hot reload crashed, keeping old state: %s", tostring(rerr))
						ctx.notify(I18n.t("reload failed: %s", tostring(rerr)), { style = "error" })
					end
					wmtimes = PluginMgr.snapshot_mtimes(wpaths)
					ctx.skip_reload_once = false
				end
			end
		end
	end
end
