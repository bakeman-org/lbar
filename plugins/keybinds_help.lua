-- plugins/keybinds_help.lua — scrollable keybind reference panel
-- (MIUIX-style card rows: translated description left, combo pill right)
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("keybinds_help")

-- MIUIX-style geometry (mirrors plugins/settings.lua)
local PAD, SB_W, ROW_GAP, CARD_R, GROUP_GAP = 20, 6, 8, 14, 28
local WHEEL_STEP = 76

local st = {
	scroll = 0,
}

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function combo_of(kb)
	local parts = {}
	for p in kb.mod:gmatch("[^+]+") do
		parts[#parts + 1] = p:sub(1, 1):upper() .. p:sub(2):lower()
	end
	parts[#parts + 1] = kb.key:upper()
	return table.concat(parts, "+")
end

local function group_of(kb)
	if kb.group and kb.group ~= "" then
		return kb.group
	end
	return "other"
end

-- desc: translate at model build so width measurement uses the zh text
local function desc_of(kb)
	if kb.desc and kb.desc ~= "" then
		return I.t(kb.desc)
	end
	return kb.action
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end
	local groups = {}
	local order = {}
	local rows_by_group = {}
	local max_combo_w, max_desc_w = 0, 0

	for _, kb in ipairs(ctx.config.keybinds or {}) do
		if kb.mod and kb.key and kb.action then
			local g = group_of(kb)
			if not rows_by_group[g] then
				order[#order + 1] = g
				rows_by_group[g] = {}
			end
			local combo = combo_of(kb)
			local desc = desc_of(kb)
			rows_by_group[g][#rows_by_group[g] + 1] = { combo = combo, desc = desc }
			local cw, dw = tw(combo), tw(desc)
			if cw > max_combo_w then
				max_combo_w = cw
			end
			if dw > max_desc_w then
				max_desc_w = dw
			end
		end
	end

	local APPBAR = lh + 26
	local GROUP_H = lh + 8
	local ROW_H = math.max(46, lh + 28)
	local FOOTER_H = lh + 22
	local H_content = 0
	local total = 0
	for gi, gname in ipairs(order) do
		local rows = rows_by_group[gname]
		groups[#groups + 1] = { title = gname, rows = rows }
		total = total + #rows
		if gi > 1 then
			H_content = H_content + GROUP_GAP - ROW_GAP
		end
		H_content = H_content + GROUP_H + ROW_GAP + #rows * (ROW_H + ROW_GAP)
	end
	if #groups == 0 then
		groups[1] = { title = "other", rows = { { combo = I.t("(none)"), desc = I.t("no keybinds in config.lua") } } }
		total = 1
		H_content = GROUP_H + ROW_GAP + ROW_H + ROW_GAP
	end

	local COMBO_COL = max_combo_w + 28
	local desired = PAD + 22 + COMBO_COL + max_desc_w + 22 + PAD + 12
	local W = math.max(480, math.min(math.max(760, lh * 24), desired))
	-- natural height from the row count, capped at 85% of the screen
	local natural_h = APPBAR + 14 + H_content + 14 + FOOTER_H
	local H = math.max(lh * 12, math.min(ctx.scr_h * 0.85, natural_h))
	if user_size then
		W = math.max(W, user_size.w)
		H = math.max(lh * 10, user_size.h)
	end
	local max_scroll = math.max(0, APPBAR + 14 + H_content + 14 - (H - FOOTER_H) + 8)

	return {
		groups = groups,
		LH = lh,
		APPBAR = APPBAR,
		GROUP_H = GROUP_H,
		ROW_H = ROW_H,
		FOOTER_H = FOOTER_H,
		PAD = PAD,
		W = W,
		H = H,
		content_h = H_content,
		total = total,
		max_scroll = max_scroll,
	}
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH

	-- self-heal on resize: model follows the live surface so the scrollbar,
	-- row culling and scroll range always match the real panel
	m.W, m.H = p.w, p.h
	m.max_scroll = math.max(0, m.APPBAR + 14 + (m.content_h or 0) + 14 - (m.H - m.FOOTER_H) + 8)
	st.scroll = clamp(st.scroll, 0, m.max_scroll)
	local W, H = m.W, m.H
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end

	local view_top = m.APPBAR
	local view_bot = H - m.FOOTER_H
	local y = view_top + 14 - st.scroll
	local card_x = m.PAD
	local card_w = W - m.PAD * 2 - SB_W

	-- scrollable rows painted FIRST; the footer band and the header below
	-- cover the overflow opaquely, which clips without needing a scissor
	for gi, g in ipairs(m.groups) do
		if gi > 1 then
			y = y + GROUP_GAP - ROW_GAP
		end
		-- group title: small hint-coloured text
		if y + m.GROUP_H > view_top and y < view_bot then
			p:text(m.PAD + 6, y + 6, I.t(g.title), T.hint)
		end
		y = y + m.GROUP_H + ROW_GAP
		for _, row in ipairs(g.rows) do
			if y + m.ROW_H > view_top and y < view_bot then
				local hovered = ui:hover(card_x, y, card_w, m.ROW_H)
				p:rrect(card_x, y, card_w, m.ROW_H, CARD_R, hovered and T.surface_hover or T.surface)
				local ty = y + math.floor((m.ROW_H - lh) / 2)
				-- combo pill right-aligned; desc truncated to the room left over
				local pill_w = tw(row.combo) + 24
				local pill_h = lh + 12
				local pill_x = card_x + card_w - 16 - pill_w
				local desc = row.desc
				local avail = pill_x - 12 - (card_x + 16)
				if tw(desc) > avail then
					local cw = tw("n")
					desc = Util.utf8_truncate(desc, math.max(2, math.floor(avail / math.max(4, cw))))
				end
				p:text(card_x + 16, ty, desc, T.on_var)
				p:rrect(pill_x, y + math.floor((m.ROW_H - pill_h) / 2), pill_w, pill_h, pill_h / 2, T.surface_hi)
				p:text(pill_x + 12, ty, row.combo, T.hint)
			end
			y = y + m.ROW_H + ROW_GAP
		end
	end

	-- scrollbar (right edge, inside padding)
	if m.max_scroll > 0 then
		st.scroll = ui:scrollbar("kb_scroll", W - 14, view_top, SB_W, view_bot - view_top,
			st.scroll, m.max_scroll)
	end

	-- footer: opaque band + hairline separator + row count
	local fy = H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(m.PAD, fy, W - m.PAD * 2, 1, T.outline)
	p:text(m.PAD, fy + math.floor((m.FOOTER_H - lh) / 2),
		I.t("%d keybinds · %d groups", m.total, #m.groups), T.hint)

	-- header painted LAST: its opaque band clips the scrolled content
	p:draw_header(I.t("Keybinds"), Util.keybind_hint(ctx, "toggle_keybinds_help"), m.PAD)
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("Keys"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "keybinds_help" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("Keys"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "keybinds_help", gx, gw)
	end
end

function M.init(ctx)
	local panel = Panel.new(ctx, {
		name = "keybinds_help",
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_press = function(p, mx, my, btn)
			local m = p.m
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				if m.max_scroll > 0 then
					local dy = (btn == 4) and 1 or -1
					st.scroll = clamp(st.scroll - dy * WHEEL_STEP, 0, m.max_scroll)
					p:draw()
				end
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	ctx.register_panel("keybinds_help", panel)
	log("ready: %d keybinds", #(ctx.config.keybinds or {}))
end

function M.shutdown() end

return M
