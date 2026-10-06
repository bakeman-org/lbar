local M = {}
local used_kb, total_kb, last = 0, 1, 0

local function read_mem()
	local f = io.open("/proc/meminfo", "r")
	if not f then
		return
	end
	local mt, ma
	for line in f:lines() do
		local k, v = line:match("^(%w+):%s+(%d+)")
		if k == "MemTotal" then
			mt = tonumber(v)
		elseif k == "MemAvailable" then
			ma = tonumber(v)
		end
	end
	f:close()
	if mt and ma then
		total_kb = mt
		used_kb = mt - ma
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size("MEM 99.9G")) + 16
end

function M.tick(ctx, dt)
	last = last + dt
	if last < 2000 then
		return
	end
	last = 0
	read_mem()
	ctx.bar.needs_redraw = true
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local pct = total_kb > 0 and (used_kb / total_kb * 100) or 0
	local col = pct >= 80 and ctx.theme.crit or pct >= 50 and ctx.theme.warn or ctx.theme.fg
	local str = string.format("MEM %4.1fG", used_kb / 1024 / 1024)
	s:text(x, math.floor((h - lh) / 2), str, col)
end

return M
