#!/usr/bin/env luajit
-- tools/plugin_test.lua — 无头插件全量冒烟测试
--
-- 不连接 Wayland/X11：用纯 Lua 桩（stub）替代 ctx.L / ctx.AUD / 主题，
-- 对 config.lua 中启用的每个插件执行完整生命周期：
--   require → init → width → draw(bar item) → tick ×N
--   → 面板 draw → 交互(on_press/on_release/on_motion/on_key) → resize 重排
--   → shutdown
-- 任何一步抛错都会记为 FAIL 并以非零码退出。
--
-- 用法：
--   luajit tools/plugin_test.lua            # 全部插件
--   luajit tools/plugin_test.lua clock cpu  # 指定插件
local ffi = require("ffi")

local here = arg[0]:match("^(.*)/tools/") or "."
package.path = here .. "/?.lua;" .. package.path

local Theme = require("core.theme")

-- ────────────────────────────────────────────────────────────── stubs
local function intp(v)
	local p = ffi.new("int[1]")
	if v then
		p[0] = v
	end
	return p
end

-- popup id → 记录的尺寸，供 lbar_popup_size/flush 回读
local popup_size = {}
local next_popup = 1

local L = {}
-- 文本度量：每字符 8px 宽、行高 18（确定性，跨机器一致）
function L.xft_text_extent(_, s, w, h)
	local n = 0
	if s ~= nil then
		n = #ffi.string(s)
	end
	w[0] = n * 8
	h[0] = 18
end
function L.xft_primary_line_height()
	return 18
end
function L.xft_draw_rgba() end
function L.surf_fill() end
function L.surf_rrect_aa() end

function L.lbar_popup_create(_, w, h)
	local id = next_popup
	next_popup = next_popup + 1
	popup_size[id] = { w = w, h = h }
	return id
end
function L.lbar_popup_resize(_, id, w, h)
	popup_size[id] = { w = w, h = h }
	return 0
end
function L.lbar_popup_size(_, id, w, h)
	local s = popup_size[id] or { w = 0, h = 0 }
	w[0] = s.w
	h[0] = s.h
end
function L.lbar_popup_flush(_, id, _, sw, sh, w, h)
	-- 返回实时尺寸：与请求尺寸一致（桩不做 compositor 钳制）
	if w then
		w[0] = sw
	end
	if h then
		h[0] = sh
	end
end
function L.lbar_popup_move() end
function L.lbar_popup_show() end
function L.lbar_popup_hide() end
function L.lbar_popup_visible()
	return 0
end
function L.lbar_kbd_grab()
	return 0
end
function L.lbar_kbd_ungrab()
	return 0
end
function L.lbar_ptr_grab()
	return 0
end
function L.lbar_ptr_ungrab() end
function L.lbar_outside_catch()
	return 0
end
function L.lbar_ti_enable()
	return 0
end
function L.lbar_ti_disable()
	return 0
end
function L.lbar_ti_set_cursor()
	return 0
end
function L.lbar_screen_w()
	return 1920
end
function L.lbar_screen_h()
	return 1080
end
function L.lbar_key_lookup(_, _, _, buf, n)
	if buf then
		ffi.fill(buf, 1)
	end
	return 0
end
function L.lbar_x_get_region()
	return -1
end
function L.lbar_ipc_take()
	return 0
end
function L.lbar_tray_init()
	return 0
end
function L.lbar_tray_available()
	return 1
end
function L.lbar_tray_count()
	return 2
end
function L.lbar_tray_layout()
	return 0
end
function L.lbar_tray_blit()
	return 0
end
function L.lbar_tray_click()
	return 0
end
function L.lbar_tray_shutdown() end
function L.lbar_bar_width()
	return 1920
end
function L.lbar_bar_height()
	return 40
end
function L.lbar_bar_create()
	return 0
end
function L.lbar_bar_flush() end

local AUD = {}
for _, fn in ipairs({
	"audio_init", "audio_shutdown", "audio_play", "audio_toggle_pause",
	"audio_stop", "audio_is_playing", "audio_is_paused", "audio_set_volume",
	"audio_get_position", "audio_get_duration", "audio_scan_dir",
	"audio_scan_get", "audio_seek", "audio_probe_duration", "audio_play_sfx",
	"audio_finished",
}) do
	AUD[fn] = function()
		return 0
	end
end

