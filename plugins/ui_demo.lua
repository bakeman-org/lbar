-- plugins/ui_demo.lua — ui2 · MIUIX 组件画廊（声明式重写版）
--
-- 本插件即 ui2 框架的组件展示场与验收测试：
--   容器     :column :row :card :end_           （自动 pad/gap/测量）
--   文本     :h1 :p :small_title :hint :code
--   基础     :button(filled/tonal/text) :icon_button(+tooltip) :fab :toolbar
--             :badge :divider :progress :slider
--   选择     :checkbox :radio :toggle :stepper :segmented
--   输入     :text_field :search_bar
--   列表     :list_item(right=arrow/switch/checkbox/radio/text)
--             :basic_component :arrow/switch/checkbox/radio_preference
--   导航     :tab_row :navigation_bar :navigation_rail :breadcrumb
--             :top_app_bar
--   颜色     :color_palette :color_picker :range_slider
--   弹层     :dropdown :dialog :bottom_sheet（浮层吞点击，z 序自动）
--   提示     ui2.snackbar → lbar toast
--   结构     :each :component :if_ :unless + ui2.state 响应式
--
-- window ops（move/resize，i3/hyprland/panel）从旧版原样保留。
-- 测试：luajit plugin_container.lua ui_demo

local M = {}
local ui2 = require("core.ui2")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("ui_demo")

local XK_ESCAPE = 0xff1b

local MIN_PANEL_W = 220
local MIN_PANEL_H = 100

local COLORS = {
	0x1a1a1a, 0x444444, 0x888888, 0xcccccc, 0xffffff,
	0xdc322f, 0xb58900, 0x859900, 0x268bd2, 0x6c71c4,
	0xd33682, 0x2aa198,
}

-- ------------------------------------------------------------ window ops
-- move/resize for the focused external window (i3/hyprland) or the active
-- lbar panel; merged here from the former move_window/resize_window plugins

local function has_cmd(cmd)
	local f = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if not f then
		return false
	end
	local r = f:read("*l")
	f:close()
	return r ~= nil and r ~= ""
end

local function pick_panel(ctx, mark)
	local ap = ctx.active_panel
	if ap and ap.visible and ap[mark] then
		return ap
	end
	for _, p in pairs(ctx._panels or {}) do
		if p.visible and p[mark] then
			return p
		end
	end
	return nil
end

local function move_external(dx, dy)
	if M.wm == "i3" then
		local dir = dx < 0 and "left" or dx > 0 and "right" or dy < 0 and "up" or "down"
		return os.execute(string.format(
			"i3-msg 'move %s %d px' >/dev/null 2>&1 &", dir, math.abs(dx + dy))) == 0
	elseif M.wm == "hyprland" then
		local Hypr = require("core.wm.hyprland")
		local tf = Hypr.dispatch_cmd("hl.dispatch(hl.dsp.window.float())", "togglefloating")
		if M.mode == "auto_float" then
			return os.execute(string.format([[
(
  if hyprctl -j activewindow 2>/dev/null | grep -q '"floating": *false'; then
    %s
  fi
  %s
) &
]], tf, Hypr.dispatch_cmd(
				string.format("hl.dispatch(hl.dsp.window.move({ x = %d, y = %d }))", dx, dy),
				string.format("moveactive %d %d", dx, dy)))) == 0
		end
		return os.execute(string.format("(%s) &", Hypr.dispatch_cmd(
			string.format("hl.dispatch(hl.dsp.window.move({ x = %d, y = %d }))", dx, dy),
			string.format("moveactive %d %d", dx, dy)))) == 0
	end
	return false
end

local function resize_external(dx, dy)
	if M.wm == "i3" then
		local axis = dx ~= 0 and "width" or "height"
		local op = (dx > 0 or dy > 0) and "grow" or "shrink"
		local amt = math.abs(dx + dy)
		return os.execute(string.format(
			"i3-msg 'resize %s %s %d px' >/dev/null 2>&1 &", op, axis, amt)) == 0
	elseif M.wm == "hyprland" then
		local Hypr = require("core.wm.hyprland")
		return os.execute(string.format("(%s) &", Hypr.dispatch_cmd(
			string.format("hl.dispatch(hl.dsp.window.resize({ x = %d, y = %d }))", dx, dy),
			string.format("resizeactive %d %d", dx, dy)))) == 0
	end
	return false
