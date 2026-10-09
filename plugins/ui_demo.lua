local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("ui_demo")

local XK_ESCAPE = 0xff1b
local XK_BACKSPACE = 0xff08

local TOGS = { "wifi", "bluetooth", "do not disturb" }
local ITEMS = { "item one - click me", "item two - hover me", "item three - selected" }
local SB_ITEMS = { "row alpha", "row beta", "row gamma", "row delta", "row epsilon", "row zeta" }

local WIDGET_LINES = {
	"buttons (filled / tonal / text) · chips · labels",
	"slider · progress · toggle · text field",
	"list · scrollbar · card · divider",
	"toast notifications · panel header · close",
}

local TABS = { "controls", "lists", "windows", "inventory" }

local MIN_PANEL_W = 220
local MIN_PANEL_H = 100

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 24
	m.W = 620
	m.HEAD_H = lh + 26
	m.SEC_H = lh + 6
	m.TAB_Y = m.HEAD_H + 14
	m.TAB_H = lh + 12
	local y = m.TAB_Y + m.TAB_H + 16
	m.Y0 = y

	m.BTN_H = lh + 20
	m.CHIP_H = lh + 12
	m.TOG_H = lh + 14
	m.TOG_STEP = m.TOG_H + 8
	m.LIST_ROW_H = lh + 12
	m.PAN_ROW_H = lh + 10

	local cy = y
	m.BTN_LBL_Y = cy
	cy = cy + m.SEC_H
	m.BTN_Y = cy
	cy = cy + m.BTN_H + 14
	m.CHIP_Y = cy
	cy = cy + m.CHIP_H + 14
	m.SL_LBL_Y = cy
	cy = cy + m.SEC_H
	m.SLIDER_Y = cy + 8
	cy = cy + 8 + 22 + 14
	m.PROG_Y = cy
	cy = cy + 22 + 14
	m.TOG_LBL_Y = cy
	cy = cy + m.SEC_H
	m.TOG_Y = cy
	cy = cy + m.TOG_STEP * 3 + 8
	m.TF_LBL_Y = cy
	cy = cy + m.SEC_H
	m.TF_Y = cy
	m.TF_H = lh + 24
	cy = cy + m.TF_H + 14
	m.CONTROLS_H = cy - y

	cy = y
	m.LIST_LBL_Y = cy
	cy = cy + m.SEC_H
	m.LIST_Y = cy
	cy = cy + m.LIST_ROW_H * 3 + 6
	m.SB_LBL_Y = cy + 14
	cy = m.SB_LBL_Y + m.SEC_H
	m.SB_Y = cy
	cy = cy + m.LIST_ROW_H * 3 + 6
	m.LISTS_H = cy - y

	cy = y
	m.WID_LBL_Y = cy
	cy = cy + m.SEC_H + #WIDGET_LINES * (lh + 6) + 10
	m.PAN_LBL_Y = cy
	cy = cy + m.SEC_H
	m.PAN_Y = cy
	local npans = 0
	for _, kb in ipairs(ctx.config.keybinds or {}) do
		if kb.group == "panels" and kb.action:find("^toggle_") then
			npans = npans + 1
		end
	end
	m.PAN_ROWS = math.ceil(npans / 2)
	cy = cy + m.PAN_ROWS * m.PAN_ROW_H
	m.INV_H = cy - y

	-- windows tab: move d-pad, resize d-pad, step rows, reset
	cy = y
	m.MV_LBL_Y = cy
	cy = cy + m.SEC_H
	m.MV_P1_Y = cy
	cy = cy + m.BTN_H + 8
	m.MV_P2_Y = cy
	cy = cy + m.BTN_H + 14
	m.RZ_LBL_Y = cy
	cy = cy + m.SEC_H
	m.RZ_P1_Y = cy
	cy = cy + m.BTN_H + 8
	m.RZ_P2_Y = cy
	cy = cy + m.BTN_H + 14
	m.MSTEP_Y = cy
	cy = cy + m.PAN_ROW_H
	m.RSTEP_Y = cy
	cy = cy + m.PAN_ROW_H
	m.WIN_RESET_Y = cy
	cy = cy + m.BTN_H
	m.WINDOWS_H = cy - y

	m.H = math.max(m.CONTROLS_H, m.LISTS_H, m.INV_H, m.WINDOWS_H) + y + 20
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function draw_controls(p)
	local m, ctx, ui, T = p.m, p.ctx, p.ui, p.ctx.theme
	local lh, PAD, W = m.LH, m.PAD, m.W
	local inner = W - PAD * 2

	ui:label(PAD, m.BTN_LBL_Y, I.t("buttons"), T.hint)
	local bw = math.floor((inner - 24) / 3)
	if ui:id_button("demo_fill", PAD, m.BTN_Y, bw, m.BTN_H, I.t("Filled"), { filled = true }) then
		ctx.notify(I.t("filled button clicked"), { style = "success" })
	end
	if ui:id_button("demo_tonal", PAD + bw + 12, m.BTN_Y, bw, m.BTN_H, I.t("Tonal"), { tonal = true }) then
		ctx.notify(I.t("tonal button clicked"), { style = "info" })
	end
	if ui:id_button("demo_text", PAD + (bw + 12) * 2, m.BTN_Y, bw, m.BTN_H, I.t("Text"), {}) then
		ctx.notify(I.t("text button clicked"))
	end

	local chips = { "chip alpha", "chip beta", "chip gamma" }
	local cx = PAD
	for i, c0 in ipairs(chips) do
		local c = I.t(c0)
		local cw = ctx.text_width(c) + 28
		if ui:id_button("demo_chip" .. i, cx, m.CHIP_Y, cw, m.CHIP_H, c, { tonal = true, radius = math.floor(m.CHIP_H / 2) }) then
			ctx.notify(I.t("chip: %s", c), { style = "info" })
		end
		cx = cx + cw + 10
	end

	ui:label(PAD, m.SL_LBL_Y, I.t("slider  %.0f%%", M.val * 100), T.hint)
	local nv, ch = ui:slider("demo_slider", PAD, m.SLIDER_Y, inner, M.val)
	if ch then
		M.val = nv
	end

	ui:progress(PAD, m.PROG_Y, inner, 8, M.val * 100)

	ui:label(PAD, m.TOG_LBL_Y, I.t("toggles"), T.hint)
	for i = 1, 3 do
		local ry = m.TOG_Y + (i - 1) * m.TOG_STEP
		ui:label(PAD, ry + math.floor((m.TOG_H - lh) / 2), I.t(TOGS[i]), T.on_var)
		local nv2, ch2 = ui:toggle("demo_tog" .. i, W - PAD - 72, ry, 72, m.TOG_H, M.togs[i])
		if ch2 then
			M.togs[i] = nv2
			ctx.notify(I.t(nv2 and "%s on" or "%s off", I.t(TOGS[i])), { style = "info" })
		end
	end

	ui:label(PAD, m.TF_LBL_Y, I.t("text field  (click, then type)"), T.hint)
	ui:text_field("demo_tf", PAD, m.TF_Y, inner, m.TF_H, M.text, { placeholder = I.t("type here…") })
