-- plugins/mem.lua — compact memory bar item (text only, color by usage)
-- opts: interval_ms, color
local M = {}
local Util = require("core.util")
local I = require("core.i18n")

local used_kb, total_kb, last = 0, 1, 0
local opts = {}

local function load_opts(ctx)
	local c = ctx.config.mem or {}
	opts = {
		interval_ms = tonumber(c.interval_ms) or 2000,
		color = c.color ~= false,
	}
end

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

local function pct()
	return total_kb > 0 and (used_kb / total_kb * 100) or 0
end

local function load_color(ctx, v)
	if not opts.color then
		return ctx.theme.primary
	end
	local T = ctx.theme
	return v >= 80 and T.crit or v >= 50 and T.warn or T.good
end

function M.init(ctx)
	load_opts(ctx)
end

function M.width(ctx)
	return 8 + select(1, ctx.get_text_size(I.t("MEM") .. " 99.9G"))
end

function M.tick(ctx, dt)
	last = last + dt
	if last < opts.interval_ms then
		return
	end
	last = 0
	read_mem()
	ctx.bar.needs_redraw = true
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local str = I.t("MEM") .. string.format(" %4.1fG", used_kb / 1024 / 1024)
	s:text(x + 4, math.floor((h - lh) / 2), str, load_color(ctx, pct()))
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysmon", gx, gw)
	end
end

return M