end

local function win_move(ctx, dx, dy)
	local ok
	local p = pick_panel(ctx, "move_by")
	if p then
		p:move_by(dx, dy)
		ok = true
	else
		ok = move_external(dx, dy)
	end
	if ok then
		ctx.notify(I.t("window moved"), { style = "info", duration = 900 })
	else
		ctx.notify(I.t("no window to move"), { style = "error" })
	end
end

local function win_resize(ctx, dx, dy)
	local ok
	local p = pick_panel(ctx, "live_resize")
	if p then
		p._orig_geom = p._orig_geom or { w = p.w, h = p.h, x = p.sx, y = p.sy }
		local nw = math.max(MIN_PANEL_W, p.w + dx)
		local nh = math.max(MIN_PANEL_H, p.h + dy)
		p.user_size = { w = nw, h = nh }
		p:live_resize(nw, nh)
		ok = true
	else
		ok = resize_external(dx, dy)
	end
	if ok then
		ctx.notify(I.t("window resized"), { style = "info", duration = 900 })
	else
		ctx.notify(I.t("no window to resize"), { style = "error" })
	end
end

local function win_reset(ctx)
	local p = pick_panel(ctx, "live_resize")
	if not p then
		ctx.notify(I.t("no panel to reset"), { style = "error" })
		return
	end
	p.user_size = nil
	if p._orig_geom then
		local g = p._orig_geom
		p:live_resize(g.w, g.h)
		p:move_to(g.x, g.y)
	end
	ctx.notify(I.t("panel size reset"), { style = "success" })
end

local function defer_win(ctx, fn)
	M.pending_action = fn
end

-- ------------------------------------------------------------ 组件 tab

-- Tab 1 · basic：按钮族 / 图标 / 进度 / 徽标
local function TabBasic(b, opts)
	local st = opts.state
	b:small_title("buttons")
		:row({ gap = 8 })
			:button({ label = "Filled", filled = true,
				action = function() ui2.snackbar(opts.ctx, "filled button clicked", { style = "success" }) end })
			:button({ label = "Tonal", tonal = true,
				action = function() ui2.snackbar(opts.ctx, "tonal button clicked", { style = "info" }) end })
			:button({ label = "Text",
				action = function() ui2.snackbar(opts.ctx, "text button clicked") end })
		:end_()
		:small_title("icon · fab · toolbar · tooltip")
		:row({ gap = 10 })
			:icon_button({ icon = "gear", tooltip = "settings",
				action = function() ui2.snackbar(opts.ctx, "icon button") end })
			:icon_button({ icon = "close", tooltip = "close",
				action = function() ui2.snackbar(opts.ctx, "icon button") end })
			:fab({ icon = "plus",
				action = function() st.fab_n = st.fab_n + 1 end })
			:row({ pad = 0, gap = 0 })
				:badge({})
				:badge({ count = function() return st.fab_n end })
			:end_()
		:end_()
		:toolbar({ icons = { "star", "heart", "bell", "wifi" },
			on_select = function(i) ui2.snackbar(opts.ctx, "toolbar item " .. i) end })
		:small_title("slider · progress")
		:p({ value = function() return string.format("slider  %.0f%%", st.val * 100) end, color = "hint" })
		:slider({ value = function() return st.val end,
			on_change = function(v) st.val = v end })
		:progress({ pct = function() return st.val * 100 end })
		:progress({ pct = 72, color = "good", h = 10 })
	:end_()
end

