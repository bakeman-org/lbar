-- plugins/cpu.lua — compact cpu bar item (text only, color by load)
-- opts: interval_ms, color
local M = {}
local Util = require("core.util")
local I = require("core.i18n")

local prev, pct, last = nil, 0, 0
local opts = {}

local function load_opts(ctx)
	local c = ctx.config.cpu or {}
	opts = {
		interval_ms = tonumber(c.interval_ms) or 1000,
		color = c.color ~= false,
	}
end

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
	return 8 + select(1, ctx.get_text_size(I.t("CPU") .. string.format(" %3d%%", pct)))
end

function M.tick(ctx, dt)
	last = last + dt
	if last < opts.interval_ms then
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
	local str = I.t("CPU") .. string.format(" %3d%%", pct)
	s:text(x + 4, math.floor((h - lh) / 2), str, load_color(ctx, pct))
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysmon", gx, gw)
	end
end

function M.shutdown()
	prev = nil
end

return M
