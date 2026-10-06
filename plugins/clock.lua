local M = {}
local Popup = require("core.popup")

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

local function draw_popup(pop)
	local ctx = pop.ctx
	local s = pop.surf
	local T = ctx.theme
	local W_ = pop.w
	local lh = ctx.get_line_height()

	local time_str = os.date("%H:%M:%S")
	local date_str = os.date("%A, %B %d")
	local tw = select(1, ctx.get_text_size(time_str))
	ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, math.floor((W_ - tw) / 2), 26, time_str, T.fg)
	local dw = select(1, ctx.get_text_size(date_str))
	ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, math.floor((W_ - dw) / 2), 26 + lh + 6, date_str, T.dim)

	local y = 26 + (lh + 6) * 2 + 8
	ctx.L.surf_fill(s, W_, pop.h, 18, y, W_ - 36, 1, 0x3a3a3c)
	y = y + 12

	local month_str = string.format("%d 年 %d 月", view_year, view_month)
	local mw = select(1, ctx.get_text_size(month_str))
	ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, math.floor((W_ - mw) / 2), y, month_str, T.fg)
	y = y + lh + 12

	local cols = { "日", "一", "二", "三", "四", "五", "六" }
	local inner = W_ - 36
	local col_w = math.floor(inner / 7)
	local first_x = 18
	for i, c in ipairs(cols) do
		local cx = first_x + (i - 1) * col_w
		local cw = select(1, ctx.get_text_size(c))
		ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, cx + math.floor((col_w - cw) / 2), y, c, T.dim)
	end
	y = y + lh + 8

	local dim = days_in_month(view_year, view_month)
	local fwd = first_wday(view_year, view_month)
	local row_h = lh + 10

	for row = 0, 5 do
		for col = 0, 6 do
			local day = row * 7 + col - fwd + 1
			if day >= 1 and day <= dim then
				local cx = first_x + col * col_w
				local cy = y + row * row_h
				local day_str = tostring(day)
				local dw_ = select(1, ctx.get_text_size(day_str))
				local tx = cx + math.floor((col_w - dw_) / 2)
				local is_today = day == today.day and view_month == today.month and view_year == today.year
				if is_today then
					local pad = 5
					local sz = lh + pad * 2
					ctx.L.surf_rrect_aa(
						s,
						W_,
						pop.h,
						cx + math.floor((col_w - sz) / 2),
						cy - pad + 2,
						sz,
						sz,
						math.floor(sz / 2),
						T.accent
					)
					ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, tx, cy, day_str, 0xffffff)
				else
					ctx.L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, tx, cy, day_str, T.fg)
				end
			end
		end
	end
end

function M.init(ctx)
	P = Popup.new(ctx, {
		w = 320,
		h = 340,
		radius = 14,
		bg = ctx.theme.surface,
		draw = draw_popup,
	})
	ctx.register_popup("clock", P)
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
	ctx.show_popup("clock", gx + gw / 2, anchor_y, direction)
end

function M.shutdown() end

return M