-- Tab 2 · lists：list_item 全变体 / 搜索 / 面包屑
local function TabLists(b, opts)
	local st = opts.state
	b:small_title("list items")
		:list_item({ title = "wifi", summary = "connected · home 5G", icon = "wifi", right = "switch",
			value = function() return st.togs[1] end,
			on_change = function(v) st.togs[1] = v end })
		:list_item({ title = "bluetooth", summary = "2 devices", icon = "bluetooth", right = "switch",
			value = function() return st.togs[2] end,
			on_change = function(v) st.togs[2] = v end })
		:list_item({ title = "do not disturb", icon = "moon", right = "switch",
			value = function() return st.togs[3] end,
			on_change = function(v) st.togs[3] = v end })
		:divider({})
		:list_item({ title = "storage", right = "128G / 256G" })
		:list_item({ title = "about tablet", right = "arrow",
			on_click = function() ui2.snackbar(opts.ctx, "about clicked", { style = "info" }) end })
		:small_title("search")
		:search_bar({ value = function() return st.search end,
			placeholder = "search settings…",
			on_change = function(v) st.search = v end,
			on_submit = function(v) ui2.snackbar(opts.ctx, "search: " .. v) end })
		:small_title("breadcrumb")
		:breadcrumb({ segments = { "settings", "display", "brightness" },
			active = 3,
			on_change = function(i) ui2.snackbar(opts.ctx, "crumb " .. i) end })
	:end_()
end

-- Tab 3 · select：选择器 / 步进 / 分段 / 导航 / 颜色
local function TabSelect(b, opts)
	local st = opts.state
	b:small_title("checkbox · radio")
		:row({ gap = 12 })
			:checkbox({ value = function() return st.check end,
				on_change = function(v) st.check = v end })
			:p({ value = "notify" })
			:radio({ value = function() return st.radio_sel == 1 end,
				on_change = function() st.radio_sel = 1 end })
			:p({ value = "mode A" })
			:radio({ value = function() return st.radio_sel == 2 end,
				on_change = function() st.radio_sel = 2 end })
			:p({ value = "mode B" })
		:end_()
		:small_title("list-item selection")
		:list_item({ title = "sync forever", icon = "sync", right = "checkbox",
			value = function() return st.check end,
			on_change = function(v) st.check = v end })
		:list_item({ title = "battery saver", icon = "zap", right = "radio",
			value = function() return st.radio_sel == 1 end,
			on_change = function() st.radio_sel = 1 end })
		:small_title("stepper (number picker)")
		:row({ gap = 8 })
			:stepper({ value = function() return st.stepper_v end,
				on_change = function(v) st.stepper_v = v end })
			:stepper({ value = function() return st.stepper_v * 10 end, step = 10,
				on_change = function(v) st.stepper_v = math.floor(v / 10) end })
		:end_()
		:small_title("segmented")
		:segmented({ items = { "alpha", "beta", "gamma" },
			active = function() return st.seg end,
			on_change = function(i) st.seg = i end })
		:small_title("navigation bar")
		:navigation_bar({
			items = { { icon = "home", label = "home" }, { icon = "apps", label = "apps" },
				{ icon = "gear", label = "set" } },
			active = function() return st.nav end,
			on_change = function(i) st.nav = i end })
		:small_title("color palette")
		:color_palette({ colors = COLORS,
			value = function() return st.color end,
			on_change = function(c) st.color = c end })
		:row({ gap = 8 })
			:p({ value = "picked:", color = "hint" })
			:badge({ count = 1, color = function() return st.color end })
			:button({ label = "snackbar demo", tonal = true,
				action = function() ui2.snackbar(opts.ctx, "hello from ui2", { style = "info" }) end })
		:end_()
	:end_()
end

