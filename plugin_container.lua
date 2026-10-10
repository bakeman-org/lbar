#!/usr/bin/env luajit
-- plugin_container.lua — 独立插件开发宿主（mini-lbar）
--
-- 用法:
--   luajit plugin_container.lua <plugin> [config.lua]
--   <plugin> 可以是插件名（volume）或路径（plugins/volume.lua）
--
-- 与 lbar.lua 相同的真实后端（wayland/X11）、字体、面板、事件循环，
-- 但 bar 只加载一个插件。改插件文件保存后自动热重载（无需碰 config.lua）。
-- 退出：在本终端按 ctrl+c。

local function dir_of(p)
	local d = (p or ""):match("^(.*)/[^/]*$")
	if not d or d == "" then
		d = "."
	end
	return d
end

local SCRIPT_DIR = dir_of(arg[0] or "plugin_container.lua")
if SCRIPT_DIR:sub(1, 1) ~= "/" then
	local pwd = os.getenv("PWD")
	if pwd and pwd:sub(1, 1) == "/" and pwd ~= "" then
		SCRIPT_DIR = pwd:gsub("/$", "") .. "/" .. SCRIPT_DIR
	end
end
package.path = SCRIPT_DIR .. "/?.lua;" .. package.path
package.cpath = SCRIPT_DIR .. "/?.so;" .. package.cpath

local function usage(err)
	io.stderr:write((err and err .. "\n" or ""))
	io.stderr:write("usage: luajit plugin_container.lua [<plugin>[,<plugin>...] | --all] [options]\n")
	io.stderr:write("  <plugin>    插件名（volume）或路径（plugins/volume.lua），逗号/空格分隔多个\n")
	io.stderr:write("  --all       加载 config.lua 里的全部插件（完整模拟 lbar 行为）\n")
	io.stderr:write("  --config=   配置文件，默认 SCRIPT_DIR/config.lua\n")
	io.stderr:write("  --no-keybinds  不注册 compositor/X11 键位（避免与正在运行的真实 lbar 冲突）\n")
	io.stderr:write("  保存任一插件文件自动热重载全部已加载插件；ctrl+c 退出\n")
	os.exit(1)
end

