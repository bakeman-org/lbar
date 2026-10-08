#!/usr/bin/env luajit
local SCRIPT_DIR = (arg[0] or "lbar.lua"):match("^(.*)/[^/]*$") or "."
if SCRIPT_DIR == "" then
	SCRIPT_DIR = "."
end
if SCRIPT_DIR:sub(1, 1) ~= "/" then
	local pwd = os.getenv("PWD")
	if pwd and pwd:sub(1, 1) == "/" and pwd ~= "" then
		SCRIPT_DIR = pwd:gsub("/$", "") .. "/" .. SCRIPT_DIR
	end
end
package.path = SCRIPT_DIR .. "/?.lua;" .. package.path
package.cpath = SCRIPT_DIR .. "/?.so;" .. package.cpath

local init = require("core.init")(SCRIPT_DIR)
local Bar = require("core.bar")
local PluginMgr = require("core.plugins")
local Keybinds = require("core.keybinds")
local Toast = require("core.toast")
local Screenshot = require("core.screenshot")
local Theme = require("core.theme")
local Util = require("core.util")
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

function ctx.show_panel(name, anchor_x, anchor_y, direction)
	for n, p in pairs(panels) do
		if n ~= name and p.visible then
			p:hide(true)
		end
	end
	local p = panels[name]
	if not p then
		return
	end
	if p.visible then
		p:hide()
		ctx.active_plugin_name = nil
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
		return
	end
	if anchor_x then
		p:show_at(anchor_x, anchor_y, direction)
	else
		p:show()
	end
	ctx.active_panel = p
	ctx.active_plugin_name = name
	if ctx.bar then
		ctx.bar.needs_redraw = true
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
	if p.user_pos then
		ctx.show_panel(name)
		return
	end
	local a = p.last_anchor
	if a then
		ctx.show_panel(name, a.x, a.y, a.dir)
	else
		ctx.show_panel(name)
	end
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
local theme_dark = (config.theme_mode or "dark") ~= "light"

local function reload_all()
	local ok, newcfg = pcall(dofile, CONFIG_PATH)
	if not ok or type(newcfg) ~= "table" then
		log("config reload failed: %s", tostring(newcfg))
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

	config = newcfg
	ctx.config = config
	ctx.theme = Theme.build(config)
	theme_dark = (config.theme_mode or "dark") ~= "light"

	if font_changed then
		local ok_f, nf = pcall(load_font, config)
		if ok_f and nf then
			L.xft_done(ft_ctx)
			ft_ctx = nf
			ctx.ft_ctx = nf
			log("font reloaded: %s @ %d", config.font_path, config.font_size or 14)
		else
			log("font reload failed: %s", tostring(nf))
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

	bar, err = build_bar(config)
	if not bar then
		log("bar rebuild failed: %s", tostring(err))
		os.exit(1)
	end
	ctx.bar = bar

	keybinds.build(config.keybinds)

	wpaths = watch_paths(config)
	wmtimes = PluginMgr.snapshot_mtimes(wpaths)
	log("hot reload done: %s @ %s h=%d plugins=%d", kind, bar.pos, bar.h, #bar.plugins)
end

actions.hot_reload = reload_all
actions.toggle_auto_reload = function()
	auto_reload = not auto_reload
	ctx.notify(auto_reload and "auto reload on" or "auto reload off", { style = "info" })
end
actions.hide_all_windows = function()
	ctx.close_panels()
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

local function visible_panel()
	local ap = ctx.active_panel
	if ap and ap.visible then
		return ap
	end
	for _, p in pairs(panels) do
		if p.visible then
			return p
		end
	end
	return nil
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
				local vis = L.lbar_popup_visible(Lctx) ~= 0
				ctx.popup_visible = vis
				if vis then
					if ctx.active_panel then
						ctx.active_panel:draw()
					end
				else
					for _, p in pairs(panels) do
						p.visible = false
					end
					ctx.active_plugin_name = nil
					ctx.active_panel = nil
					bar.needs_redraw = true
				end
			end
		elseif t == 1 then
			if tgt == 1 then
				local p = visible_panel()
				if p then
					local ok, perr = pcall(p.on_motion, p, ev.x, ev.y, ev.root_x, ev.root_y)
					if not ok then
						log("panel motion error: %s", tostring(perr))
					end
				end
			else
				bar:on_motion(ev.x, ev.y)
			end
		elseif t == 2 then
			if tgt == 1 then
				local p = visible_panel()
				if p then
					if (ev.x < 0 or ev.y < 0 or ev.x >= p.w or ev.y >= p.h)
						and p.opts.ptr_grab ~= false then
						p:hide()
					else
						local ok, perr = pcall(p.on_press, p, ev.button, ev.x, ev.y, ev.root_x, ev.root_y)
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
				local p = visible_panel()
				if p then
					local ok, perr = pcall(p.on_release, p, ev.button, ev.x, ev.y, ev.root_x, ev.root_y)
					if not ok then
						log("panel release error: %s", tostring(perr))
					end
				end
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
				if PluginMgr.watch(ctx, bar, wpaths, wmtimes) then
					log("change detected, reloading...")
					reload_all()
				end
			end
		end
	end
end