-- Tab 4 · windows：move/resize d-pad（window ops 保留）
local function TabWindows(b, opts)
	local ctx = opts.ctx
	local st = opts.state
	local mv, rz = M.mv_step, M.rz_step
	b:small_title("move window")
		:row({ gap = 8, align = "center" })
			:icon_button({ icon = "arrow_up", action = function() defer_win(ctx, function() win_move(ctx, 0, -mv) end) end })
			:icon_button({ icon = "arrow_down", action = function() defer_win(ctx, function() win_move(ctx, 0, mv) end) end })
			:icon_button({ icon = "arrow_left", action = function() defer_win(ctx, function() win_move(ctx, -mv, 0) end) end })
			:icon_button({ icon = "arrow_right", action = function() defer_win(ctx, function() win_move(ctx, mv, 0) end) end })
		:end_()
		:small_title("resize window")
		:row({ gap = 8, align = "center" })
			:icon_button({ icon = "expand", tooltip = "wider", action = function() defer_win(ctx, function() win_resize(ctx, rz, 0) end) end })
			:icon_button({ icon = "shrink", tooltip = "narrower", action = function() defer_win(ctx, function() win_resize(ctx, -rz, 0) end) end })
			:icon_button({ icon = "chevron_up", tooltip = "taller", action = function() defer_win(ctx, function() win_resize(ctx, 0, rz) end) end })
			:icon_button({ icon = "chevron_down", tooltip = "shorter", action = function() defer_win(ctx, function() win_resize(ctx, 0, -rz) end) end })
		:end_()
		:list_item({ title = "move step", right = tostring(mv) .. " px" })
		:list_item({ title = "resize step", right = tostring(rz) .. " px" })
		:button({ label = "reset panel", filled = true,
			action = function() defer_win(ctx, function() win_reset(ctx) end) end })
		:p({ value = "wm backend: " .. tostring(M.wm or "panel-only"), color = "hint" })
	:end_()
end

-- Tab 5 · extras：Miuix 补齐组件（top bar / rail / range / picker / 弹层）
local function TabExtras(b, opts)
	local ctx = opts.ctx
	local st = opts.state
	b:small_title("top app bar")
		:top_app_bar({ title = "Settings", actions = { "search", "gear" },
			on_action = function(i, name) ui2.snackbar(ctx, "action: " .. name, { style = "info" }) end })
		:small_title("navigation rail")
		:navigation_rail({
			items = { { icon = "home", label = "home" }, { icon = "wifi", label = "net" },
				{ icon = "music", label = "media" } },
			active = function() return st.rail end,
			on_change = function(i) st.rail = i end })
		:small_title("range slider")
		:p({ value = function() return string.format("range  %d – %d px",
				st.rlo, st.rhi) end, color = "hint" })
		:range_slider({ value_low = function() return st.rlo end,
			value_high = function() return st.rhi end,
			min = 0, max = 200,
			on_change = function(lo, hi) st.rlo, st.rhi = math.floor(lo), math.floor(hi) end })
		:small_title("color picker")
		:row({ gap = 10, align = "center" })
			:card({ pad = 6 })
				:color_picker({ hue = function() return st.hue end,
					bri = function() return st.bri end,
					on_change = function(h, br, c) st.hue, st.bri, st.cp = h, br, c end })
			:end_()
			:badge({ count = 1, color = function() return st.cp end })
		:end_()
		:small_title("dropdown")
		:dropdown({ items = { "light", "dark", "auto", "system" },
			value = function() return st.dd end,
			on_select = function(it) st.dd = it
				ui2.snackbar(ctx, "selected: " .. it, { style = "success" }) end })
		:small_title("dialog · bottom sheet")
		:row({ gap = 8 })
			:button({ label = "dialog", tonal = true,
				action = function() st.dlg = true end })
			:button({ label = "bottom sheet", tonal = true,
				action = function() st.sheet = true end })
		:end_()
	:dialog({ open = function() return st.dlg end, on_open = function(v) st.dlg = v end,
		title = "delete item?", text = "this action cannot be undone",
		buttons = { { label = "cancel", tonal = true }, { label = "delete", filled = true,
			action = function() ui2.snackbar(ctx, "deleted", { style = "error" }) end } } })
	:bottom_sheet({ open = function() return st.sheet end, on_open = function(v) st.sheet = v end,
		title = "share to", items = { "copy link", "bluetooth", "nearby", "mail" },
		on_select = function(it) ui2.snackbar(ctx, "share: " .. it, { style = "info" }) end })
	:end_()
end

