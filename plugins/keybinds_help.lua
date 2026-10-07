local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("keybinds_help")

local ROW_PAD_Y = 9
local ROW_GAP = 6
local MAX_PANEL_H = 640
local WHEEL_STEP = 52
local SBAR_W = 4
local SBAR_PAD = 10

local st = {
	scroll = 0,
	max_scroll = 0,
	drag_active = false,
	drag_grab = 0,
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

local function desc_of(kb)
	if kb.desc and kb.desc ~= "" then
		return kb.desc
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
	local SEC_H = lh + 14
	local GAP = 12
	local PAD = 24
	local ROW_BOX_H = lh + ROW_PAD_Y * 2
	local H_content = 0
	for _, gname in ipairs(order) do
		local rows = rows_by_group[gname]
		groups[#groups + 1] = { title = gname, rows = rows }
		H_content = H_content + SEC_H + #rows * (ROW_BOX_H + ROW_GAP) + GAP
	end
	if #groups == 0 then
		groups[1] = { title = "other", rows = { { combo = "(none)", desc = "no keybinds in config.lua" } } }
		H_content = SEC_H + ROW_BOX_H + ROW_GAP + GAP
	end

	local COMBO_COL = max_combo_w + 28
	local desired = PAD + 22 + COMBO_COL + max_desc_w + 22 + PAD + 12
	local W = math.max(480, math.min(math.max(760, lh * 24), desired))
	local natural_h = APPBAR + 14 + H_content + 14
	local H = math.min(math.max(MAX_PANEL_H, lh * 16), natural_h)
	if user_size then
		W = math.max(W, user_size.w)
		H = math.max(lh * 10, user_size.h)
	end
	local max_scroll = math.max(0, APPBAR + H_content - H + 28)

	return {
		groups = groups,
		LH = lh,
		APPBAR = APPBAR,
		SEC_H = SEC_H,
		GAP = GAP,
		PAD = PAD,
		ROW_BOX_H = ROW_BOX_H,
		COMBO_COL = COMBO_COL,
		W = W,
		H = H,
		max_scroll = max_scroll,
	}
end

local function scrollbar_geo(p, m)
	if m.max_scroll <= 0 then
		return nil
	end
	local track_x = m.W - SBAR_PAD
	local track_y = m.APPBAR + 8
	local track_h = m.H - m.APPBAR - 16
	if track_h <= 0 then
		return nil
	end
	local view_h = m.H - m.APPBAR
	local bar_h = math.max(28, track_h * (view_h - m.max_scroll) / view_h)
	if bar_h > track_h then
		bar_h = track_h
	end
	local bar_y = track_y + (track_h - bar_h) * (st.scroll / m.max_scroll)
	return {
		track_x = track_x,
		track_y = track_y,
		track_w = SBAR_W,
		track_h = track_h,
		bar_y = bar_y,
		bar_h = bar_h,
	}
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH
	local W, H = m.W, m.H
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end
	st.max_scroll = m.max_scroll

	local view_top = m.APPBAR
	local view_bot = H
	local content_top = m.APPBAR + 14
	local has_scrollbar = m.max_scroll > 0
	local right_inset = has_scrollbar and (SBAR_PAD + SBAR_W + 6) or 0

	local box_x = m.PAD - 6
	local box_w = W - (m.PAD - 6) * 2 - right_inset
	local text_x = box_x + 22
	local desc_x = text_x + m.COMBO_COL

	local y = content_top - st.scroll

	for _, g in ipairs(m.groups) do
		local section_h = m.SEC_H + #g.rows * (m.ROW_BOX_H + ROW_GAP) + m.GAP
		if y + section_h > view_top and y < view_bot then
			local title_w = tw(g.title)
			p:text(m.PAD, y, g.title, T.primary)
			p:rect(m.PAD + title_w + 12, y + math.floor(lh / 2), W - m.PAD * 2 - title_w - 12, 1, T.outline)
			y = y + m.SEC_H
			for _, row in ipairs(g.rows) do
				if y + m.ROW_BOX_H > view_top and y < view_bot then
					local hover = ui:hover(box_x, y, box_w, m.ROW_BOX_H)
					p:rrect(box_x, y, box_w, m.ROW_BOX_H, 12, hover and T.surface_hi or T.surface)
					p:rrect(box_x + 10, y + 10, 3, m.ROW_BOX_H - 20, 2, T.primary)
					local ty = y + math.floor((m.ROW_BOX_H - lh) / 2)
					p:text(text_x, ty, row.combo, T.primary_hi)
					p:text(desc_x, ty, row.desc, T.on_surface)
				end
				y = y + m.ROW_BOX_H + ROW_GAP
			end
			y = y + m.GAP
		else
			y = y + section_h
		end
	end

	local geo = scrollbar_geo(p, m)
	if geo then
		p:rrect(geo.track_x, geo.track_y, geo.track_w, geo.track_h, geo.track_w / 2, T.surface)
		local bar_hover = ui:hover(geo.track_x - 4, geo.bar_y, geo.track_w + 8, geo.bar_h)
		local bar_color = (bar_hover or st.drag_active) and T.primary_hi or T.primary
		p:rrect(geo.track_x, geo.bar_y, geo.track_w, geo.bar_h, geo.track_w / 2, bar_color)
	end

	p:draw_header("Keybinds", Util.keybind_hint(ctx, "toggle_keybinds_help"), m.PAD)
end

function M.width(ctx)
	return select(1, ctx.get_text_size("keys")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "keybinds_help" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "keys", active and ctx.theme.primary or ctx.theme.on_surface)
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
				return
			end
			local geo = scrollbar_geo(p, m)
			if geo then
				local on_track = mx >= geo.track_x - 4
					and mx <= geo.track_x + geo.track_w + 4
					and my >= geo.track_y
					and my <= geo.track_y + geo.track_h
				if on_track then
					if my >= geo.bar_y and my <= geo.bar_y + geo.bar_h then
						st.drag_active = true
						st.drag_grab = my - geo.bar_y
					else
						local span = geo.track_h - geo.bar_h
						if span > 0 then
							local frac = (my - geo.track_y - geo.bar_h / 2) / span
							st.scroll = clamp(frac * m.max_scroll, 0, m.max_scroll)
						end
					end
					p:draw()
				end
			end
		end,
		on_motion = function(p, mx, my)
			if st.drag_active then
				local geo = scrollbar_geo(p, p.m)
				if geo then
					local span = geo.track_h - geo.bar_h
					if span > 0 then
						local frac = (my - st.drag_grab - geo.track_y) / span
						st.scroll = clamp(frac * p.m.max_scroll, 0, p.m.max_scroll)
						p:draw()
					end
				end
			end
		end,
		on_release = function(p)
			st.drag_active = false
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