-- 解析所有参数：位置参数是插件（支持逗号分隔），--config= 指定配置
local plugin_args = {}
local CONFIG_PATH
local opt_all, opt_no_keybinds = false, false
local ai = 1
while arg[ai] do
	local a = arg[ai]
	if a == "" then
		-- skip
	elseif a:sub(1, 9) == "--config=" then
		CONFIG_PATH = a:sub(10)
	elseif a == "--config" and arg[ai + 1] then
		CONFIG_PATH = arg[ai + 1]
		ai = ai + 1
	elseif a == "--all" then
		opt_all = true
	elseif a == "--no-keybinds" then
		opt_no_keybinds = true
	elseif a:sub(1, 2) == "--" then
		usage("error: unknown option: " .. a)
	else
		for name in a:gmatch("[^,]+") do
			plugin_args[#plugin_args + 1] = name
		end
	end
	ai = ai + 1
end

if not CONFIG_PATH or CONFIG_PATH == "" then
	CONFIG_PATH = SCRIPT_DIR .. "/config.lua"
end

if not CONFIG_PATH or CONFIG_PATH == "" then
	CONFIG_PATH = SCRIPT_DIR .. "/config.lua"
end

local init = require("core.init")(SCRIPT_DIR)
local Bar = require("core.bar")
local PluginMgr = require("core.plugins")
local Keybinds = require("core.keybinds")
local Toast = require("core.toast")
local Theme = require("core.theme")
local Util = require("core.util")
local I18n = require("core.i18n")
local ffi = init.ffi
local libc = init.libc
local L = init.L
local AUD = init.AUD
local log = Util.logger("container")

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

-- --all / 无参数：加载 config.plugins 全集
if #plugin_args == 0 then
	for _, name in ipairs(config.plugins or {}) do
		plugin_args[#plugin_args + 1] = name
	end
end
if #plugin_args == 0 then
	usage("error: no plugins (config.lua has empty plugins list)")
end
local plugin_names = {}
local plugin_paths = {}
for _, pa in ipairs(plugin_args) do
	local name = pa:match("([^/]+)%.lua$") or pa:match("([^/]+)$")
	local path
	if pa:match("%.lua$") then
		path = pa
		if path:sub(1, 1) ~= "/" then
			path = SCRIPT_DIR .. "/" .. path
		end
	else
		path = SCRIPT_DIR .. "/plugins/" .. name .. ".lua"
	end
	local fh = io.open(path, "rb")
	if not fh then
		usage("error: plugin file not found: " .. path)
	end
	fh:close()
	plugin_names[#plugin_names + 1] = name
	plugin_paths[#plugin_paths + 1] = path
end

local Lctx = L.lbar_open()
if Lctx == nil then
	io.stderr:write("error: lbar_open failed\n")
	io.stderr:write("  最常见原因：已有另一个 lbar 实例在运行（真 bar 或另一个容器），\n")
	io.stderr:write("  C 层用 $XDG_RUNTIME_DIR/lbar.lock 强制单例。先退出它再启动容器。\n")
	os.exit(1)
end
local kind = ffi.string(L.lbar_backend(Lctx))

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
	_panels = {},
	_panel_by_id = {},
}
ctx.scr_w = L.lbar_screen_w(Lctx)
ctx.scr_h = L.lbar_screen_h(Lctx)

local _tw_cache = {}
local _th_cache = {}
local _mw, _mh = ffi.new("int[1]"), ffi.new("int[1]")
local _line_h = L.xft_primary_line_height(ft_ctx)
local function clear_text_caches()
	for k in pairs(_tw_cache) do
		_tw_cache[k] = nil
	end
	for k in pairs(_th_cache) do
		_th_cache[k] = nil
	end
	_line_h = L.xft_primary_line_height(ft_ctx)
end
function ctx.get_text_size(s)
	local w = _tw_cache[s]
	if w then
		return w, _th_cache[s]
	end
	L.xft_text_extent(ft_ctx, s, _mw, _mh)
	_tw_cache[s] = _mw[0]
	_th_cache[s] = _mh[0]
	return _mw[0], _mh[0]
end
function ctx.text_width(s)
	local v = _tw_cache[s]
	if v then
		return v
	end
	L.xft_text_extent(ft_ctx, s, _mw, _mh)
	_tw_cache[s] = _mw[0]
	_th_cache[s] = _mh[0]
	return _mw[0]
end
function ctx.get_line_height()
	return _line_h
end

ctx.theme = Theme.build(config)
I18n.init(ctx)
ctx.toast = Toast.new(ctx)
ctx.notify = function(text, opts)
	ctx.toast:show(text, opts)
end

local panels = {}
local bar
local function bar_needs_redraw()
	if bar then
		bar.needs_redraw = true
	end
end

function ctx.register_panel(name, panel)
	panels[name] = panel
	ctx.actions["toggle_" .. name] = function()
		ctx.toggle_panel(name)
	end
end

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
	local ime = want and p.input and p.input.focused
	if ime and not ctx._ime_on then
		ctx._ime_on = true
		local r = p.input
		ctx.L.lbar_ti_enable(ctx.Lctx, r.x or 0, r.y or 0, r.w or 0, r.h or 0)
	elseif not ime and ctx._ime_on then
		ctx._ime_on = false
		ctx.L.lbar_ti_disable(ctx.Lctx)
	end
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

function ctx.sync_ptr_grab()
	local on = false
	if ctx.backend_kind == "wayland" then
		for _, q in pairs(panels) do
			if q.visible and not q.destroyed and q.opts.ptr_grab ~= false then
				on = true
				break
			end
		end
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
		bar_needs_redraw()
		return
	end
	if anchor_x then
		p:show_at(anchor_x, anchor_y, direction, align)
	else
		p:show()
	end
	bar_needs_redraw()
end

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
	bar_needs_redraw()
end

-- show_panel/close_panels 引用 bar，声明提升：bar 建好后赋值

local actions = ctx.actions
actions.quit = function()
	os.exit(0)
end
actions.close_panels = function()
	ctx.close_panels()
end

local function build_bar(cfg)
	local b, err = Bar.new(ctx, cfg)
	if not b then
		return nil, err
	end
	PluginMgr.load_all(ctx, b, plugin_names)
	if #b.plugins == 0 then
		return nil, "no plugin loaded from: " .. table.concat(plugin_names, ", ")
	end
	return b
end

-- 面板自动展示：面板类插件启动即可见；bar item 类插件靠点击
local function auto_show_panel()
	local shown = 0
	for name, p in pairs(panels) do
		if name ~= "toast" and not p.destroyed then
			show_restored(name)
			shown = shown + 1
		end
	end
	if shown > 0 then
		log("%d panel(s) auto-shown — click bar items to toggle, drag headers to arrange", shown)
	end
	return shown > 0
end

bar = assert(build_bar(config))
ctx.bar = bar

-- 键位：与 lbar 相同的 config.keybinds（wayland → compositor binds + lbar-cli
-- IPC 转发；X11 → 直接 grab）。--no-keybinds 可关（与真实 lbar 并行跑时避免抢绑定）。
-- IPC 事件循环里按 action 名派发（见 dispatch_ipc）。
local keybinds = Keybinds.new(ctx)
local rebuild -- 前向声明：actions.hot_reload / watcher 都会调用
local actions = ctx.actions
actions.quit = function()
	os.exit(0)
end
actions.close_panels = function()
	ctx.close_panels()
end
actions.hot_reload = function()
	log("hot reload requested via keybind")
	rebuild()
end-- ctrl+alt+d：隐藏/恢复全部面板（toast 不计入，与 lbar 行为一致）
local hidden_restore = nil
actions.hide_all_windows = function()
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
if not opt_no_keybinds then
	keybinds.build(config.keybinds)
end

local shown = auto_show_panel()
log("container running (%s, %dx%d) — plugins: %s", kind, ctx.scr_w, ctx.scr_h,
	table.concat(plugin_names, ", "))
for _, pp in ipairs(plugin_paths) do
	log("  edit %s and save to hot-reload", pp)
end
log("  ctrl+c in this terminal to quit")

local ts = ffi.new("lbar_ts[1]")
local function now_ms()
	libc.clock_gettime(1, ts)
	return tonumber(ts[0].tv_sec) * 1000 + tonumber(ts[0].tv_nsec) / 1e6
end

rebuild = function()
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

	for _, name in ipairs(plugin_names) do
		package.loaded["plugins." .. name] = nil
	end
	-- ui2 等声明式框架层也要清，改框架本身才能热重载生效
	package.loaded["core.ui2"] = nil

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
	clear_text_caches()

	local ok, b = pcall(build_bar, config)
	if not ok or not b then
		log("rebuild failed: %s — fix the plugin and save again", tostring(b))
		-- 保持退出前的空 bar，等待下一次文件修改重试
		bar = nil
		ctx.bar = nil
		return
	end
	bar = b
	ctx.bar = bar
	if not opt_no_keybinds then
		keybinds.build(config.keybinds)
	end
	auto_show_panel()
	log("plugins reloaded: %s", table.concat(plugin_names, ", "))
end

local TICK_MS = 200
local WATCH_MS = 800
local watch_accum = 0
local last_mtimes = {}
for _, pp in ipairs(plugin_paths) do
	last_mtimes[pp] = Util.file_mtime(pp)
end
local last_tick = now_ms()
local last_loop = now_ms()
local ev = ffi.new("lbar_event_t")

-- IPC：compositor 键位触发 → lbar-cli <action> → 本容器执行（与 lbar 相同）
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

local function route_panel(ev, ekind)
	if ekind ~= "press" then
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

while true do
	L.lbar_poll(Lctx, 16)
	dispatch_ipc()

	while L.lbar_next_event(Lctx, ev) ~= 0 do
		local t = ev.type
		local tgt = ev.target
		if t == 4 then
			if tgt == 0 then
				bar_needs_redraw()
			else
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
					bar_needs_redraw()
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
				if bar then
					bar:on_motion(ev.x, ev.y)
				end
			end
		elseif t == 2 then
			if tgt == 2 then
				if ev.button ~= 4 and ev.button ~= 5 then
					dismiss_outside_panels()
				end
			elseif tgt == 1 then
				local p = route_panel(ev, "press")
				if p and not p.destroyed then
					local lx, ly = local_coords(p)
					local inside = lx >= 0 and ly >= 0 and lx < p.w and ly < p.h
					if not inside and p.opts.ptr_grab ~= false then
						dismiss_outside_panels()
					else
						if p.name ~= "toast" and ctx.active_panel ~= p then
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
				if bar then
					bar:on_click(ev.button, ev.x, ev.y)
				end
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
				elseif not opt_no_keybinds then
					-- 无焦点面板：全局键位（X11 grab 路径；wayland 走 IPC）
					local action = keybinds.lookup(ev.keycode, ev.keystate)
					if action and actions[action] then
						local ok, aerr = pcall(actions[action])
						if not ok then
							log("action %s error: %s", action, tostring(aerr))
						end
					end
				end
			end
		elseif t == 6 or t == 7 then
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

	if bar and bar.needs_redraw then
		bar:draw()
	end

	local now = now_ms()
	local dt = now - last_loop
	if dt < 1 then
		dt = 1
	end
	last_loop = now
	ctx._now_ms = now
	for _, p in pairs(panels) do
		p:tick(dt)
	end
	ctx.toast:tick(dt)

	local bdt = now - last_tick
	if bdt >= TICK_MS then
		if bar then
			bar:tick(bdt)
		end
		last_tick = now

		watch_accum = watch_accum + bdt
		if watch_accum >= WATCH_MS then
			watch_accum = 0
			local changed = nil
			for _, pp in ipairs(plugin_paths) do
				local mt = Util.file_mtime(pp)
				if mt and mt ~= last_mtimes[pp] then
					last_mtimes[pp] = mt
					changed = pp
				end
			end
			if changed then
				log("change detected in %s, reloading ...", changed)
				local ok, rerr = pcall(rebuild)
				if not ok then
					log("hot reload crashed: %s", tostring(rerr))
				end
			end
		end
	end
end