-- Tab 6 · panels：键位清单（数据驱动 :each）
local function TabPanels(b, opts)
	local ctx = opts.ctx
	local kbs = {}
	for _, kb in ipairs(ctx.config.keybinds or {}) do
		if kb.group == "panels" and kb.action:find("^toggle_") then
			kbs[#kbs + 1] = { name = kb.action:sub(8), hint = Util.keybind_hint(ctx, kb.action) }
		end
	end
	b:small_title("panels · keybind or click bar item")
		:card({ pad = 10, gap = 2 })
			:each(function() return kbs end, function(kb, _, bb)
				bb:list_item({ title = kb.name, right = kb.hint })
			end)
			:if_(#kbs == 0, function(bb)
				bb:p({ value = "no panel keybinds in config.lua", color = "hint" })
			end)
		:end_()
		:p({ value = "ui2: declarative · reactive · miuix-style", color = "hint" })
	:end_()
end

-- ------------------------------------------------------------ init

local TAB_NAMES = { "basic", "lists", "select", "extras", "windows", "panels" }

function M.tick(ctx, dt)
	if M.pending_action then
		local fn = M.pending_action
		M.pending_action = nil
		local ok, err = pcall(fn)
		if not ok then
			log("pending action error: %s", tostring(err))
		end
	end
end

function M.width(ctx)
	return ctx.text_width(I.t("UI demo")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "ui_demo" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("UI demo"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "ui_demo", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending_action = nil

	local mvcfg = ctx.config.move_window or {}
	local rzcfg = ctx.config.resize_window or {}
	M.mv_step = math.max(1, tonumber(mvcfg.step) or 30)
	M.rz_step = math.max(4, tonumber(rzcfg.step) or 30)
	M.mode = mvcfg.mode or "auto_float"
	if has_cmd("i3-msg") then
		M.wm = "i3"
	elseif has_cmd("hyprctl") then
		M.wm = "hyprland"
	else
		M.wm = nil
		log("no i3-msg or hyprctl - external window ops unavailable")
	end

	ctx.actions["move_win_left"] = function()
		win_move(ctx, -M.mv_step, 0)
	end
	ctx.actions["move_win_right"] = function()
		win_move(ctx, M.mv_step, 0)
	end
	ctx.actions["move_win_up"] = function()
		win_move(ctx, 0, -M.mv_step)
	end
	ctx.actions["move_win_down"] = function()
		win_move(ctx, 0, M.mv_step)
	end
	ctx.actions["resize_win_wider"] = function()
		win_resize(ctx, M.rz_step, 0)
	end
	ctx.actions["resize_win_narrower"] = function()
		win_resize(ctx, -M.rz_step, 0)
	end
	ctx.actions["resize_win_taller"] = function()
		win_resize(ctx, 0, M.rz_step)
	end
	ctx.actions["resize_win_shorter"] = function()
		win_resize(ctx, 0, -M.rz_step)
	end
	ctx.actions["reset_active_window"] = function()
		defer_win(ctx, function()
			win_reset(ctx)
		end)
	end

	local st = ui2.state({
		tab = 1,
		val = 0.42,
		togs = { true, false, true },
		check = false,
		radio_sel = 2,
		stepper_v = 5,
		seg = 1,
		nav = 1,
		color = COLORS[9],
		fab_n = 0,
		search = "",
		rail = 1,
		rlo = 40,
		rhi = 140,
		hue = 210,
		bri = 0.85,
		cp = 0x2196f3,
		dd = "auto",
		dlg = false,
		sheet = false,
	})

	local b = ui2.panel(ctx, {
		name = "ui_demo",
		title = I.t("UI Components"),
		hint = Util.keybind_hint(ctx, "toggle_ui_demo"),
		width = 480,
	})

	local tab_opts = { state = st, ctx = ctx }

	-- 每个 tab 一个 visible column：st.tab 变化 → 布局实时切换
	local tabs = { TabBasic, TabLists, TabSelect, TabExtras, TabWindows, TabPanels }
	b:column({ pad = 20, gap = 12 })
		:tab_row({
			tabs = TAB_NAMES,
			active = function() return st.tab end,
			on_change = function(i) st.tab = i end,
		})
		:divider({})
	for i, TabFn in ipairs(tabs) do
		b:column({ pad = 0, gap = 12, visible = function() return st.tab == i end })
			:component(TabFn, tab_opts)
		:end_()
	end
	b:on_key(XK_ESCAPE, function(p) p:hide() end)

	ui2.reactive(st, b, ctx)

	M.panel = b.panel
	M.panel.b = b
	M.state = st
	ctx.register_panel("ui_demo", b.panel)

	log("ready (ui2 · miuix gallery)")
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
