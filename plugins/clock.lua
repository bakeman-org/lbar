local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local str, last_sec, P = "--:--", -1, nil
local today = os.date("*t")
local view_year, view_month = today.year, today.month

local function days_in_month(y, m)
	local t1 = os.time({ year = y, month = m, day = 1, hour = 12 })
	local ny, nm = (m == 12) and y + 1 or y, (m == 12) and 1 or m + 1
	local t2 = os.time({ year = ny, month = nm, day = 1, hour = 12 })
	return math.floor((t2 - t1) / 86400 + 0.5)
end
local function first_wday(y, m)
	return tonumber(os.date("%w", os.time({ year = y, month = m, day = 1, hour = 12 })))
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 20
	m.COL_W = lh + 26
	m.W = m.PAD * 2 + m.COL_W * 7
	m.HEAD_H = lh + 26
	m.ROW_H = lh + 10
	m.H = m.HEAD_H + (lh + 6) + (lh + 4) + 12 + 1 + 10 + (lh + 8) + (lh + 8)
		+ m.ROW_H * 6 + 16
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function draw_panel(p)
	local ctx = p.ctx
	local T = ctx.theme
	local m = p.m
	local W_, lh, PAD, COL_W = m.W, m.LH, m.PAD, m.COL_W

	local time_str = os.date("%H:%M:%S")
	local date_str = os.date("%a, %b %d")
	p:draw_header("Clock", Util.keybind_hint(ctx, "toggle_clock"), PAD)
	local ty = m.HEAD_H + 6
	local tw = select(1, ctx.get_text_size(time_str))
	p:text(math.floor((W_ - tw) / 2), ty, time_str, T.primary)
	local dw = select(1, ctx.get_text_size(date_str))
	p:text(math.floor((W_ - dw) / 2), ty + lh + 4, date_str, T.on_var)

	local y = ty + lh + 4 + lh + 12
	p:rect(PAD, y, W_ - PAD * 2, 1, T.outline)
	y = y + 10

	local month_str = string.format("%d-%02d", view_year, view_month)
	local mw = select(1, ctx.get_text_size(month_str))
	p:text(math.floor((W_ - mw) / 2), y, month_str, T.on_surface)
	y = y + lh + 8

	local cols = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
	local inner = W_ - PAD * 2
	local first_x = PAD
	for i, c in ipairs(cols) do
		local cx = first_x + (i - 1) * COL_W
		local cw = select(1, ctx.get_text_size(c))
		p:text(cx + math.floor((COL_W - cw) / 2), y, c, T.hint)
	end
	y = y + lh + 8

	local dim = days_in_month(view_year, view_month)
	local fwd = first_wday(view_year, view_month)
	local row_h = m.ROW_H

	for row = 0, 5 do
		for col = 0, 6 do
			local day = row * 7 + col - fwd + 1
			if day >= 1 and day <= dim then
				local cx = first_x + col * COL_W
				local cy = y + row * row_h
				local day_str = tostring(day)
				local dw_ = select(1, ctx.get_text_size(day_str))
				local tx = cx + math.floor((COL_W - dw_) / 2)
				local is_today = day == today.day and view_month == today.month
					and view_year == today.year
				if is_today then
					local pad = 5
					local sz = lh + pad * 2
					p:rrect(
						cx + math.floor((COL_W - sz) / 2),
						cy - pad + 2,
						sz, sz, math.floor(sz / 2), T.primary
					)
					p:text(tx, cy, day_str, T.on_primary)
				else
					p:text(tx, cy, day_str, (col == 0 or col == 6) and T.on_var or T.on_surface)
				end
			end
		end
	end
end

function M.init(ctx)
	P = Panel.new(ctx, {
		name = "clock",
		radius = 16,
		bg = ctx.theme.bg,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = draw_panel,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
	})
	if P then
		P.m = build_model(ctx)
	end
	ctx.register_panel("clock", P)
end

function M.width(ctx)
	return select(1, ctx.get_text_size(str)) + 20
end

function M.tick(ctx, dt)
	local now = os.time()
	if now ~= last_sec then
		last_sec = now
		str = os.date("%H:%M")
		ctx.bar.needs_redraw = true
		if P.visible then
			P:draw()
		end
	end
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	s:text(x + 8, math.floor((h - lh) / 2), str, ctx.theme.fg)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn ~= 1 then
		return
	end
	local t = os.date("*t")
	view_year, view_month = t.year, t.month
	local direction = (ctx.config.position == "top") and "below" or "above"
	local anchor_y = (ctx.config.position == "top") and ctx.bar.h or (ctx.scr_h - ctx.bar.h)
	ctx.show_panel("clock", gx + gw / 2, anchor_y, direction)
end

function M.shutdown() end

return M
