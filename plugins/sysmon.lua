local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("sysmon")

local REFRESH_MS = 1000
local HISTORY_LEN = 60
local MAX_CORES = 8
local CLK_TCK = 100
local PAGE_SIZE = 4096
local PROC_FETCH_N = 200

local XK_k = 0x6b
local XK_ESCAPE = 0xff1b

-- readdir via ffi: io.popen("ls /proc") on every sample blocked the main loop
local ok_ffi, ffi = pcall(require, "ffi")
if ok_ffi then
	-- cdef symbols are global: a hot reload re-runs this file and errors
	-- with "attempt to redefine 'dirent'" — ignore, signatures unchanged
	pcall(ffi.cdef, [[
		typedef struct DIR DIR;
		typedef struct dirent {
			unsigned long long d_ino;
			long long d_off;
			unsigned short d_reclen;
			unsigned char d_type;
			char d_name[256];
		} dirent;
		DIR *opendir(const char *);
		dirent *readdir(DIR *);
		int closedir(DIR *);
	]])
end

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

local function read_load_uptime()
	local f = io.open("/proc/loadavg", "r")
	if f then
		local line = f:read("*l")
		f:close()
		local a, b, c = line:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
		if a then
			M.cur_load = string.format("%.2f %.2f %.2f", tonumber(a), tonumber(b) or 0, tonumber(c) or 0)
		end
	end
	f = io.open("/proc/uptime", "r")
	if f then
		local line = f:read("*l")
		f:close()
		local sec = tonumber(line:match("([%d%.]+)")) or 0
		local h = math.floor(sec / 3600)
		local m = math.floor((sec % 3600) / 60)
		M.cur_up = h >= 24
			and I.t("%dd %dh", math.floor(h / 24), h % 24)
			or I.t("%dh %dm", h, m)
	end
end

