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

-- ── ui2 框架单测：state 响应式 / 树构建 / measure / each / component / if_ ──
local n0 = #failures
local ui2 = require("core.ui2")

local st = ui2.state({ count = 0, name = "x" })
local sub_n = 0
st:subscribe(function() sub_n = sub_n + 1 end)
st.count = 1
st.name = "y"
st:set({ a = 1, b = 2 })
if sub_n ~= 4 or st.count ~= 1 or st.a ~= 1 then
	failures[#failures + 1] = "ui2: state 响应式订阅失败"
end

-- ── ui2 visible 翻转防护：render 中途 state 变更 → 未 measure 子树被画 ──
-- （真实容器点击 tab 曾触发 "arithmetic on nil" 布局错误）
do
	local vctx = new_ctx()
	local vst = ui2.state({ on = false })
	local okv, vb = pcall(ui2.panel, vctx, { name = "ui2vis", title = "V" })
	if not okv or not vb then
		failures[#failures + 1] = "ui2 visible: panel 构建失败"
	else
		ui2.reactive(vst, vb, vctx)
		vb:column({ pad = 8 })
			:button({ label = "go", action = function() vst.on = true end })
			:column({ pad = 8, visible = function() return vst.on end })
				:top_app_bar({ title = "t", actions = { "gear" } })
				:range_slider({ value_low = 10, value_high = 50 })
			:end_()
		:end_()
		local vp = vb.panel
		vp:show()
		vp:draw()
		local vui = vp.ui
		do
			-- 绕过 Panel:draw 的 pcall（它会吞 render 错误），直接暴露
			local okr, errr = xpcall(function()
				vb:render(vp)
			end, debug.traceback)
			if not okr then
				failures[#failures + 1] = "ui2 visible: render 报错: " .. tostring(errr)
			end
		end
		-- Panel:draw 内部 pcall 会吞掉 opts.draw 的错误并写 ctx.log：
		-- 拦截 log 抓 "draw error"，否则 nil 布局错误对测试不可见
		local draw_errors = {}
		vctx.log = function(fmt, ...)
			local s = string.format(fmt, ...)
			if s:find("draw error", 1, true) then
				draw_errors[#draw_errors + 1] = s
			end
		end
		-- release 命中 button：render 中翻转 visible，未 measure 的
		-- top_app_bar/range_slider 子树立即被绘制（无 nil 布局错误 + 内容可见）
		local hit_btn = false
		for y = 40, 120, 4 do
			vst.on = false
			vp:draw()
			-- press 帧（id_button 捕获 active_id）→ release 帧（触发 action）
			vui.mx, vui.my = 30, y
			vui.mdown = true
			pcall(vp.draw, vp)
			vui.mdown = false
			vui.mrelease = { x = 30, y = y }
			pcall(vp.draw, vp)
			vui.mrelease = nil
			if vst.on then
				hit_btn = true
				break
			end
		end
		vctx.log = nil
		if #draw_errors > 0 then
			failures[#failures + 1] = "ui2 visible: render 中途翻转报错: " .. draw_errors[1]
		elseif not hit_btn then
			failures[#failures + 1] = "ui2 visible: button action 未触发（坐标未命中？）"
		end
		vp:hide()
	end
end

local uctx = new_ctx()
local okb, b = pcall(ui2.panel, uctx, { name = "ui2t", title = "T" })
if not okb or not b then
	failures[#failures + 1] = "ui2: panel 构建失败: " .. tostring(b)
else
	b:column({ pad = 0, gap = 0 })
		:h1("H1")
		:p("body")
		:row({ gap = 4 })
			:text("a")
			:text("bb")
		:end_()
		:each({ "x", "y", "z" }, function(item, _, bb)
			bb:p(item)
		end)
		:if_(true, function(bb) bb:p("yes") end)
		:if_(false, function(bb) bb:p("no") end)
		:unless(false, function(bb) bb:p("unless") end)
	:end_()
	local col = b.children[1]
	if #col.children ~= 8 then
		failures[#failures + 1] = "ui2: 树节点数错误（期望 8，得 " .. #col.children .. "）"
	end
	if col.children[3].kind ~= "row" or #col.children[3].children ~= 2 then
		failures[#failures + 1] = "ui2: :row 嵌套结构错误"
	end
	if col.children[4].opts.value ~= "x" then
		failures[#failures + 1] = "ui2: :each 展开顺序错误"
	end
	local m = b:measure()
	-- h1(30) + p(18) + row(34) + 3*each(54) + if(18) + unless(18)
	if m.H ~= 172 then
		failures[#failures + 1] = "ui2: measure 高度错误（期望 172，得 " .. m.H .. "）"
	end

	local function ListItem(b2, opts)
		b2:row({ pad = 0, gap = 4 })
			:p({ value = opts.label })
		:end_()
	end
	local b2 = ui2.panel(uctx, { name = "ui2t2" })
	b2:column({ pad = 0, gap = 0 })
		:component(ListItem, { label = "first" })
		:component(ListItem, { label = "second" })
	:end_()
	if #b2.children[1].children ~= 2 then
		failures[#failures + 1] = "ui2: :component 复用展开数量错误"
	end
end

if #failures == n0 then
	print("ui2 framework: state / tree / measure / each / component / if_ ok")
end

-- ── ui2 MIUIX 部件单测：全部部件 measure + render 干跑 ──
local n1 = #failures
do
	local st2 = ui2.state({ tab = 1, check = false, v = 5, color = 0x123456 })
	local mctx = new_ctx()
	local mb, mberr = pcall(ui2.panel, mctx, { name = "ui2miuix", title = "T" })
	if not mb or not mberr then
		failures[#failures + 1] = "ui2 miuix: panel 构建失败: " .. tostring(mberr)
	else
		local okm, errm = pcall(function()
			mberr:column({ pad = 12, gap = 10 })
				:small_title("basic")
				:row({ gap = 8 })
					:checkbox({ value = function() return st2.check end })
					:radio({ value = function() return st2.tab == 1 end })
					:badge({})
					:badge({ count = 9 })
				:end_()
				:row({ gap = 8 })
					:icon_button({ icon = "gear", tooltip = "settings" })
					:fab({ icon = "plus" })
				:end_()
				:toolbar({ icons = { "star", "heart", "bell" } })
				:small_title("selection")
				:list_item({ title = "wifi", summary = "connected", icon = "wifi", right = "switch",
					value = function() return st2.check end })
				:switch_preference({ title = "wifi pref", icon = "wifi",
					value = function() return st2.check end })
				:arrow_preference({ title = "about" })
				:checkbox_preference({ title = "check pref",
					value = function() return st2.check end })
				:radio_preference({ title = "radio pref", value = true })
				:basic_component({ title = "basic comp", icon = "folder" })
				:list_item({ title = "version", right = "v2.0" })
				:stepper({ value = function() return st2.v end })
				:small_title("navigation")
				:top_app_bar({ title = "Top", actions = { "search", "gear" } })
				:breadcrumb({ segments = { "home", "docs", "ui2" }, active = 3 })
				:tab_row({ tabs = { "a", "b", "c" },
					active = function() return st2.tab end })
				:navigation_bar({ items = { { icon = "home", label = "home" }, { icon = "apps", label = "set" } } })
				:navigation_rail({ items = { { icon = "home", label = "home" },
					{ icon = "gear", label = "set" } }, active = 1 })
				:color_palette({ colors = { 0x111111, 0x444444, 0xff0000 },
					value = function() return st2.color end })
				:search_bar({ value = function() return "" end })
				:range_slider({ value_low = 20, value_high = 80, min = 0, max = 200 })
				:color_picker({ hue = 200, bri = 0.8 })
				:dropdown({ items = { "a", "b", "c" }, value = "a" })
			:end_()
			local mm = mberr:measure()
			if mm.W <= 0 or mm.H <= 0 then
				failures[#failures + 1] = "ui2 miuix: measure 尺寸异常 " .. mm.W .. "x" .. mm.H
			end
			local mp = mberr.panel
			mp.w, mp.h = math.max(mm.W, 400), mm.H + 60
			mp:show()
			mp:draw()
		end)
		if not okm then
			failures[#failures + 1] = "ui2 miuix: 部件渲染失败: " .. tostring(errm)
		end
	end
end

if #failures == n1 then
	print("ui2 miuix widgets: checkbox/radio/badge/icon_button/fab/toolbar/list_item/stepper/breadcrumb/tab_row/navigation_bar/color_palette/search_bar/top_app_bar/navigation_rail/range_slider/color_picker/dropdown/preferences ok")
end

-- ── ui2 浮层：dropdown/dialog/bottom_sheet 开启渲染 + 吞点击路径 ──
local n15 = #failures
do
	local st3 = ui2.state({ dlg = true, sheet = true })
	local octx = new_ctx()
	local ob, oberr = pcall(ui2.panel, octx, { name = "ui2ov", title = "T" })
	if not ob or not oberr then
		failures[#failures + 1] = "ui2 overlay: panel 构建失败"
	else
		local oko, erro = pcall(function()
			oberr:column({ pad = 12, gap = 10 })
				:dropdown({ items = { "x", "y" }, value = "x" })
			:end_()
			oberr:dialog({ open = function() return st3.dlg end, title = "t", text = "msg",
				buttons = { { label = "ok", filled = true } } })
			oberr:bottom_sheet({ open = function() return st3.sheet end, title = "sheet",
				items = { "a", "b" } })
			-- 直接把 dropdown 节点置 open（模拟点击展开）
			for _, ch in ipairs(oberr.children) do
				if ch.children then
					for _, c2 in ipairs(ch.children) do
						if c2.kind == "dropdown" then
							c2._open = true
						end
					end
				end
			end
			local mm = oberr:measure()
			local mp = oberr.panel
			mp.w, mp.h = math.max(mm.W, 400), mm.H + 80
			mp:show()
			-- 模拟一次释放点击落在卡片外（吞点击路径 + 关闭逻辑不崩溃）
			mp.ui.mrelease = { x = 10, y = 10 }
			mp:draw()
			mp.ui.mrelease = nil
			mp:draw()
		end)
		if not oko then
			failures[#failures + 1] = "ui2 overlay: 浮层渲染失败: " .. tostring(erro)
		end
	end
end
if #failures == n15 then
	print("ui2 overlays: dropdown/dialog/bottom_sheet open + click-swallow ok")
end

-- ── ui_demo 全量：6 个 tab 全部 measure + render（含 extras 弹层） ──
local n3 = #failures
do
	local dctx = new_ctx()
	local okd, derr = pcall(function()
		local demo = require("plugins.ui_demo")
		demo.init(dctx)
		local p = dctx._panels.ui_demo
		if not p then
			failures[#failures + 1] = "ui_demo: panel 未注册"
			return
		end
		local st = demo.state
		for tab = 1, 6 do
			st.tab = tab
			p:draw()
		end
		-- extras 交互：打开 dialog / bottom sheet 各画一帧
		st.tab = 4
		st.dlg = true
		st.sheet = true
		p:draw()
		st.dlg, st.sheet = false, false
		-- panels tab：card 内 list_item 自然宽须包含右侧 hint 文本（防负坐标截断）
		st.tab = 6
		local m6 = p.b:measure()
		if m6.W < 200 then
			failures[#failures + 1] = "ui_demo: panels tab card 自然宽异常 W=" .. m6.W
				.. "（list_item right 文本空间未计入）"
		end
		p:draw()
		-- 模拟点击/悬停：6 tab × (press/release/after) + 内容区 hover 扫描
		local ui = p.ui
		local function click(x, y)
			ui.mx, ui.my = x, y
			ui.mdown = true
			local ok1, e1 = pcall(p.draw, p)
			ui.mdown = false
			ui.mrelease = { x = x, y = y }
			local ok2, e2 = pcall(p.draw, p)
			ui.mrelease = nil
			local ok3, e3 = pcall(p.draw, p)
			if not (ok1 and ok2 and ok3) then
				failures[#failures + 1] = string.format("ui_demo: click %d,%d 报错: %s",
					x, y, tostring(e1 or e2 or e3))
			end
		end
		for tab = 1, 6 do
			st.tab = tab
			p:draw()
			click(40 + tab * 60, 26)
		end
		for tab = 1, 6 do
			st.tab = tab
			p:draw()
			for y = 44, p.h - 8, 10 do
				for x = 8, p.w - 8, 20 do
					ui.mx, ui.my = x, y
					local ok, err = pcall(p.draw, p)
					if not ok then
						failures[#failures + 1] = string.format("ui_demo: hover tab%d %d,%d 报错: %s",
							tab, x, y, tostring(err))
						return
					end
				end
			end
		end
		-- render 中途切 tab（曾致 nil 布局错误）：release 命中 tab_row →
		-- on_change → visible 翻转 → 未 measure 子树被画 → 必须整帧重画
		local switched = 0
		for ti = 2, 6 do
			local tx = math.floor((ti - 0.5) / 6 * p.w)
			for y = 40, 110, 6 do
				st.tab = 1
				p:draw()
				ui.mx, ui.my = tx, y
				ui.mdown = false
				ui.mrelease = { x = tx, y = y }
				local ok, err = pcall(p.draw, p)
				ui.mrelease = nil
				if not ok then
					failures[#failures + 1] = string.format("ui_demo: render 中途切 tab%d (x=%d,y=%d) 报错: %s",
						ti, tx, y, tostring(err))
					return
				elseif st.tab == ti then
					switched = switched + 1
					break
				end
			end
		end
		if switched == 0 then
			failures[#failures + 1] = "ui_demo: 切 tab 测试未命中 tab_row（几何变化？）"
		end
		-- 自适应：user_size 拉大/拉小后重排，双击 header（reset_size）恢复自然尺寸
		for _, size in ipairs({ { 700, 620 }, { 260, 180 }, { 480, 501 } }) do
			local ok, err = pcall(function()
				p.user_size = { w = size[1], h = size[2] }
				p:live_resize(size[1], size[2])
				p:draw()
			end)
			if not ok then
				failures[#failures + 1] = "ui_demo: resize " .. size[1] .. "x" .. size[2]
					.. " 重排失败: " .. tostring(err)
			end
		end
		p.user_size = { w = 700, h = 620 }
		p:live_resize(700, 620)
		local ok_r, err_r = pcall(p.reset_size, p)
		if not ok_r then
			failures[#failures + 1] = "ui_demo: reset_size 失败: " .. tostring(err_r)
		elseif p.w > 700 then
			failures[#failures + 1] = "ui_demo: reset_size 后未回到自然尺寸 (w=" .. p.w .. ")"
		end
	end)
	if not okd then
		failures[#failures + 1] = "ui_demo: 渲染失败: " .. tostring(derr)
	end
end
if #failures == n3 then
	print("ui_demo: 6 tabs (basic/lists/select/extras/windows/panels) render ok")
end

-- ── ui2 icons 单测：Nerd Font PUA 解析 / ASCII 兜底 / 未知名不产生豆腐 ──
local n2 = #failures
do
	local Icons = require("core.icons")
	Icons.configure(cfg) -- config.lua 字体路径
	local g = Icons.glyph("gear")
	if #g ~= 3 or g:byte(1) ~= 0xEF then
		failures[#failures + 1] = "ui2 icons: nerd 模式未生效（gear 应为 3 字节 PUA UTF-8）"
	end
	if Icons.glyph("no_such_icon") ~= "?" then
		failures[#failures + 1] = "ui2 icons: 未知名应兜底 '?'"
	end
	if Icons.glyph("›") ~= "›" then
		failures[#failures + 1] = "ui2 icons: 原始字符应原样传递"
	end
	Icons.mode("ascii")
	if Icons.glyph("gear") ~= "*" then
		failures[#failures + 1] = "ui2 icons: ascii 兜底失败"
	end
	Icons.mode("nerd") -- 恢复，供后续测试
end
if #failures == n2 then
	print("ui2 icons: nerd pua / ascii fallback / unknown->? ok")
end
for _, f in ipairs(failures) do
	print("FAIL: " .. f)
end
os.exit(#failures == 0 and 0 or 1)