-- 可绘表面桩：bar item 的 draw 接收它作为 s
local Surface = {}
Surface.__index = Surface
function Surface.new(w, h)
	return setmetatable({ w = w, h = h, surf = ffi.new("uint32_t[?]", w * h) }, Surface)
end
function Surface:clear() end
function Surface:rect() end
function Surface:rrect() end
function Surface:text() end
function Surface:line() end

-- ────────────────────────────────────────────────────────────── ctx
local cfg = dofile(here .. "/config.lua")

local function new_ctx()
	local width_cache = {}
	local ctx = {
		SCRIPT_DIR = here,
		lbar_dir = here,
		config_path = here .. "/config.lua",
		L = L,
		Lctx = nil,
		ft_ctx = nil,
		config = cfg,
		theme = Theme.build(cfg),
		backend_kind = "x11",
		scr_w = 1920,
		scr_h = 1080,
		debug = false,
		auto_reload = true,
		popup_visible = false,
		active_plugin_name = nil,
		active_panel = nil,
		actions = {},
		_panels = {},
		_panel_by_id = {},
		AUD = AUD,
		log = function() end,
		notify = function() end,
		_now_ms = 0,
	}
	ctx.bar = { plugins = {}, h = 40, w = 1920, pos = "top", needs_redraw = false, padding = 16, gap = 4 }
	ctx.get_line_height = function()
		return 18
	end
	ctx.get_text_size = function(s)
		return #(s or "") * 8, 18
	end
	ctx.text_width = function(s)
		s = s or ""
		local v = width_cache[s]
		if v then
			return v
		end
		v = #s * 8
		width_cache[s] = v
		return v
	end
	ctx.register_panel = function(name, panel)
		ctx._panel_by_id[panel.id] = panel
		ctx._panels[name] = panel
		ctx.actions["toggle_" .. name] = function() end
	end
	function ctx.show_panel(name, ax, ay, dir, align)
		local p = ctx._panels[name]
		if not p then
			return
		end
		if p.visible then
			p:hide()
			return
		end
		if ax then
			p:show_at(ax, ay, dir, align)
		else
			p:show()
		end
	end
	function ctx.toggle_panel(name)
		ctx.show_panel(name)
	end
	function ctx.close_panels()
		for _, p in pairs(ctx._panels) do
			if p.visible then
				p:hide()
			end
		end
	end
	function ctx.sync_kbd() end
	function ctx.sync_ptr_grab() end
	-- 内置动作（插件经 ctx.actions.xxx 调用）
	for _, a in ipairs({
		"toggle_theme", "hot_reload", "quit", "close_panels", "hide_all_windows",
		"toggle_debug_mode", "debug_screenshot", "debug_dump_panel",
		"toggle_auto_reload", "move_win_left", "move_win_right", "move_win_up",
		"move_win_down", "resize_win_wider", "resize_win_narrower",
		"resize_win_taller", "resize_win_shorter", "reset_active_window",
	}) do
		ctx.actions[a] = function() end
	end
	return ctx
end

