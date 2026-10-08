-- plugins/cpu.lua — cpu bar item, styled via config.cpu opts
-- opts: style = 'text'|'graph'|'both', interval_ms, history (spark samples), color
local M = {}
local Util = require("core.util")
local I = require("core.i18n")

local prev, pct, last = nil, 0, 0
local hist, hist_head, hist_n = {}, 0, 0
local opts = {}

local SPARK_BAR_W = 2
local SPARK_GAP = 1

local function load_opts(ctx)
	local c = ctx.config.cpu or {}
	opts = {
		style = c.style or "graph",
		interval_ms = tonumber(c.interval_ms) or 1000,
		history = math.max(8, tonumber(c.history) or 24),
		color = c.color ~= false,
	}
	hist = {}
	hist_head, hist_n = 0, 0
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

local function push_hist(v)
	hist_head = (hist_head % opts.history) + 1
	hist[hist_head] = v
	hist_n = math.min(hist_n + 1, opts.history)
end

local function spark_w()
	if opts.style == "text" then
		return 0
	end
	return hist_n * (SPARK_BAR_W + SPARK_GAP)
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
	local w = 16
	if opts.style ~= "graph" then
		w = w + select(1, ctx.get_text_size(I.t("CPU") .. string.format(" %3d%%", pct)))
	end
	if opts.style ~= "text" then
		w = w + (opts.history * (SPARK_BAR_W + SPARK_GAP)) + 8
	end
	return w
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
			push_hist(pct)
			ctx.bar.needs_redraw = true
		end
	end
	prev = cur
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local tx = x + 8
	if opts.style ~= "graph" then
		local str = I.t("CPU") .. string.format(" %3d%%", pct)
		s:text(tx, math.floor((h - lh) / 2), str, load_color(ctx, pct))
		tx = tx + select(1, ctx.get_text_size(str)) + 10
	end
	if opts.style ~= "text" and hist_n > 0 then
		local bh_max = h - 12
		local by = math.floor((h - bh_max) / 2)
		for i = 0, hist_n - 1 do
			local idx = ((hist_head - hist_n + i - 1) % opts.history)
			if idx < 0 then
				idx = idx + opts.history
			end
			idx = idx + 1
			local v = hist[idx] or 0
			local bh = math.max(2, math.floor(bh_max * v / 100))
			s:rrect(tx + i * (SPARK_BAR_W + SPARK_GAP), by + bh_max - bh, SPARK_BAR_W, bh, 1, load_color(ctx, v))
		end
	end
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
