local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

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
	return ctx.theme.primary
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 20
	m.W = 340
	m.HEAD_H = lh + 26
	m.ROW_H = lh + 20
	m.H = m.HEAD_H + m.ROW_H * 3 + 24 + (lh + 12) + 20 + lh + 18
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function draw_panel(p)
	local ctx = p.ctx
	local T = ctx.theme
	local m = p.m
	local W_ = m.W
	local lh, PAD = m.LH, m.PAD
	local inner = W_ - PAD * 2

	p:draw_header("System", Util.keybind_hint(ctx, "toggle_system"), PAD)

	local y = m.HEAD_H + 14

	p:text(PAD, y, "CPU", T.on_var)
	local cpu_s = string.format("%d%%", cpu_pct)
	local cpu_w = select(1, ctx.get_text_size(cpu_s))
	p:text(W_ - PAD - cpu_w, y, cpu_s, T.on_surface)
	y = y + lh + 6
	p.ui:progress(PAD, y, inner, 8, cpu_pct, pick(ctx, cpu_pct), T.surface_hi)
	y = y + m.ROW_H - lh

	p:text(PAD, y, "Memory", T.on_var)
	local mem_s = string.format("%.1f / %.1f GB", mem_used_gb, mem_total_gb)
	local mem_w = select(1, ctx.get_text_size(mem_s))
	p:text(W_ - PAD - mem_w, y, mem_s, T.on_surface)
	y = y + lh + 6
	p:rrect(PAD, y, inner, 8, 4, T.surface_hi)
	if mem_pct > 0 then
		local fw = math.max(8, math.floor(inner * mem_pct / 100))
		p:rrect(PAD, y, fw, 8, 4, pick(ctx, mem_pct))
	end
	y = y + m.ROW_H - lh

	p:text(PAD, y, "Swap", T.on_var)
	local sw_s = string.format("%d%%", swap_pct)
	local sw_w = select(1, ctx.get_text_size(sw_s))
	p:text(W_ - PAD - sw_w, y, sw_s, T.on_surface)
	y = y + lh + 6
	p:rrect(PAD, y, inner, 8, 4, T.surface_hi)
	if swap_pct > 0 then
		local fw = math.max(8, math.floor(inner * swap_pct / 100))
		p:rrect(PAD, y, fw, 8, 4, T.primary)
	end
	y = y + 24

	p:rect(PAD, y, inner, 1, T.outline)
	y = y + 12
	p:text(PAD, y, "Load avg", T.on_var)
	local load_s = string.format("%.2f  %.2f  %.2f", load1, load5, load15)
	local load_w = select(1, ctx.get_text_size(load_s))
	p:text(W_ - PAD - load_w, y, load_s, T.on_surface)
	y = y + lh + 6
	p:text(PAD, y, "uptime", T.on_var)
	local up_str = "up " .. uptime_str
	local up_w = select(1, ctx.get_text_size(up_str))
	p:text(W_ - PAD - up_w, y, up_str, T.on_surface)
end

function M.init(ctx)
	update_stats()
	P = Panel.new(ctx, {
		name = "system",
		radius = 16,
		bg = ctx.theme.bg,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = draw_panel,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
	})
	if P then
		P.m = build_model(ctx)
	end
	ctx.register_panel("system", P)
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
	ctx.show_panel("system", gx + gw / 2, anchor_y, direction)
end

function M.shutdown() end

return M
