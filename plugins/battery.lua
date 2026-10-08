-- plugins/battery.lua — realtime battery bar item; click opens power panel
local M = {}
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("battery")

local present = false
local bats = {} -- e.g. { "BAT0", "BAT1" }
local cap = 0
local charging = false
local last = 0
local REFRESH_MS = 2000

local function rd(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

local function probe_bats()
	local found = {}
	for i = 0, 5 do
		local name = string.format("BAT%d", i)
		if rd("/sys/class/power_supply/" .. name .. "/capacity") then
			found[#found + 1] = name
		end
	end
	-- some systems expose other names; try a few common ones
	for _, name in ipairs({ "BATT", "BATTERY", "BAT" }) do
		if rd("/sys/class/power_supply/" .. name .. "/capacity") then
			found[#found + 1] = name
		end
	end
	bats = found
	present = #found > 0
	if present then
		log("batteries: %s", table.concat(found, ","))
	end
end

local function refresh()
	if #bats == 0 then
		probe_bats()
		if not present then
			return
		end
	end
	local sum, n = 0, 0
	charging = false
	for _, name in ipairs(bats) do
		local c = rd("/sys/class/power_supply/" .. name .. "/capacity")
		if c then
			sum = sum + (tonumber(c) or 0)
			n = n + 1
		end
		local st = rd("/sys/class/power_supply/" .. name .. "/status") or ""
		if st == "Charging" or st == "Full" then
			charging = true
		end
	end
	if n > 0 then
		cap = math.floor(sum / n + 0.5)
		present = true
	else
		present = false
	end
end

function M.init(_)
	refresh()
end

function M.width(ctx)
	if not present then
		return 0
	end
	return select(1, ctx.get_text_size(I.t("BAT") .. " 100%")) + 16
end

function M.tick(ctx, dt)
	if not present and #bats == 0 then
		-- no battery detected; probe again occasionally (hot-dock / desktop)
		last = last + dt
		if last < 30000 then
			return
		end
		last = 0
		refresh()
		return
	end
	last = last + dt
	if last < REFRESH_MS then
		return
	end
	last = 0
	refresh()
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

function M.draw(ctx, s, x, y, w, h)
	if not present then
		return
	end
	local lh = ctx.get_line_height()
	local col = charging and ctx.theme.accent
		or cap <= 10 and ctx.theme.crit
		or cap <= 30 and ctx.theme.warn
		or ctx.theme.fg
	local icon = charging and I.t("CHG") or cap <= 10 and "!!" or cap <= 30 and I.t("LOW") or I.t("BAT")
	s:text(x, math.floor((h - lh) / 2), string.format("%s %3d%%", icon, cap), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "power", gx, gw)
	end
end

return M
