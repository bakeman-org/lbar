local M = {}
local cap, status, present, last = 100, "Unknown", false, 0

local function rd(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

local function refresh()
	local c = rd("/sys/class/power_supply/BAT0/capacity")
	if not c then
		present = false
		return
	end
	present = true
	cap = tonumber(c) or 0
	status = rd("/sys/class/power_supply/BAT0/status") or "Unknown"
end

local function icon()
	if status == "Charging" or status == "Full" then
		return "CHG"
	end
	if cap <= 10 then
		return "!!"
	end
	if cap <= 30 then
		return "LOW"
	end
	return "BAT"
end

function M.init(_)
	refresh()
end

function M.width(ctx)
	if not present then
		return 0
	end
	return select(1, ctx.get_text_size("BAT 100%")) + 16
end

function M.tick(ctx, dt)
	if not present then
		return
	end
	last = last + dt
	if last < 5000 then
		return
	end
	last = 0
	refresh()
	ctx.bar.needs_redraw = true
end

function M.draw(ctx, s, x, y, w, h)
	if not present then
		return
	end
	local lh = ctx.get_line_height()
	local col = (status == "Charging" or status == "Full") and ctx.theme.accent
		or cap <= 10 and ctx.theme.crit
		or cap <= 30 and ctx.theme.warn
		or ctx.theme.fg
	s:text(x, math.floor((h - lh) / 2), string.format("%s %3d%%", icon(), cap), col)
end

return M