local function list_pids()
	local pids = {}
	if ok_ffi then
		local d = ffi.C.opendir("/proc")
		if d ~= nil then
			while true do
				local e = ffi.C.readdir(d)
				if e == nil then
					break
				end
				local pid = tonumber(ffi.string(e.d_name))
				if pid then
					pids[#pids + 1] = pid
				end
			end
			ffi.C.closedir(d)
		end
		return pids
	end
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
	read_load_uptime()
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

-- state-changing actions are deferred to M.tick and run under pcall —
-- running them from inside draw() mutates business state mid-draw
local function defer(fn)
	M.pending_action = fn
end

-- MIUIX-style geometry: rounded card rows, unified side padding, small
-- hint-coloured group titles in their own band with wide group separation
local PAD, SB_W = 20, 6
local ROW_GAP = 8 -- gap between row cards
local CARD_R = 14 -- row card corner radius
local GROUP_GAP = 28 -- gap between a card and the next group title
local TOP_PAD = 14 -- breathing room under the header
local BAR_H = 8 -- load bar height
local SPARK_H = 48 -- history sparkline height
local CHIP_GAP = 10 -- gap between per-core chips
local LABEL_W = 60 -- fixed label column inside the cpu card
local CPU_W, MEM_W = 72, 84 -- right-aligned list columns

local function row_h(lh)
	return math.max(46, lh + 28)
end

local function chip_h(lh)
	return math.max(40, lh + 22)
end

local function title_h(lh)
	return lh + 8
end

local function compute_layout(lh, ncores_display, scr_h, user_size)
	local L = {}
	L.PAD = PAD
	L.W = 720
	L.HEADER_H = lh + 26
	L.SEARCH_ROW = lh + 24 -- search input row under the header
	L.FOOTER_H = lh + 30
	L.ROW_H = row_h(lh)
	L.CHIP_H = chip_h(lh)
	L.TITLE_H = title_h(lh)
	L.CPU_CARD_H = L.ROW_H + SPARK_H + 16
	local chip_rows = math.ceil(math.max(1, ncores_display) / 4)
	L.CORES_H = chip_rows * L.CHIP_H + (chip_rows - 1) * CHIP_GAP
	-- header + search row + cpu/cores/memory/system groups + processes title
	-- + footer are fixed; the process list takes the remainder of the height
	local fixed = L.HEADER_H + 6 + L.SEARCH_ROW + TOP_PAD
		+ L.TITLE_H + L.CPU_CARD_H + ROW_GAP + L.CORES_H
		+ GROUP_GAP + L.TITLE_H + L.ROW_H + ROW_GAP + L.ROW_H
		+ GROUP_GAP + L.TITLE_H + L.ROW_H + ROW_GAP + L.ROW_H
		+ GROUP_GAP + L.TITLE_H
		+ L.FOOTER_H
	L.FIXED_H = fixed
	-- natural height follows the content rows, capped at 85% of the screen;
	-- the list always keeps room for at least 4 visible rows
	local want_h = math.min(math.floor(scr_h * 0.85), fixed + 6 * L.ROW_H)
	if want_h < fixed + L.ROW_H * 4 then
		want_h = fixed + L.ROW_H * 4
	end
	if user_size then
		L.W = math.max(560, user_size.w)
		want_h = math.max(380, user_size.h)
	end
	L.H = want_h
	L.VISIBLE_ROWS = math.max(4, math.floor((want_h - fixed) / L.ROW_H))
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
	local lh, PAD = ctx.get_line_height(), m.PAD
	-- self-heal on resize: follow the live surface, re-derive the list
	-- height and visible rows so the view bottom/footer always match p.w/p.h
	m.W, m.H = p.w, p.h
	local W, H = m.W, m.H
	-- the search input (own row under the header) grows downward when text
	-- wraps: shift the body down by the growth (Panel:fit grows the panel)
	local in_extra = p.input and p.input:extra_h() or 0
	local list_h = H - m.FIXED_H - in_extra
	if list_h < m.ROW_H * 4 then
		list_h = m.ROW_H * 4
	end
	local visible = math.max(1, math.floor(list_h / m.ROW_H))
	m.VISIBLE_ROWS = visible
	M.VISIBLE_ROWS = visible

	local card_x = PAD
	local card_w = W - PAD * 2 - SB_W
	local CR = card_x + card_w
	local content_x = card_x + 16
	local bar_x = content_x + LABEL_W

	-- scrollable content is painted FIRST; the fixed chrome (header, footer)
	-- is painted on top further down, which clips every band without needing
	-- a scissor primitive

	local y = m.HEADER_H + 6 + m.SEARCH_ROW + TOP_PAD + in_extra

	-- cpu group: aggregate load row + history sparkline in one card
	p:text(card_x + 6, y + m.TITLE_H - lh - 2, I.t("CPU"), T.hint)
	y = y + m.TITLE_H
	p:rrect(card_x, y, card_w, m.CPU_CARD_H, CARD_R, T.surface)
	local ty = y + math.floor((m.ROW_H - lh) / 2)
	local pct = M.cur_cpu_agg or 0
	p:text(content_x, ty, I.t("CPU"), T.on_var)
	local pct_str = string.format("%5.1f%%", pct)
	local pw = ctx.text_width(pct_str)
	p:text(CR - 16 - pw, ty, pct_str, T.hint)
	local bar_w = CR - 16 - pw - 12 - bar_x
	if bar_w > 40 then
		ui:progress(bar_x, ty + math.floor((lh - BAR_H) / 2), bar_w, BAR_H, pct, load_color(T, pct))
	end
	local spark_y = y + m.ROW_H + 6
	local slot_w = (card_w - 32) / HISTORY_LEN
	for i = 0, HISTORY_LEN - 1 do
		local idx = ((M.history_head + i) % HISTORY_LEN) + 1
		local v = M.history[idx] or 0
		local bh = math.floor((SPARK_H - 2) * v / 100)
		if bh > 0 then
			local bx = math.floor(content_x + i * slot_w)
			local by = spark_y + SPARK_H - 1 - bh
			local bw = math.max(1, math.floor(slot_w) - 1)
			p:rect(bx, by, bw, bh, load_color(T, v))
		end
	end
	y = y + m.CPU_CARD_H + ROW_GAP

	-- per-core load as chips in a 4-column grid
	if (M.ncores_display or 0) > 0 then
		local chip_w = math.floor((card_w - 3 * CHIP_GAP) / 4)
		for i = 1, M.ncores_display do
			local col = (i - 1) % 4
			local crow = math.floor((i - 1) / 4)
			local cxp = card_x + col * (chip_w + CHIP_GAP)
			local cyp = y + crow * (m.CHIP_H + CHIP_GAP)
			p:rrect(cxp, cyp, chip_w, m.CHIP_H, CARD_R, T.surface)
			local v = M.cur_cores[i] or 0
			local cty = cyp + 4
			p:text(cxp + 12, cty, string.format("c%d", i - 1), T.on_var)
			local cs = string.format("%5.1f%%", v)
			local cw = ctx.text_width(cs)
			p:text(cxp + chip_w - 12 - cw, cty, cs, T.hint)
			ui:progress(cxp + 12, cyp + m.CHIP_H - 12, chip_w - 24, 6, v, load_color(T, v))
		end
	end
	y = y + m.CORES_H

	-- memory group: mem + swap cards
	local mem = M.cur_mem or {}
	local mem_total = mem.MemTotal or 1
	local mem_avail = mem.MemAvailable or mem.MemFree or 0
	local mem_used = mem_total - mem_avail
	local mem_pct = mem_used / mem_total * 100
	y = y + GROUP_GAP
	p:text(card_x + 6, y + m.TITLE_H - lh - 2, I.t("memory"), T.hint)
	y = y + m.TITLE_H
	p:rrect(card_x, y, card_w, m.ROW_H, CARD_R, T.surface)
	ty = y + math.floor((m.ROW_H - lh) / 2)
	p:text(content_x, ty, I.t("mem"), T.on_var)
	local mem_str = string.format("%s / %s %3.0f%%", fmt_bytes_kb(mem_used), fmt_bytes_kb(mem_total), mem_pct)
	local mw = ctx.text_width(mem_str)
	p:text(CR - 16 - mw, ty, mem_str, T.hint)
	bar_w = CR - 16 - mw - 12 - bar_x
	if bar_w > 40 then
		ui:progress(bar_x, ty + math.floor((lh - BAR_H) / 2), bar_w, BAR_H, mem_pct, load_color(T, mem_pct))
	end
	y = y + m.ROW_H + ROW_GAP

	local swp_total = mem.SwapTotal or 0
	local swp_free = mem.SwapFree or 0
	local swp_used = swp_total - swp_free
	local swp_pct = swp_total > 0 and (swp_used / swp_total * 100) or 0
	p:rrect(card_x, y, card_w, m.ROW_H, CARD_R, T.surface)
	ty = y + math.floor((m.ROW_H - lh) / 2)
	p:text(content_x, ty, I.t("swap"), T.on_var)
	local swp_str = swp_total > 0
			and string.format("%s / %s %3.0f%%", fmt_bytes_kb(swp_used), fmt_bytes_kb(swp_total), swp_pct)
		or "--"
	local sw = ctx.text_width(swp_str)
	p:text(CR - 16 - sw, ty, swp_str, T.hint)
	bar_w = CR - 16 - sw - 12 - bar_x
	if bar_w > 40 then
		ui:progress(bar_x, ty + math.floor((lh - BAR_H) / 2), bar_w, BAR_H, swp_pct, load_color(T, swp_pct))
	end
	y = y + m.ROW_H

	-- system group: load + uptime text cards
	y = y + GROUP_GAP
	p:text(card_x + 6, y + m.TITLE_H - lh - 2, I.t("system"), T.hint)
	y = y + m.TITLE_H
	p:rrect(card_x, y, card_w, m.ROW_H, CARD_R, T.surface)
	ty = y + math.floor((m.ROW_H - lh) / 2)
	p:text(content_x, ty, I.t("load"), T.on_var)
	local load_str = M.cur_load or "--"
	local lw = ctx.text_width(load_str)
	p:text(CR - 16 - lw, ty, load_str, T.hint)
	y = y + m.ROW_H + ROW_GAP
	p:rrect(card_x, y, card_w, m.ROW_H, CARD_R, T.surface)
	ty = y + math.floor((m.ROW_H - lh) / 2)
	p:text(content_x, ty, I.t("uptime"), T.on_var)
	local up_str = I.t("up %s", M.cur_up or "--")
	local uw = ctx.text_width(up_str)
	p:text(CR - 16 - uw, ty, up_str, T.hint)
	y = y + m.ROW_H

	-- processes group: card rows; the group title doubles as the column
	-- header band (cpu/mem hints aligned over their columns)
	y = y + GROUP_GAP
	local mem_right = CR - 16
	local cpu_right = mem_right - MEM_W - 16
	p:text(card_x + 6, y + m.TITLE_H - lh - 2, I.t("processes"), T.hint)
	local cpu_hdr = I.t("CPU%")
	p:text(cpu_right - ctx.text_width(cpu_hdr), y + m.TITLE_H - lh - 2, cpu_hdr, T.hint)
	local mem_hdr = I.t("MEM%")
	p:text(mem_right - ctx.text_width(mem_hdr), y + m.TITLE_H - lh - 2, mem_hdr, T.hint)
	y = y + m.TITLE_H

	local pid_max = 0
	for i = 0, visible - 1 do
		local idx = M.scroll + i + 1
		if idx > #M.filtered then
			break
		end
		local pwd = ctx.text_width(tostring(M.filtered[idx].pid))
		if pwd > pid_max then
			pid_max = pwd
		end
	end
	local pid_x = content_x
	local name_x = pid_x + pid_max + 26
	local name_max_w = math.max(40, cpu_right - CPU_W - 12 - name_x)

	m.rect_list.x = card_x
	m.rect_list.y = y
	m.rect_list.w = card_w
	m.rect_list.h = visible * m.ROW_H

	M:clamp_scroll()
	for i = 0, visible - 1 do
		local idx = M.scroll + i + 1
		if idx > #M.filtered then
			break
		end
		local proc = M.filtered[idx]
		local ry = y + i * m.ROW_H
		local selected = proc.pid == M.selected_pid
		local hovered = ui:hover(card_x, ry, card_w, m.ROW_H)
		p:rrect(card_x, ry, card_w, m.ROW_H, CARD_R,
			selected and T.surface_hi or (hovered and T.surface_hover or T.surface))
		local ry_ty = ry + math.floor((m.ROW_H - lh) / 2)
		p:text(pid_x, ry_ty, tostring(proc.pid), T.hint)
		local name = proc.name
		if ctx.text_width(name) > name_max_w then
			local cut = #name
			while cut > 0 do
				if ctx.text_width(name:sub(1, cut) .. "…") <= name_max_w then
					name = name:sub(1, cut) .. "…"
					break
				end
				cut = cut - 1
			end
		end
		p:text(name_x, ry_ty, name, selected and T.on_surface or T.on_var)
		local cpu_col = proc.cpu >= 80 and T.crit or proc.cpu >= 30 and T.warn or T.good
		local cstr = string.format("%5.1f", proc.cpu)
		p:text(cpu_right - ctx.text_width(cstr), ry_ty, cstr, cpu_col)
		local mp = proc.mem / (mem_total * 1024) * 100
		local mstr = string.format("%5.1f%%", mp)
		p:text(mem_right - ctx.text_width(mstr), ry_ty, mstr, T.hint)
	end
	y = y + m.rect_list.h

	-- scrollbar (right edge, inside padding)
	if #M.filtered > visible then
		local off = ui:scrollbar("sm_sb", W - 14, m.rect_list.y, SB_W, m.rect_list.h,
			M.scroll, #M.filtered - visible)
		M.scroll = off
	end

	-- fixed chrome painted last so content can never overlap it

	-- footer: opaque band covers rows scrolled past the bottom; pill buttons
	-- laid out like a MIUI dialog (primary action filled)
	local fy = H - m.FOOTER_H - in_extra
	p:rect(0, fy, W, m.FOOTER_H + in_extra, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	local bh = lh + 14
	local bo = math.floor((m.FOOTER_H - bh) / 2)
	local bw = 76
	if M.pending then
		local nm = M.pending.name
		if #nm > 24 then
			nm = nm:sub(1, 24) .. "…"
		end
		local q = I.t("kill %d %s?", M.pending.pid, nm)
		local q_max = W - PAD * 2 - 2 * bw - 12 - 24
		while #q > 4 and ctx.text_width(q) > q_max do
			q = q:sub(1, -2)
		end
		p:text(PAD, mid_y, q, T.crit)
		-- state changes are deferred: draw only records the hit intent
		if ui:id_button("sm_cancel", W - PAD - 2 * bw - 12, fy + bo, bw, bh, I.t("cancel"),
			{ tonal = true }) then
			defer(function()
				M.pending = nil
			end)
		end
		if ui:id_button("sm_kill", W - PAD - bw, fy + bo, bw, bh, I.t("kill"),
			{ filled = true, color = T.crit }) then
			defer(function()
				M:do_kill()
			end)
		end
	else
		local total = #M.procs
		local shown = #M.filtered
		local status = (shown < total)
				and I.t("filter %d / %d · ctrl+f search · ctrl+k kill", shown, total)
			or I.t("%d processes · ctrl+f search · ctrl+k kill", total)
		p:text(PAD, mid_y, status, T.hint)
		if ui:id_button("sm_refresh", W - PAD - bw, fy + bo, bw, bh, I.t("refresh"),
			{ tonal = true }) then
			defer(function()
				M:sample()
				M.ctx.notify(I.t("refreshed"), { style = "info", duration = 1500 })
			end)
		end
	end

	-- header last: opaque fill also covers anything under the top edge;
	-- the search input lives on its own row below the header, so long text
	-- grows the row downward (Panel:fit adds the extra height) instead of
	-- overlapping the header band or the body cards
	local hh = p:draw_header(I.t("System Monitor"), Util.keybind_hint(ctx, "toggle_sysmon"), PAD)
	p.input:set_rect(PAD, hh + 6, W - PAD * 2, lh + 24)
	p.input:draw(p)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending_action = nil

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
			placeholder = I.t("ctrl+f search process or pid"),
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
			if sym == XK_ESCAPE and M.pending then
				M.pending = nil
				return true
			end
			if ctrl and sym == XK_k then
				if M.pending then
					M:do_kill()
				else
					for _, pr in ipairs(M.filtered) do
						if pr.pid == M.selected_pid then
							M:ask_kill(pr)
							break
						end
					end
				end
				return true
			end
			if ctrl and sym == 0x66 then
				p.input:focus()
				return true
			end
			return false
		end,
		on_show = function(p)
			M.pending = nil
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
						M:ask_kill(M.filtered[idx])
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
	M.VISIBLE_ROWS = m.VISIBLE_ROWS
	M.panel = panel
	ctx.register_panel("sysmon", panel)

	M.prev_cpu = nil
	M.prev_procs = {}
	M.cur_cpu_agg = 0
	M.cur_cores = {}
	M.cur_mem = nil
	M.cur_load = "--"
	M.cur_up = "--"
	M.procs = {}
	M.filtered = {}
	M.history = {}
	M.history_head = 0

	M.scroll = 0
	M.selected_pid = nil
	M.pending = nil
	M.search_query = ""
	M.refresh_acc = 0
	M._fit_cores = M.ncores_display
	M.need_fit = false

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
	return select(1, ctx.get_text_size(I.t("mon"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "sysmon" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("mon"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysmon", gx, gw)
	end
end

function M:ask_kill(proc)
	if not proc then
		return
	end
	M.pending = { pid = proc.pid, name = proc.name }
end

function M:do_kill()
	local pid = M.pending and M.pending.pid
	if not pid or type(pid) ~= "number" then
		return
	end
	-- os.execute yields the raw exit code (0 = success), never a boolean
	local rc = os.execute("kill -TERM " .. pid .. " 2>/dev/null")
	if rc == 0 then
		M.ctx.notify(I.t("SIGTERM sent to pid %d", pid), { style = "success", duration = 2000 })
	else
		M.ctx.notify(I.t("kill failed: pid %d", pid), { style = "error", duration = 2500 })
	end
	M.pending = nil
	M.selected_pid = nil
	M:sample()
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	if M.pending_action then
		local fn = M.pending_action
		M.pending_action = nil
		local ok, err = pcall(fn)
		if not ok then
			log("pending action error: %s", tostring(err))
		end
		if M.panel.visible then
			M.panel:draw()
		end
	end
	M.refresh_acc = M.refresh_acc + dt
	if M.refresh_acc >= REFRESH_MS then
		M.refresh_acc = 0
		M:sample()
		-- auto-fit when a content-driven size input changed (core count is
		-- the only data-dependent term in size_fn); fit() no-ops if unchanged
		if M.ncores_display ~= M._fit_cores then
			M._fit_cores = M.ncores_display
			M.need_fit = true
		end
		-- need_fit is consumed here, never inside draw
		if M.need_fit then
			M.need_fit = false
			M.panel:fit()
		end
		if M.panel.visible then
			M.panel:draw()
		end
	end
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
	M.pending_action = nil
end

return M
