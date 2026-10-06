local M = {}
local prev, pct, last = nil, 0, 0

local function read_stat()
	local f = io.open("/proc/stat", "r")
	if not f then
		return nil
	end
	local line = f:read("*l")
	f:close()
	local n = {}
	for v in line:gmatch("%d+") do
		n[#n + 1] = tonumber(v)
	end
	local total, idle = 0, (n[4] or 0) + (n[5] or 0)
	for i = 1, 8 do
		total = total + (n[i] or 0)
	end
	return { total = total, idle = idle }
end

function M.width(ctx)
	return select(1, ctx.get_text_size(string.format("CPU %3d%%", pct))) + 16
end

function M.tick(ctx, dt)
	last = last + dt
	if last < 1000 then
		return
	end
	last = 0
	local cur = read_stat()
	if cur and prev then
		local dt_t = cur.total - prev.total
		local di = cur.idle - prev.idle
		if dt_t > 0 then
			pct = math.floor((dt_t - di) / dt_t * 100 + 0.5)
			ctx.bar.needs_redraw = true
		end
	end
	prev = cur
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local col = pct >= 80 and ctx.theme.crit or pct >= 50 and ctx.theme.warn or ctx.theme.fg
	s:text(x, math.floor((h - lh) / 2), string.format("CPU %3d%%", pct), col)
end

return M