end

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

local function draw_windows(p)
	local m, ctx, ui, T = p.m, p.ctx, p.ui, p.ctx.theme
	local lh, PAD, W = m.LH, m.PAD, m.W
	local inner = W - PAD * 2
	local btn_w = math.floor((inner - 2 * 8) / 3)
	local tonal = { tonal = true, bg = T.surface_hi }

	ui:label(PAD, m.MV_LBL_Y, I.t("move window"), T.hint)
	if ui:id_button("mv_up", PAD + btn_w + 8, m.MV_P1_Y, btn_w, m.BTN_H, "↑", tonal) then
		defer_win(ctx, function()
			win_move(ctx, 0, -M.mv_step)
		end)
	end
	if ui:id_button("mv_left", PAD, m.MV_P2_Y, btn_w, m.BTN_H, "←", tonal) then
		defer_win(ctx, function()
			win_move(ctx, -M.mv_step, 0)
		end)
	end
	if ui:id_button("mv_down", PAD + btn_w + 8, m.MV_P2_Y, btn_w, m.BTN_H, "↓", tonal) then
		defer_win(ctx, function()
			win_move(ctx, 0, M.mv_step)
		end)
	end
	if ui:id_button("mv_right", PAD + (btn_w + 8) * 2, m.MV_P2_Y, btn_w, m.BTN_H, "→", tonal) then
		defer_win(ctx, function()
			win_move(ctx, M.mv_step, 0)
		end)
	end

	ui:label(PAD, m.RZ_LBL_Y, I.t("resize window"), T.hint)
	if ui:id_button("rz_narrow", PAD, m.RZ_P1_Y, btn_w, m.BTN_H, "←", tonal) then
		defer_win(ctx, function()
			win_resize(ctx, -M.rz_step, 0)
		end)
	end
	if ui:id_button("rz_tall", PAD + btn_w + 8, m.RZ_P1_Y, btn_w, m.BTN_H, "↑", tonal) then
		defer_win(ctx, function()
			win_resize(ctx, 0, M.rz_step)
		end)
	end
	if ui:id_button("rz_wide", PAD + (btn_w + 8) * 2, m.RZ_P1_Y, btn_w, m.BTN_H, "→", tonal) then
		defer_win(ctx, function()
			win_resize(ctx, M.rz_step, 0)
		end)
	end
	if ui:id_button("rz_short", PAD + btn_w + 8, m.RZ_P2_Y, btn_w, m.BTN_H, "↓", tonal) then
		defer_win(ctx, function()
			win_resize(ctx, 0, -M.rz_step)
		end)
	end

	local rows = {
		{ y = m.MSTEP_Y, label = I.t("move step px"), value = string.format("%d px", M.mv_step) },
		{ y = m.RSTEP_Y, label = I.t("resize step px"), value = string.format("%d px", M.rz_step) },
	}
	for _, r in ipairs(rows) do
		p:rrect(PAD, r.y, inner, m.PAN_ROW_H, 14, T.surface)
		local ty = r.y + math.floor((m.PAN_ROW_H - lh) / 2)
		p:text(PAD + 16, ty, r.label, T.on_var)
		local vw = ctx.text_width(r.value)
		p:text(W - PAD - 16 - vw, ty, r.value, T.hint)
	end

	if ui:id_button("win_reset", PAD, m.WIN_RESET_Y, inner, m.BTN_H, I.t("reset panel"), { filled = true }) then
		defer_win(ctx, function()
			win_reset(ctx)
		end)
	end
