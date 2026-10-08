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

local TABS = { "controls", "lists", "inventory" }

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
	m.TF_H = lh + 16
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

	m.H = math.max(m.CONTROLS_H, m.LISTS_H, m.INV_H) + y + 20
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
		local cw = select(1, ctx.get_text_size(c)) + 28
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
			p:text(x + col_w - select(1, ctx.get_text_size(hint)), y2, hint, T.hint)
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
	local tag_w = select(1, ctx.get_text_size(tag))
	local tag_x = p.rect_close.x - 12 - tag_w
	if tag_x > PAD + select(1, ctx.get_text_size(title)) + 12 then
		p:text(tag_x, hy, tag, T.hint)
	end

	local ui = p.ui
	local tx = PAD
	for _, t in ipairs(TABS) do
		local label = I.t(t)
		local tw = select(1, ctx.get_text_size(label)) + 28
		local active = M.tab == t
		if ui:id_button("demo_tab_" .. t, tx, m.TAB_Y, tw, m.TAB_H, label,
				{ filled = active, tonal = not active }) then
			M.tab = t
		end
		tx = tx + tw + 10
	end

	if M.tab == "controls" then
		draw_controls(p)
	elseif M.tab == "lists" then
		draw_lists(p)
	else
		draw_inventory(p)
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("UI"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "ui_demo" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("UI"), active and ctx.theme.primary or ctx.theme.on_surface)
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
