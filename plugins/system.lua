local M = {}
local Popup = require("core.popup")
local W = require("core.widgets")

local P, last = nil, 0
local prev_cpu
local cpu_pct, mem_pct, swap_pct = 0, 0, 0
local mem_used_gb, mem_total_gb = 0, 1
local load1, load5, load15 = 0, 0, 0
local uptime_str = "0m"

local function update_stats()
	local f = io.open("/proc/stat", "r")
	if f then
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
		local cur = { total = total, idle = idle }
		if prev_cpu then
			local dt = cur.total - prev_cpu.total
			local di = cur.idle - prev_cpu.idle
			if dt > 0 then
				cpu_pct = math.floor((dt - di) / dt * 100 + 0.5)
			end
		end
		prev_cpu = cur
	end
	f = io.open("/proc/meminfo", "r")
	if f then
		local mt, ma, st, sf
		for line in f:lines() do
			local k, v = line:match("^(%w+):%s+(%d+)")
			if k == "MemTotal" then
				mt = tonumber(v)
			elseif k == "MemAvailable" then
				ma = tonumber(v)
			elseif k == "SwapTotal" then
				st = tonumber(v)
			elseif k == "SwapFree" then
				sf = tonumber(v)
			end
		end
		f:close()
		if mt and ma then
			mem_total_gb = mt / 1024 / 1024
			mem_used_gb = (mt - ma) / 1024 / 1024
			mem_pct = math.floor((mt - ma) / mt * 100 + 0.5)
		end
		if st and sf and st > 0 then
			swap_pct = math.floor((st - sf) / st * 100 + 0.5)
		end
	end
	f = io.open("/proc/loadavg", "r")
	if f then
		local line = f:read("*l")
		f:close()
		local a, b, c = line:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
		load1, load5, load15 = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
	end
	f = io.open("/proc/uptime", "r")
	if f then
		local line = f:read("*l")
		f:close()
		local sec = tonumber(line:match("([%d%.]+)")) or 0
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		if h >= 24 then
			uptime_str = string.format("%dd %dh", math.floor(h / 24), h % 24)
		else
			uptime_str = string.format("%dh %dm", h, m)
		end
	end
end

local function pick(ctx, p)
	if p >= 80 then
		return ctx.theme.crit
	end
	if p >= 50 then
		return ctx.theme.warn
	end
	return ctx.theme.accent
end

local function draw_popup(pop)
	local ctx = pop.ctx
	local T, s = ctx.theme, pop.surf
	local L = ctx.L
	local W_ = pop.w
	local lh = ctx.get_line_height()
	local PAD = 18
	local inner = W_ - PAD * 2
	local tx = function(str, x, y, color)
		L.xft_draw_rgba(ctx.ft_ctx, s, W_, pop.h, x, y, str, color)
	end

	tx("System", PAD, 16, T.fg)
	local up_str = "up " .. uptime_str
	local up_w = select(1, ctx.get_text_size(up_str))
	tx(up_str, W_ - PAD - up_w, 16, T.dim)

	local y = 16 + lh + 14

	tx("CPU", PAD, y, T.dim)
	local cpu_s = string.format("%d%%", cpu_pct)
	local cpu_w = select(1, ctx.get_text_size(cpu_s))
	tx(cpu_s, W_ - PAD - cpu_w, y, T.fg)
	y = y + lh + 4
	W.progress(ctx, {
		rrect = function(_, x, y, w, h, r, c)
			L.surf_rrect_aa(s, W_, pop.h, x, y, w, h, r, c)
		end,
	}, PAD, y, inner, 8, cpu_pct, pick(ctx, cpu_pct))
	y = y + 8 + 16

	tx("Memory", PAD, y, T.dim)
	local mem_s = string.format("%.1f / %.1f GB", mem_used_gb, mem_total_gb)
	local mem_w = select(1, ctx.get_text_size(mem_s))
	tx(mem_s, W_ - PAD - mem_w, y, T.fg)
	y = y + lh + 4
	L.surf_rrect_aa(s, W_, pop.h, PAD, y, inner, 8, 4, 0x2b2b2e)
	if mem_pct > 0 then
		local fw = math.max(8, math.floor(inner * mem_pct / 100))
		L.surf_rrect_aa(s, W_, pop.h, PAD, y, fw, 8, 4, pick(ctx, mem_pct))
	end
	y = y + 8 + 16

	tx("Swap", PAD, y, T.dim)
	local sw_s = string.format("%d%%", swap_pct)
	local sw_w = select(1, ctx.get_text_size(sw_s))
	tx(sw_s, W_ - PAD - sw_w, y, T.fg)
	y = y + lh + 4
	L.surf_rrect_aa(s, W_, pop.h, PAD, y, inner, 8, 4, 0x2b2b2e)
	if swap_pct > 0 then
		local fw = math.max(8, math.floor(inner * swap_pct / 100))
		L.surf_rrect_aa(s, W_, pop.h, PAD, y, fw, 8, 4, T.accent)
	end
	y = y + 8 + 18

	L.surf_fill(s, W_, pop.h, PAD, y, inner, 1, 0x3a3a3c)
	y = y + 12
	tx("Load avg", PAD, y, T.dim)
	local load_s = string.format("%.2f  %.2f  %.2f", load1, load5, load15)
	local load_w = select(1, ctx.get_text_size(load_s))
	tx(load_s, W_ - PAD - load_w, y, T.fg)
end

function M.init(ctx)
	update_stats()
	P = Popup.new(ctx, {
		w = 300,
		h = 260,
		radius = 14,
		bg = ctx.theme.surface,
		draw = draw_popup,
	})
	ctx.register_popup("system", P)
end

function M.width(ctx)
	return select(1, ctx.get_text_size("SYS")) + 20
end

function M.tick(ctx, dt)
	last = last + dt
	if last < 1500 then
		return
	end
	last = 0
	update_stats()
	if P.visible then
		P:draw()
	end
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	s:text(x + 8, math.floor((h - lh) / 2), "SYS", ctx.theme.fg)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn ~= 1 then
		return
	end
	update_stats()
	local direction = (ctx.config.position == "top") and "below" or "above"
	local anchor_y = (ctx.config.position == "top") and ctx.bar.h or (ctx.scr_h - ctx.bar.h)
	ctx.show_popup("system", gx + gw / 2, anchor_y, direction)
end

function M.shutdown() end

return M