-- ────────────────────────────────────────────────────────────── runner
local failures = {}
local function fail(plugin, stage, err)
	failures[#failures + 1] = string.format("%s: %s → %s", plugin, stage, tostring(err))
end

local function step(plugin, stage, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		fail(plugin, stage, err)
		return false
	end
	return true
end

local function test_plugin(name)
	local ctx = new_ctx()
	local before = {}
	for k in pairs(ctx._panels) do
		before[k] = true
	end

	package.loaded["plugins." .. name] = nil
	local ok, mod = pcall(require, "plugins." .. name)
	if not ok or type(mod) ~= "table" then
		fail(name, "require", mod)
		return false
	end

	if mod.init and not step(name, "init", mod.init, ctx) then
		return false
	end

	-- bar item width 契约：number 或 nil（0 合法 = 隐藏）
	if mod.width then
		local ok2, w = pcall(mod.width, ctx)
		if not ok2 then
			fail(name, "width", w)
		elseif w ~= nil and type(w) ~= "number" then
			fail(name, "width", "返回非数字：" .. tostring(w))
		end
	end

	-- bar item 绘制
	if mod.draw then
		local w = 80
		if mod.width then
			local ok3, v = pcall(mod.width, ctx)
			if ok3 and type(v) == "number" and v > 0 then
				w = v
			end
		end
		step(name, "draw(bar)", mod.draw, ctx, Surface.new(w, 40), 0, 0, w, 40)
	end

	-- bar item 点击/滚轮
	if mod.on_click then
		step(name, "on_click", mod.on_click, ctx, 1, 10, 20, 100, 60)
		step(name, "on_click(scroll)", mod.on_click, ctx, 4, 10, 20, 100, 60)
	end

	-- tick ×若干
	for i = 1, 3 do
		if mod.tick then
			step(name, "tick#" .. i, mod.tick, ctx, 16)
		end
	end

	-- 该插件新注册的每个面板：draw + 交互 + 重排
	for pname, panel in pairs(ctx._panels) do
		if not before[pname] and panel.name ~= "toast" then
			step(name, "panel[" .. pname .. "]:draw", panel.draw, panel)
			step(name, "panel[" .. pname .. "]:on_press", panel.on_press, panel, 1, 30, 30, 30, 30)
			step(name, "panel[" .. pname .. "]:on_motion", panel.on_motion, panel, 40, 40, 40, 40)
			step(name, "panel[" .. pname .. "]:on_release", panel.on_release, panel, 1, 40, 40, 40, 40)
			step(name, "panel[" .. pname .. "]:on_key", panel.on_key, panel, 0xff1b, 0)
			-- 重排：小尺寸 → 大尺寸
			step(name, "panel[" .. pname .. "]:resize(380x300)", panel.resize, panel, 380, 300)
			step(name, "panel[" .. pname .. "]:draw(small)", panel.draw, panel)
			step(name, "panel[" .. pname .. "]:resize(860x960)", panel.resize, panel, 860, 960)
			step(name, "panel[" .. pname .. "]:draw(large)", panel.draw, panel)
			-- 拖动/移动路径
			step(name, "panel[" .. pname .. "]:move_to", panel.move_to, panel, 120, 90)
			step(name, "panel[" .. pname .. "]:live_resize", panel.live_resize, panel, 520, 420)
		end
	end

	if mod.shutdown then
		step(name, "shutdown", mod.shutdown)
	end
	return true
end

-- ────────────────────────────────────────────────────────────── main
-- 动画配置覆盖检查：panels.*.anim 与 animation.style 只允许支持取值，
-- 且默认配置应覆盖全部 6 种（auto/slide_up/slide_down/slide_left/slide_right/none）
local ANIM_SUPPORTED = { "auto", "slide_up", "slide_down", "slide_left", "slide_right", "none" }
do
	local supported = {}
	for _, a in ipairs(ANIM_SUPPORTED) do
		supported[a] = true
	end
	local used = {}
	if cfg.animation then
		if cfg.animation.style and not supported[cfg.animation.style] then
			failures[#failures + 1] = "anim: animation.style 不支持的取值 '" .. tostring(cfg.animation.style) .. "'"
		end
		used[cfg.animation.style or "auto"] = true
	end
	for name, pc in pairs(cfg.panels or {}) do
		local a = pc.anim or "auto"
		if not supported[a] then
			failures[#failures + 1] = string.format("anim: panels.%s 不支持的取值 '%s'", name, tostring(a))
		end
		used[a] = true
	end
	for _, a in ipairs(ANIM_SUPPORTED) do
		if not used[a] then
			failures[#failures + 1] = "anim: 默认配置未覆盖取值 '" .. a .. "'"
		end
	end
	if #failures == 0 then
		print("anim coverage: " .. #ANIM_SUPPORTED .. "/" .. #ANIM_SUPPORTED .. " styles covered")
	end
end

local want = {}
for i = 1, #arg do
	want[arg[i]] = true
end

local list = {}
for _, name in ipairs(cfg.plugins or {}) do
	if next(want) == nil or want[name] then
		list[#list + 1] = name
	end
end

-- 额外确保 _testprobe 之类的开发插件不参与（仅 config 列表）
print(string.format("plugin smoke test: %d plugins", #list))
local pass = 0
for _, name in ipairs(list) do
	local n0 = #failures
	local ok = test_plugin(name)
	if ok and #failures == n0 then
		print(string.format("  PASS  %s", name))
		pass = pass + 1
	else
		print(string.format("  FAIL  %s", name))
	end
end

print(string.format("\n%d/%d plugins passed", pass, #list))
for _, f in ipairs(failures) do
	print("  " .. f)
end
os.exit(#failures == 0 and 0 or 1)
