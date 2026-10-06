local M = {}

function M.divider(ctx, s, x, y, w, color)
	s:rect(x, y, w, 1, color or 0x3a3a3c)
end

function M.progress(ctx, s, x, y, w, h, pct, color, track)
	local r = math.floor(h / 2)
	s:rrect(x, y, w, h, r, track or 0x2b2b2e)
	if pct > 0 then
		local fw = math.max(h, math.floor(w * pct / 100))
		if fw > w then
			fw = w
		end
		s:rrect(x, y, fw, h, r, color)
	end
end

function M.kv(ctx, s, x, y, w, label, value, opts)
	opts = opts or {}
	local lh = ctx.get_line_height()
	s:text(x, y, label, opts.label_color or ctx.theme.dim)
	local vw = select(1, ctx.get_text_size(value))
	s:text(x + w - vw, y, value, opts.value_color or ctx.theme.fg)
	return lh + (opts.gap or 6)
end

function M.button(ctx, s, x, y, w, h, text, opts)
	opts = opts or {}
	local r = math.floor(h / 2)
	local bg
	if opts.filled then
		bg = opts.hover and ctx.theme.accent_hi or ctx.theme.accent
	elseif opts.tonal then
		bg = opts.hover and 0x3b3b3e or 0x2c2c2e
	else
		bg = opts.hover and 0x2c2c2e or 0x232326
	end
	s:rrect(x, y, w, h, r, bg)
	local lh = ctx.get_line_height()
	local tw = select(1, ctx.get_text_size(text))
	s:text(x + math.floor((w - tw) / 2), y + math.floor((h - lh) / 2), text, opts.fg or ctx.theme.fg)
end

function M.section(ctx, s, x, y, text)
	s:text(x, y, text, ctx.theme.dim)
	return ctx.get_line_height()
end

return M