end

local function draw_lists(p)
	local m, ctx, ui, T = p.m, p.ctx, p.ui, p.ctx.theme
	local lh, PAD, W = m.LH, m.PAD, m.W
	local inner = W - PAD * 2

	ui:label(PAD, m.LIST_LBL_Y, I.t("list"), T.hint)
	for i = 1, 3 do
		local ry = m.LIST_Y + (i - 1) * m.LIST_ROW_H
		local sel = M.sel == i
		local hover = ui:hover(PAD, ry, inner, m.LIST_ROW_H)
		local bg = sel and T.secondary_ctr or hover and T.surface_hover or T.surface_hi
		p:rrect(PAD, ry, inner, m.LIST_ROW_H, 10, bg)
		p:text(PAD + 16, ry + math.floor((m.LIST_ROW_H - lh) / 2),
			I.t(ITEMS[i]), sel and T.primary or T.on_surface)
		if ui:clicked(PAD, ry, inner, m.LIST_ROW_H) then
			M.sel = i
			ctx.notify(I.t("selected: %s", I.t(ITEMS[i])), { style = "info" })
		end
	end

	ui:label(PAD, m.SB_LBL_Y, I.t("scrollbar  (drag the thumb)"), T.hint)
	local vis = math.max(1, math.min(#SB_ITEMS,
		math.floor((m.H - m.SB_Y - 8) / m.LIST_ROW_H)))
	local max_off = math.max(0, #SB_ITEMS - vis)
	local list_w = inner - 22
	local new_off = ui:scrollbar("demo_sb", PAD + list_w + 8, m.SB_Y, 8, m.LIST_ROW_H * vis,
		M.sb_off, max_off)
	if new_off ~= M.sb_off then
		M.sb_off = new_off
	end
	for i = 1, vis do
		local li = M.sb_off + i
		if li > #SB_ITEMS then
			break
		end
		local ry = m.SB_Y + (i - 1) * m.LIST_ROW_H
		p:rrect(PAD, ry, list_w, m.LIST_ROW_H, 10, T.surface_hi)
		p:text(PAD + 16, ry + math.floor((m.LIST_ROW_H - lh) / 2), I.t(SB_ITEMS[li]), T.on_var)
	end
end

local function draw_inventory(p)
	local m, ctx, ui, T = p.m, p.ctx, p.ui, p.ctx.theme
	local lh, PAD, W = m.LH, m.PAD, m.W

	ui:label(PAD, m.WID_LBL_Y, I.t("widgets"), T.hint)
	for i, wln in ipairs(WIDGET_LINES) do
		p:text(PAD, m.WID_LBL_Y + m.SEC_H + (i - 1) * (lh + 6), I.t(wln), T.on_var)
	end

	ui:label(PAD, m.PAN_LBL_Y, I.t("panels  (keybind or click the bar item)"), T.hint)
	local col_w = math.floor((W - PAD * 2) / 2)
	local row, col = 0, 0
	for _, kb in ipairs(ctx.config.keybinds or {}) do
		if kb.group == "panels" and kb.action:find("^toggle_") then
			local pname = kb.action:sub(8)
			local x = PAD + col * col_w
			local y2 = m.PAN_Y + row * m.PAN_ROW_H
			p:text(x, y2, pname, T.on_var)
			local hint = Util.keybind_hint(ctx, kb.action)
			p:text(x + col_w - ctx.text_width(hint), y2, hint, T.hint)
			col = col + 1
			if col == 2 then
				col = 0
				row = row + 1
			end
		end
	end
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme

	-- self-heal on resize: model follows the live surface so inner widths
	-- and the scrollbar demo clamp to the real panel
	m.W, m.H = p.w, p.h
	local lh, PAD, W = m.LH, m.PAD, m.W

	local title = I.t("UI Components")
	local hy = p:draw_header(title, Util.keybind_hint(ctx, "toggle_ui_demo"), PAD)
	local tag = tostring(ctx.theme.name or "theme")
	local tag_w = ctx.text_width(tag)
	local tag_x = p.rect_close.x - 12 - tag_w
	if tag_x > PAD + ctx.text_width(title) + 12 then
		p:text(tag_x, hy, tag, T.hint)
	end

	local ui = p.ui
	local labels, active = {}, 1
	for i, t in ipairs(TABS) do
		labels[i] = I.t(t)
		if M.tab == t then
			active = i
		end
	end
	local sel = ui:segmented(PAD, m.TAB_Y, W - PAD * 2, m.TAB_H, labels, active)
	if sel > 0 then
		M.tab = TABS[sel]
	end

	if M.tab == "controls" then
		draw_controls(p)
	elseif M.tab == "lists" then
		draw_lists(p)
	elseif M.tab == "windows" then
		draw_windows(p)
	else
		draw_inventory(p)
	end
end

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
	M.val = 0.42
	M.togs = { true, false, true }
	M.text = ""
	M.sel = 0
	M.tab = "controls"
	M.sb_off = 0
	M.pending_action = nil

	-- merged window ops (former move_window / resize_window plugins)
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

	local panel = Panel.new(ctx, {
		name = "ui_demo",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
		end,
		on_key = function(p, sym, text, ctrl)
			if sym == XK_ESCAPE then
				p:hide()
				return true
			end
			if not p.ui:has_focus("demo_tf") then
				return false
			end
			if ctrl then
				return true
			end
			if sym == XK_BACKSPACE then
				local j = Util.utf8_prev(M.text, #M.text + 1)
				M.text = M.text:sub(1, j - 1)
				return true
			end
			if sym and sym >= 32 and text and #text > 0 then
				M.text = M.text .. text
				return true
			end
			return false
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("ui_demo", panel)

	log("ready")
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
