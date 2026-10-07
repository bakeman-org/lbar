local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("sysmon")

local REFRESH_MS = 1000
local HISTORY_LEN = 60
local MAX_CORES = 8
local CLK_TCK = 100
local PAGE_SIZE = 4096
local PROC_FETCH_N = 200

local XK_k = 0x6b

local function read_cpu_stat()
	local f = io.open("/proc/stat", "r")
	if not f then
		return nil
	end
	local res = { cores = {} }
	for line in f:lines() do
		if line:sub(1, 3) == "cpu" then
			local name = line:match("^(cpu%d*)")
			local n = {}
			for num in line:gmatch("%d+") do
				n[#n + 1] = tonumber(num)
			end
			local total = 0
			for i = 1, 8 do
				total = total + (n[i] or 0)
			end
			local idle = (n[4] or 0) + (n[5] or 0)
			local rec = { total = total, busy = total - idle }
			if name == "cpu" then
				res.agg = rec
			else
				res.cores[#res.cores + 1] = rec
			end
		else
			break
		end
	end
	f:close()
	return res
end

local function read_mem()
	local f = io.open("/proc/meminfo", "r")
	if not f then
		return nil
	end
	local m = {}
	for line in f:lines() do
		local k, v = line:match("^(%w+):%s+(%d+)")
		if k then
			m[k] = tonumber(v)
		end
	end
	f:close()
	return m
end

local function list_pids()
	local pids = {}
	local p = io.popen("ls -1 /proc 2>/dev/null")
	if not p then
		return pids
	end
	for line in p:lines() do
		local pid = tonumber(line)
		if pid then
			pids[#pids + 1] = pid
		end
	end
	p:close()
	return pids
end

local function read_proc(pid)
	local f = io.open("/proc/" .. pid .. "/stat", "r")
	if not f then
		return nil
	end
	local line = f:read("*l")
	f:close()
	if not line then
		return nil
	end
	local name = line:match("%(([^%)]+)%)") or "?"
	local rest = line:match("%)%s+(.*)$")
	if not rest then
		return nil
	end
	local fields = {}
	for tok in rest:gmatch("%S+") do
		fields[#fields + 1] = tok
	end
	return {
		pid = pid,
		name = name,
		utime = tonumber(fields[12]) or 0,
		stime = tonumber(fields[13]) or 0,
		rss = tonumber(fields[22]) or 0,
	}
end

local function delta_pct(prev, cur)
	if not prev then
		return 0
	end
	local dt = cur.total - prev.total
	local db = cur.busy - prev.busy
	if dt <= 0 then
		return 0
	end
	return db / dt * 100
end

function M:sample()
	local cur = read_cpu_stat()
	if not cur or not cur.agg then
		return
	end
	local prev = M.prev_cpu
	local ncpu = #cur.cores
	if ncpu < 1 then
		ncpu = 1
	end

	if prev then
		local agg = delta_pct(prev.agg, cur.agg)
		M.cur_cpu_agg = agg
		M.history_head = (M.history_head % HISTORY_LEN) + 1
		M.history[M.history_head] = agg

		M.cur_cores = {}
		for i, c in ipairs(cur.cores) do
			M.cur_cores[i] = delta_pct(prev.cores[i], c)
		end

		local dt_sec = (cur.agg.total - prev.agg.total) / ncpu / CLK_TCK
		if dt_sec > 0.01 then
			local list, snap = {}, {}
			local count = 0
			for _, pid in ipairs(list_pids()) do
				if count >= PROC_FETCH_N then
					break
				end
				count = count + 1
				local p = read_proc(pid)
				if p then
					local pp = M.prev_procs[pid]
					local cpu_pct = 0
					if pp then
						local d = (p.utime + p.stime) - (pp.utime + pp.stime)
						if d > 0 then
							cpu_pct = d / CLK_TCK / dt_sec * 100
						end
					end
					list[#list + 1] = {
						pid = p.pid,
						name = p.name,
						cpu = cpu_pct,
						mem = p.rss * PAGE_SIZE,
					}
					snap[pid] = { utime = p.utime, stime = p.stime }
				end
			end
			M.prev_procs = snap
			table.sort(list, function(a, b)
				return a.cpu > b.cpu
			end)
			M.procs = list
			M:apply_filter()
		end
	end
	M.prev_cpu = cur
	M.cur_mem = read_mem()
end

function M:apply_filter()
	local q = M.search_query
	if not q or q == "" then
		M.filtered = M.procs
	else
		local ql = q:lower()
		local out = {}
		for _, p in ipairs(M.procs) do
			if p.name:lower():find(ql, 1, true) or tostring(p.pid):find(ql, 1, true) then
				out[#out + 1] = p
			end
		end
		M.filtered = out
	end
	M:clamp_scroll()
end

function M:clamp_scroll()
	local max_scroll = math.max(0, #M.filtered - M.VISIBLE_ROWS)
	if M.scroll > max_scroll then
		M.scroll = max_scroll
	end
	if M.scroll < 0 then
		M.scroll = 0
	end
end

local function compute_layout(lh, ncores_display, scr_h, user_size)
	local L = {}
	L.W = 840
	L.PAD = 20
	L.HEADER_H = lh + 26
	L.BAR_H = 8
	L.SPARK_H = 40
	L.ROW_H = lh + 8
	L.CORE_H = lh + 4
	L.LABEL_W = 60
	L.PCT_W = 76
	L.FOOTER_H = lh + 16
	L.CPU_H = L.ROW_H + L.SPARK_H + 12
	L.CORES_H = ncores_display * L.CORE_H + 12
	L.MEM_H = L.ROW_H * 2 + 12
	L.PHDR_H = L.ROW_H

	local want_h = math.min(math.floor(scr_h * 0.82), 880)
	if want_h < 500 then
		want_h = 500
	end
	if user_size then
		L.W = math.max(640, user_size.w)
		want_h = math.max(420, user_size.h)
	end
	local fixed = L.HEADER_H + L.CPU_H + L.CORES_H + L.MEM_H + L.PHDR_H + L.FOOTER_H + 30
	local list_h = want_h - fixed
	if list_h < L.ROW_H * 4 then
		list_h = L.ROW_H * 4
		want_h = fixed + list_h
	end
	L.H = want_h
	L.VISIBLE_ROWS = math.max(4, math.floor(list_h / L.ROW_H))
	return L
end

local function load_color(T, pct)
	if pct >= 80 then
		return T.crit
	end
	if pct >= 50 then
		return T.warn
	end
	return T.good
end

local function fmt_bytes_kb(kb)
	if not kb then
		return "--"
	end
	local gib = kb / 1024 / 1024
	if gib >= 1024 then
		return string.format("%.1f TiB", gib / 1024)
	end
	return string.format("%.1f GiB", gib)
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh, PAD = p.ctx.get_line_height(), m.PAD
	local W, H = m.W, m.H
	local inner_w = W - PAD * 2
	local LABEL_W, PCT_W = m.LABEL_W, m.PCT_W
	local bar_x = PAD + LABEL_W
	local bar_w = inner_w - LABEL_W - PCT_W - 8

	local function draw_bar(x, y, w, h, pct, color)
		p:rect(x, y, w, h, T.surface)
		local fill = math.floor(w * math.max(0, math.min(100, pct)) / 100)
		if fill > 0 then
			p:rect(x, y, fill, h, color)
		end
	end

	local hh = p:draw_header("System Monitor", Util.keybind_hint(ctx, "toggle_sysmon"), PAD)
	local hint = Util.keybind_hint(ctx, "toggle_sysmon")
	local hw = select(1, ctx.get_text_size(hint))
	local hint_x = p.rect_close.x - 12 - hw
	local search_x = PAD + select(1, ctx.get_text_size("System Monitor")) + 20
	local search_w = hint_x - 12 - search_x
	local search_h = lh + 4
	local search_y = hh + math.floor((hh - search_h) / 2)
	if search_w > 120 then
		p.input:set_rect(search_x, search_y, search_w, search_h)
		p.input:draw(p)
	end

	local y = m.HEADER_H + 12

	local pct = M.cur_cpu_agg or 0
	p:text(PAD, y, "CPU", T.on_var)
	draw_bar(bar_x, y + math.floor((lh - m.BAR_H) / 2), bar_w, m.BAR_H, pct, load_color(T, pct))
	p:text(W - PAD - PCT_W, y, string.format("%6.1f%%", pct), T.on_surface)
	y = y + m.ROW_H

	p:rect(PAD, y, inner_w, m.SPARK_H, T.surface)
	local slot_w = inner_w / HISTORY_LEN
	for i = 0, HISTORY_LEN - 1 do
		local idx = ((M.history_head + i) % HISTORY_LEN) + 1
		local v = M.history[idx] or 0
		local bh = math.floor((m.SPARK_H - 2) * v / 100)
		if bh > 0 then
			local bx = math.floor(PAD + i * slot_w)
			local by = y + m.SPARK_H - 1 - bh
			local bw = math.max(1, math.floor(slot_w) - 1)
			p:rect(bx, by, bw, bh, load_color(T, v))
		end
	end
	y = y + m.SPARK_H + 12

	for i = 1, M.ncores_display or 0 do
		local v = M.cur_cores[i] or 0
		p:text(PAD, y, string.format("c%-2d", i - 1), T.hint)
		draw_bar(bar_x, y + math.floor((lh - 4) / 2), bar_w, 4, v, load_color(T, v))
		p:text(W - PAD - PCT_W, y, string.format("%6.1f%%", v), T.on_var)
		y = y + m.CORE_H
	end
	y = y + 8
	p:rect(PAD, y, inner_w, 1, T.outline)
	y = y + 10

	local mem = M.cur_mem or {}
	local mem_total = mem.MemTotal or 1
	local mem_avail = mem.MemAvailable or mem.MemFree or 0
	local mem_used = mem_total - mem_avail
	local mem_pct = mem_used / mem_total * 100

	p:text(PAD, y, "mem", T.on_var)
	draw_bar(bar_x, y + math.floor((lh - m.BAR_H) / 2), bar_w, m.BAR_H, mem_pct, load_color(T, mem_pct))
	local mem_str = string.format("%s/%s %3.0f%%", fmt_bytes_kb(mem_used), fmt_bytes_kb(mem_total), mem_pct)
	local mw = select(1, ctx.get_text_size(mem_str))
	p:text(W - PAD - mw, y, mem_str, T.on_surface)
	y = y + m.ROW_H

	local swp_total = mem.SwapTotal or 0
	local swp_free = mem.SwapFree or 0
	local swp_used = swp_total - swp_free
	local swp_pct = swp_total > 0 and (swp_used / swp_total * 100) or 0
	p:text(PAD, y, "swap", T.on_var)
	draw_bar(bar_x, y + math.floor((lh - m.BAR_H) / 2), bar_w, m.BAR_H, swp_pct, load_color(T, swp_pct))
	local swp_str = swp_total > 0
			and string.format("%s/%s %3.0f%%", fmt_bytes_kb(swp_used), fmt_bytes_kb(swp_total), swp_pct)
		or "--"
	local sw = select(1, ctx.get_text_size(swp_str))
	p:text(W - PAD - sw, y, swp_str, T.on_surface)
	y = y + m.ROW_H + 10
	p:rect(PAD, y, inner_w, 1, T.outline)
	y = y + 10

	local pid_x = PAD
	local name_x = PAD + 90
	local cpu_x = PAD + 440
	local mem_x = PAD + 520
	p:text(pid_x, y, "PID", T.hint)
	p:text(name_x, y, "NAME", T.hint)
	p:text(cpu_x, y, "CPU%", T.hint)
	p:text(mem_x, y, "MEM%", T.hint)

	m.rect_list.x = PAD
	m.rect_list.y = y + m.ROW_H
	m.rect_list.w = inner_w - 8
	m.rect_list.h = m.VISIBLE_ROWS * m.ROW_H
	y = y + m.ROW_H

	local row_h = m.ROW_H
	local name_max_w = cpu_x - name_x - 12
	M:clamp_scroll()
	for i = 0, m.VISIBLE_ROWS - 1 do
		local idx = M.scroll + i + 1
		if idx > #M.filtered then
			break
		end
		local proc = M.filtered[idx]
		local ry = y + i * row_h
		local selected = (proc.pid == M.selected_pid)
		if selected then
			p:rect(PAD - 4, ry, inner_w + 8, row_h, T.surface_hover)
		end
		p:text(pid_x, ry, string.format("%-7d", proc.pid), selected and T.on_surface or T.on_var)
		local name = proc.name
		if select(1, ctx.get_text_size(name)) > name_max_w then
			local cut = #name
			while cut > 0 do
				if select(1, ctx.get_text_size(name:sub(1, cut) .. "…")) <= name_max_w then
					name = name:sub(1, cut) .. "…"
					break
				end
				cut = cut - 1
			end
		end
		p:text(name_x, ry, name, T.on_surface)
		local cpu_col = proc.cpu >= 80 and T.crit or proc.cpu >= 30 and T.warn or T.good
		p:text(cpu_x, ry, string.format("%6.1f", proc.cpu), cpu_col)
		local mp = proc.mem / (mem_total * 1024) * 100
		p:text(mem_x, ry, string.format("%6.1f%%", mp), T.on_var)
	end

	local list_top = m.rect_list.y
	local list_h = m.rect_list.h
	local sbar_x = m.rect_list.x + m.rect_list.w + 2
	if #M.filtered > m.VISIBLE_ROWS then
		p:rect(sbar_x, list_top, 6, list_h, T.surface)
		local bar_h = math.max(30, math.floor(list_h * m.VISIBLE_ROWS / #M.filtered))
		local max_scroll = #M.filtered - m.VISIBLE_ROWS
		local bar_y = list_top + math.floor((list_h - bar_h) * M.scroll / max_scroll)
		p:rrect(sbar_x, bar_y, 6, bar_h, 3, T.outline)
	end

	local by = H - m.FOOTER_H + 4
	p:rect(PAD, by - 6, inner_w, 1, T.outline)
	local total = #M.procs
	local shown = #M.filtered
	local status = (shown < total)
			and string.format("filter %d / %d · ctrl+f search · ctrl+k kill", shown, total)
		or string.format("%d processes · ctrl+f search · ctrl+k kill", total)
	p:text(PAD, by + 4, status, T.hint)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true

	local probe = read_cpu_stat()
	local ncores_all = probe and #probe.cores or 4
	M.ncores_display = math.min(MAX_CORES, ncores_all)

	local panel = Panel.new(ctx, {
		name = "sysmon",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = function(c, us)
			local m = compute_layout(c.get_line_height(), M.ncores_display, c.scr_h, us)
			m.rect_list = { x = 0, y = 0, w = 0, h = 0 }
			return m
		end,
		size_fn = function(c)
			local m = compute_layout(c.get_line_height(), M.ncores_display, c.scr_h)
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = "ctrl+f search process or pid",
			on_change = function(v)
				M.search_query = v
				M:apply_filter()
			end,
			on_submit = function()
				M.panel:blur_input()
			end,
			on_cancel = function()
				M.panel:hide()
			end,
		},
		on_key = function(p, sym, text, ctrl, shift, state)
			if ctrl and sym == XK_k then
				M:kill_selected()
				return true
			end
			if ctrl and sym == 0x66 then
				p.input:focus()
				return true
			end
			return false
		end,
		on_show = function(p)
			M.search_query = ""
			if p.input then
				p.input:set_value("")
			end
			M:apply_filter()
			M:sample()
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				if btn == 4 then
					M.scroll = math.max(0, M.scroll - 3)
				else
					M.scroll = M.scroll + 3
					M:clamp_scroll()
				end
				return
			end
			local m = p.m
			local function in_rect(r)
				return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
			end
			if in_rect(m.rect_list) then
				local row = math.floor((my - m.rect_list.y) / m.ROW_H)
				local idx = M.scroll + row + 1
				if idx >= 1 and idx <= #M.filtered then
					M.selected_pid = M.filtered[idx].pid
					if btn == 3 then
						M:kill_selected()
					end
				end
				p:draw()
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	local m = compute_layout(ctx.get_line_height(), M.ncores_display, ctx.scr_h)
	m.rect_list = { x = 0, y = 0, w = 0, h = 0 }
	panel.m = m
	M.W, M.PAD = m.W, m.PAD
	M.HEADER_H, M.BAR_H, M.SPARK_H, M.ROW_H, M.CORE_H = m.HEADER_H, m.BAR_H, m.SPARK_H, m.ROW_H, m.CORE_H
	M.LABEL_W, M.PCT_W, M.FOOTER_H = m.LABEL_W, m.PCT_W, m.FOOTER_H
	M.VISIBLE_ROWS = m.VISIBLE_ROWS
	M.panel = panel
	ctx.register_panel("sysmon", panel)

	M.prev_cpu = nil
	M.prev_procs = {}
	M.cur_cpu_agg = 0
	M.cur_cores = {}
	M.cur_mem = nil
	M.procs = {}
	M.filtered = {}
	M.history = {}
	M.history_head = 0

	M.scroll = 0
	M.selected_pid = nil
	M.search_query = ""
	M.refresh_acc = 0

	M.prev_cpu = read_cpu_stat()
	for _, pid in ipairs(list_pids()) do
		local p = read_proc(pid)
		if p then
			M.prev_procs[pid] = { utime = p.utime, stime = p.stime }
		end
	end
	log("ready: %d cores", M.ncores_display)
end

function M.width(ctx)
	return select(1, ctx.get_text_size("mon")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "sysmon" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "mon", active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysmon", gx, gw)
	end
end

function M:kill_selected()
	local pid = M.selected_pid
	if not pid or type(pid) ~= "number" then
		return
	end
	os.execute("kill -TERM " .. pid .. " 2>/dev/null")
	M.ctx.notify(string.format("SIGTERM sent to pid %d", pid), { style = "warning", duration = 2000 })
	M.selected_pid = nil
	M:sample()
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	M.refresh_acc = M.refresh_acc + dt
	if M.refresh_acc >= REFRESH_MS then
		M.refresh_acc = 0
		M:sample()
		if M.panel.visible then
			M.panel:draw()
		end
	end
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
