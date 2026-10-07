local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("ui_demo")

local XK_ESCAPE = 0xff1b
local XK_BACKSPACE = 0xff08

local TOGS = { "wifi", "bluetooth", "do not disturb" }
local ITEMS = { "item one - click me", "item two - hover me", "item three - selected" }

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 24
	m.W = 560
	m.HEAD_H = lh + 26
	m.SEC_H = lh + 6
	local y = m.HEAD_H + 16

	m.BTN_LBL_Y = y
	y = y + m.SEC_H
	m.BTN_Y = y
	m.BTN_H = lh + 20
	y = y + m.BTN_H + 14

	m.CHIP_Y = y
	m.CHIP_H = lh + 12
	y = y + m.CHIP_H + 14

	m.SL_LBL_Y = y
	y = y + m.SEC_H
	m.SLIDER_Y = y + 8
	y = y + 8 + 22 + 14

	m.PROG_Y = y
	y = y + 22 + 14

	m.TOG_LBL_Y = y
	y = y + m.SEC_H
	m.TOG_Y = y
	m.TOG_H = lh + 14
	m.TOG_STEP = m.TOG_H + 8
	y = y + m.TOG_STEP * 3 + 8

	m.TF_LBL_Y = y
	y = y + m.SEC_H
	m.TF_Y = y
	m.TF_H = lh + 16
	y = y + m.TF_H + 14

	m.LIST_LBL_Y = y
	y = y + m.SEC_H
	m.LIST_Y = y
	m.LIST_ROW_H = lh + 12
	m.LIST_ROWS = 3
	y = y + m.LIST_ROW_H * m.LIST_ROWS + 6

	m.H = y + 20
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	local ui = p.ui
	local lh, PAD, W = m.LH, m.PAD, m.W
	local inner = W - PAD * 2

	local hy = p:draw_header("UI Components", Util.keybind_hint(ctx, "toggle_ui_demo"), PAD)
	local tag = tostring(ctx.theme.name or "theme")
	local tag_w = select(1, ctx.get_text_size(tag))
	local tag_x = p.rect_close.x - 12 - tag_w
	if tag_x > PAD + select(1, ctx.get_text_size("UI Components")) + 12 then
		p:text(tag_x, hy, tag, T.hint)
	end

	ui:label(PAD, m.BTN_LBL_Y, "buttons", T.hint)
	local bw = math.floor((inner - 24) / 3)
	if ui:id_button("demo_fill", PAD, m.BTN_Y, bw, m.BTN_H, "Filled", { filled = true }) then
		ctx.notify("filled button clicked", { style = "success" })
	end
	if ui:id_button("demo_tonal", PAD + bw + 12, m.BTN_Y, bw, m.BTN_H, "Tonal", { tonal = true }) then
		ctx.notify("tonal button clicked", { style = "info" })
	end
	if ui:id_button("demo_text", PAD + (bw + 12) * 2, m.BTN_Y, bw, m.BTN_H, "Text", {}) then
		ctx.notify("text button clicked")
	end

	local chips = { "chip alpha", "chip beta", "chip gamma" }
	local cx = PAD
	for i, c in ipairs(chips) do
		local cw = select(1, ctx.get_text_size(c)) + 28
		if ui:id_button("demo_chip" .. i, cx, m.CHIP_Y, cw, m.CHIP_H, c, { tonal = true, radius = math.floor(m.CHIP_H / 2) }) then
			ctx.notify("chip: " .. c, { style = "info" })
		end
		cx = cx + cw + 10
	end

	ui:label(PAD, m.SL_LBL_Y, string.format("slider  %.0f%%", M.val * 100), T.hint)
	local nv, ch = ui:slider("demo_slider", PAD, m.SLIDER_Y, inner, M.val)
	if ch then
		M.val = nv
	end

	ui:progress(PAD, m.PROG_Y, inner, 8, M.val * 100)

	ui:label(PAD, m.TOG_LBL_Y, "toggles", T.hint)
	for i = 1, 3 do
		local ry = m.TOG_Y + (i - 1) * m.TOG_STEP
		ui:label(PAD, ry + math.floor((m.TOG_H - lh) / 2), TOGS[i], T.on_var)
		local nv2, ch2 = ui:toggle("demo_tog" .. i, W - PAD - 72, ry, 72, m.TOG_H, M.togs[i])
		if ch2 then
			M.togs[i] = nv2
			ctx.notify(TOGS[i] .. (nv2 and " on" or " off"), { style = "info" })
		end
	end

	ui:label(PAD, m.TF_LBL_Y, "text field  (click, then type)", T.hint)
	ui:text_field("demo_tf", PAD, m.TF_Y, inner, m.TF_H, M.text, { placeholder = "type here…" })

	ui:label(PAD, m.LIST_LBL_Y, "list", T.hint)
	for i = 1, m.LIST_ROWS do
		local ry = m.LIST_Y + (i - 1) * m.LIST_ROW_H
		local sel = M.sel == i
		local hover = ui:hover(PAD, ry, inner, m.LIST_ROW_H)
		local bg = sel and T.secondary_ctr or hover and T.surface_hover or T.surface_hi
		p:rrect(PAD, ry, inner, m.LIST_ROW_H, 10, bg)
		p:text(PAD + 16, ry + math.floor((m.LIST_ROW_H - lh) / 2),
			ITEMS[i], sel and T.primary or T.on_surface)
		if ui:clicked(PAD, ry, inner, m.LIST_ROW_H) then
			M.sel = i
			ctx.notify("selected: " .. ITEMS[i], { style = "info" })
		end
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size("ui")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "ui_demo" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "ui", active and ctx.theme.primary or ctx.theme.on_surface)
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
