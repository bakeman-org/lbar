-- plugins/clock.lua — clock + calendar panel with schedule/alarms.
-- Scheduling uses a Material-style picker: click a calendar day to select
-- the date, then add → footer shows a date chip + a time chip that opens
-- an Android clock dial (view "time": outer ring 13-23+00, inner ring
-- 1-12, atan2 sector hit testing, pointer drawn as a 2px rect chain; the
-- minutes dial follows with 00-55 marks, 1-minute fine inner slices and
-- +/-1 nudges). The calendar header shows the year (click → "years" grid
-- view) plus the selected date. Clicking a schedule row opens the same
-- form pre-filled for editing; submitting updates that entry in place
-- (M.edit_idx, nil = create-new). Entries persist to clock.schedule_file;
-- due entries fire a one-shot warning toast. Panel views form a small
-- state machine: "form" | "time" | "years". Layout auto-fits content
-- (calendar rows, schedule rows, wrapped description input) and reflows
-- on user resize. Legacy "YYYY-MM-DD HH:MM text" parsing is kept for
-- offline tests.
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local str, last_sec, P = "--:--", -1, nil
local today = os.date("*t")
local view_year, view_month = today.year, today.month

local SCHEDULE_MAX = 6

-- entries: { y, mo, d, mi, txt }; fired[key] marks already-alerted
local entries, fired = {}, {}
M.adding = false
M.need_fit = false
M.view = "form" -- panel view: "form" | "time" | "years"
M.tp_phase = "h" -- time dial phase: hours then minutes
M.sel = nil -- picked calendar day { y, mo, d } used by the add picker
M.edit_idx = nil -- schedule row being edited (nil = the form creates new)
local pick_h, pick_mi = 8, 30

local function state_path()
	local home = os.getenv("HOME") or "/tmp"
	local base = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
	return base .. "/lbar/schedule.conf"
end

local function sched_file(ctx)
	local c = ctx.config.clock
	return (c and c.schedule_file) or state_path()
end

local function entry_hm(e)
	return math.floor(e.mi / 60), e.mi % 60
end

local function entry_key(e)
	local h, m = entry_hm(e)
	return string.format("%04d-%02d-%02d %02d:%02d %s", e.y, e.mo, e.d, h, m, e.txt)
end

local function entry_epoch(e)
	local h, m = entry_hm(e)
	return os.time({ year = e.y, month = e.mo, day = e.d, hour = h, min = m })
end

local function sort_entries()
	table.sort(entries, function(a, b)
		local ea, eb = entry_epoch(a), entry_epoch(b)
		if ea == eb then
			return a.txt < b.txt
		end
		return ea < eb
	end)
end

local function load_entries(ctx)
	entries, fired = {}, {}
	local f = io.open(sched_file(ctx), "r")
	if not f then
		return
	end
	local now = os.time()
	for line in f:lines() do
		local y, mo, d, h, mi, txt =
			line:match("^(%d%d%d%d)-(%d%d)-(%d%d)%s+(%d%d):(%d%d)%s+(.+)$")
		if y then
			local e = {
				y = tonumber(y), mo = tonumber(mo), d = tonumber(d),
				mi = tonumber(h) * 60 + tonumber(mi), txt = txt,
			}
			if entry_epoch(e) <= now then
				fired[entry_key(e)] = true -- past entries never alert on (re)load
			end
			entries[#entries + 1] = e
		end
	end
	f:close()
	sort_entries()
end

local function save_entries(ctx)
	local path = sched_file(ctx)
	local dir = path:match("^(.*)/")
	if dir and dir ~= "" then
		os.execute("mkdir -p '" .. dir .. "' 2>/dev/null")
	end
	local f = io.open(path, "w")
	if not f then
		return
	end
	for _, e in ipairs(entries) do
		local h, m = entry_hm(e)
		f:write(string.format("%04d-%02d-%02d %02d:%02d %s\n", e.y, e.mo, e.d, h, m, e.txt))
	end
	f:close()
end

-- legacy text parser (kept for offline tests): "YYYY-MM-DD HH:MM text" |
-- "MM-DD HH:MM text" | "HH:MM text"; short forms roll forward when past
local function parse_entry(s)
	s = s:match("^%s*(.-)%s*$")
	local bt = os.date("*t")
	local y, mo, d, h, mi, txt = s:match("^(%d%d%d%d)-(%d%d)-(%d%d)%s+(%d+):(%d+)%s+(.+)$")
	if not y then
		local m2, d2, h2, m3, tx = s:match("^(%d%d)-(%d%d)%s+(%d+):(%d+)%s+(.+)$")
		if m2 then
			mo, d, h, mi, txt = tonumber(m2), tonumber(d2), tonumber(h2), tonumber(m3), tx
			y = bt.year
			if os.time({ year = y, month = mo, day = d, hour = h, min = mi }) < os.time() then
				y = y + 1
			end
		end
	end
	if not y then
		local h2, m3, tx = s:match("^(%d+):(%d+)%s+(.+)$")
		if h2 then
			h, mi, txt = tonumber(h2), tonumber(m3), tx
			y, mo, d = bt.year, bt.month, bt.day
			if os.time({ year = y, month = mo, day = d, hour = h, min = mi }) < os.time() then
				local tom = os.date("*t", os.time({ year = y, month = mo, day = d, hour = 12 }) + 86400)
				y, mo, d = tom.year, tom.month, tom.day
			end
		end
	end
	if not y or not txt or #txt == 0 then
		return nil
	end
	y, mo, d, h, mi = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
	if mi > 59 or h > 23 or mo > 12 or d > 31 then
		return nil
	end
	return { y = y, mo = mo, d = d, mi = h * 60 + mi, txt = txt }
end

local function add_entry(ctx, e)
	entries[#entries + 1] = e
	sort_entries()
	save_entries(ctx)
	M.need_fit = true -- auto-fit in tick (never resize from draw)
	ctx.notify(I.t("saved") .. ": " .. entry_key(e), { style = "success" })
end

-- exposed for offline stub tests; unused at runtime
M._parse_entry = parse_entry
M._load_entries = load_entries
M._save_entries = save_entries
M._entries = function()
	return entries
end
M._fired = function()
	return fired
end
M._get_pick = function()
	return pick_h, pick_mi
end
M._set_pick = function(h, mi) -- offline tests: drive the time picker
	pick_h, pick_mi = h, mi
end
M._view_state = function()
	return M.view, view_year, view_month
end

local function days_in_month(y, m)
	local t1 = os.time({ year = y, month = m, day = 1, hour = 12 })
	local ny, nm = (m == 12) and y + 1 or y, (m == 12) and 1 or m + 1
	local t2 = os.time({ year = ny, month = nm, day = 1, hour = 12 })
	return math.floor((t2 - t1) / 86400 + 0.5)
end
local function first_wday(y, m)
	return tonumber(os.date("%w", os.time({ year = y, month = m, day = 1, hour = 12 })))
end
local function cal_rows_needed(y, m)
	return math.ceil((first_wday(y, m) + days_in_month(y, m)) / 7)
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 24
	m.COL_W = lh + 40
	m.W = math.max(440, m.PAD * 2 + m.COL_W * 7) -- wide enough for the dial
	m.HEAD_H = lh + 26 -- must match Panel:draw_header's strip height
	m.ROW_H = lh + 16 -- calendar cell pitch
	m.SCHED_GAP = lh + 16 -- schedule row pitch
	m.CHIP_H = lh + 14 -- picker chip height
	m.BASE_IN = lh + 8 -- base description input height
	m.DIAL_RO = math.floor(lh * 4) -- outer ring label radius
	m.DIAL_RI = math.floor(m.DIAL_RO * 0.64) -- inner ring label radius
	m.DIAL_D = m.DIAL_RO * 2 + 28 -- dial hit diameter (>= 2.6 * lh)
	m.FOOT_H = lh + 40
	m.FOOT_ADD = 10 + m.CHIP_H + 10 + m.BASE_IN + 20
	-- reserve room for the auto-fit description input (grows with wrapped
	-- rows; Panel:tick flags the re-fit when the input height changes)
	local in_h = (P and P.input and P.input:height()) or m.BASE_IN
	m.FOOT_GROW = (M.adding and M.view == "form")
		and math.max(0, in_h - m.BASE_IN) or 0
	if M.view == "time" then
		local y = m.HEAD_H + 14
		y = y + (lh + 16) + 14 -- HH:MM readout pills
		y = y + m.DIAL_D + 20 + 12 -- dial card
		y = y + (lh + 14) + 14 -- nudge + cancel/ok row
		m.H = y
	elseif M.view == "years" then
		local y = m.HEAD_H + 14
		y = y + lh + 4 -- year line
		y = y + lh + 14 -- selected date line
		y = y + 10 + (lh + 26) * 5 + 14 -- 5x5 year grid
		m.H = y
	else
		local rows = cal_rows_needed(view_year, view_month)
		local n = math.max(1, math.min(#entries, SCHEDULE_MAX))
		-- running layout, mirrored verbatim by draw_panel (keeps fit exact)
		local y = m.HEAD_H + 10 -- big time
		y = y + lh + 6 -- date line
		y = y + lh + 14 -- divider
		y = y + 12 -- picker header: year line + selected date line
		y = y + lh + 4 -- year line
		y = y + lh + 14 -- selected date line
		y = y + lh + 10 -- weekday row
		y = y + lh + 10 -- calendar top
		m.H = y + m.ROW_H * rows -- calendar (actual row count)
			+ 16 + 1 + 12 + (lh + 10) -- divider + schedule header
			+ m.SCHED_GAP * n + 14 -- schedule rows (>= 1 for empty state)
			+ (M.adding and (m.FOOT_ADD + m.FOOT_GROW) or m.FOOT_H)
	end
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function sel_ymd()
	return M.sel or { y = today.year, mo = today.month, d = today.day }
end

local function sel_str()
	local s = sel_ymd()
	return string.format("%04d-%02d-%02d", s.y, s.mo, s.d)
end

local function start_add(p)
	M.adding = true
	M.edit_idx = nil
	M.view = "form"
	M.tp_phase = "h"
	local t = os.date("*t")
	pick_h = (t.hour + 1) % 24
	pick_mi = 0
	if not M.sel then
		M.sel = { y = t.year, mo = t.month, d = t.day }
	end
	M.need_fit = true -- footer grows a picker row; refit in tick
	if p.input then
		p.input:set_value("")
		p.input:focus()
	end
end

-- open the same form pre-filled with entry i; submit updates it in place
local function start_edit(p, i)
	local e = entries[i]
	if not e then
		return
	end
	M.adding = true
	M.edit_idx = i
	M.view = "form"
	M.tp_phase = "h"
	M.sel = { y = e.y, mo = e.mo, d = e.d }
	pick_h, pick_mi = entry_hm(e)
	M.need_fit = true
	if p.input then
		p.input:set_value(e.txt)
		p.input:focus()
	end
end

local function stop_add(p)
	M.adding = false
	M.edit_idx = nil
	M.view = "form"
	M.need_fit = true
	if p.input then
		p.input:blur()
		p.input:set_value("")
	end
end

local function submit_add(p)
	local ctx = p.ctx
	local txt = (p.input and p.input.value or ""):match("^%s*(.-)%s*$")
	if #txt == 0 then
		ctx.notify(I.t("invalid schedule format"), { style = "error" })
		return
	end
	if M.edit_idx and not entries[M.edit_idx] then
		M.edit_idx = nil -- row vanished meanwhile: fall back to create
	end
	local sel = sel_ymd()
	local e = { y = sel.y, mo = sel.mo, d = sel.d, mi = pick_h * 60 + pick_mi, txt = txt }
	local is_today_sel = sel.y == today.year and sel.mo == today.month and sel.d == today.day
	local orig = M.edit_idx and entries[M.edit_idx] or nil
	local time_kept = orig and orig.y == e.y and orig.mo == e.mo
		and orig.d == e.d and orig.mi == e.mi
	if entry_epoch(e) <= os.time() then
		if time_kept then
			-- editing a past entry without touching its time: keep it
		elseif not is_today_sel then
			ctx.notify(I.t("time already past"), { style = "error" })
			return
		else
			-- defaulted to today but the time slipped by: roll to tomorrow
			local tom = os.date("*t", os.time({ year = e.y, month = e.mo, day = e.d, hour = 12 }) + 86400)
			e.y, e.mo, e.d = tom.year, tom.month, tom.day
		end
	end
	if M.edit_idx then
		entries[M.edit_idx] = e -- update in place, keep the entry's identity
		if entry_epoch(e) <= os.time() then
			fired[entry_key(e)] = true -- don't re-alert stale past edits
		end
		sort_entries()
		save_entries(ctx)
		M.need_fit = true
		ctx.notify(I.t("updated") .. ": " .. entry_key(e), { style = "success" })
		stop_add(p)
	else
		add_entry(ctx, e)
		stop_add(p)
	end
	p:draw()
end

-- ── Material time dial helpers ──
-- point on a clock dial: deg 0 = top, growing clockwise
local function dial_xy(cx, cy, r, deg)
	local rad = math.rad(deg)
	return cx + math.sin(rad) * r, cy - math.cos(rad) * r
end

-- straight line as a chain of 2px rect steps (no line primitive)
local function draw_line(p, x0, y0, x1, y1, c)
	local dx, dy = x1 - x0, y1 - y0
	local steps = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / 2))
	for i = 0, steps do
		local t = i / steps
		p:rect(math.floor(x0 + dx * t) - 1, math.floor(y0 + dy * t) - 1, 2, 2, c)
	end
end

local function draw_dial_label(p, ctx, lh, x, y, s, sel, T)
	local tw = select(1, ctx.get_text_size(s))
	local tx = x - math.floor(tw / 2)
	local ty = y - math.floor(lh / 2)
	if sel then
		local d = lh + 6
		p:rrect(math.floor(x - d / 2), math.floor(y - d / 2), d, d, math.floor(d / 2), T.primary)
		p:text(tx, ty, s, T.on_primary)
	else
		p:text(tx, ty, s, T.on_surface)
	end
end

-- resolve a dial click: atan2 splits the dial into 12 sectors, the radius
-- splits inner/outer rings (hours) or fine/coarse minutes
local function dial_pick(mx, my, r)
	local dx, dy = mx - r.cx, my - r.cy
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > r.r_out then
		return -- square corner beyond the dial circle
	end
	local deg = math.deg(math.atan2(dx, -dy)) % 360
	local idx = math.floor((deg + 15) / 30) % 12
	if M.tp_phase == "h" then
		if dist < r.r_mid then
			pick_h = (idx == 0) and 12 or idx
		else
			pick_h = (idx == 0) and 0 or idx + 12
		end
		M.tp_phase = "m" -- hour chosen: advance to the minutes dial
	elseif dist < r.r_mid then
		pick_mi = math.floor((deg + 3) / 6) % 60 -- 6-degree fine slices
	else
		pick_mi = idx * 5 -- 30-degree coarse marks: 00/05/.../55
	end
end

-- ── view: "time" — Material clock dial ──
local function draw_time_view(p, m)
	local ctx, T, ui = p.ctx, p.ctx.theme, p.ui
	local lh, PAD, W_ = m.LH, m.PAD, m.W
	p:draw_header(I.t("Clock"), Util.keybind_hint(ctx, "toggle_clock"), PAD)
	-- the form input is hidden here: park it off-panel so stale hit rects
	-- can neither grab clicks nor keep keyboard focus
	if p.input then
		p.input:set_rect(PAD, m.H + 60, 120, m.BASE_IN)
	end
	-- HH:MM readout: active phase filled; click a pill to switch phase
	local ry = m.HEAD_H + 14
	local pill_h = lh + 16
	local pw = select(1, ctx.get_text_size("88")) + 26
	local colon_w = select(1, ctx.get_text_size(":"))
	local x0 = math.floor((W_ - (pw * 2 + colon_w + 16)) / 2)
	if ui and ui:id_button("tp_h", x0, ry, pw, pill_h,
		string.format("%02d", pick_h),
		M.tp_phase == "h" and { filled = true } or { tonal = true }) then
		M.tp_phase = "h"
	end
	p:text(x0 + pw + 8, ry + math.floor((pill_h - lh) / 2), ":", T.hint)
	if ui and ui:id_button("tp_m", x0 + pw + 8 + colon_w + 8, ry, pw, pill_h,
		string.format("%02d", pick_mi),
		M.tp_phase == "m" and { filled = true } or { tonal = true }) then
		M.tp_phase = "m"
	end
	-- dial card: surface card, surface_hi track, bg inner disc
	local dy = ry + pill_h + 14
	local card_h = m.DIAL_D + 20
	p:rrect(PAD, dy, W_ - PAD * 2, card_h, 16, T.surface)
	local ccx = math.floor(W_ / 2)
	local ccy = dy + 10 + math.floor(m.DIAL_D / 2)
	local tr = m.DIAL_RO + 14
	p:rrect(ccx - tr, ccy - tr, tr * 2, tr * 2, tr, T.surface_hi)
	local ir = m.DIAL_RI + 10
	p:rrect(ccx - ir, ccy - ir, ir * 2, ir * 2, ir, T.bg)
	-- hit rect consumed by on_press (sector + radius resolution)
	local dial_rect = {
		x = ccx - tr, y = ccy - tr, w = tr * 2, h = tr * 2,
		cx = ccx, cy = ccy, r_out = tr,
		r_mid = math.floor((m.DIAL_RI + m.DIAL_RO) / 2),
	}
	local deg, rad
	if M.tp_phase == "h" then
		M.hour_rects, M.min_rects = { dial_rect }, {}
		deg = (pick_h % 12) * 30
		rad = (pick_h >= 1 and pick_h <= 12) and m.DIAL_RI or m.DIAL_RO
	else
		M.hour_rects, M.min_rects = {}, { dial_rect }
		deg = pick_mi * 6
		rad = (pick_mi % 5 == 0) and m.DIAL_RO or m.DIAL_RI
	end
	-- pointer from the center dot to the selected value
	local hx, hy = dial_xy(ccx, ccy, rad, deg)
	draw_line(p, ccx, ccy, hx, hy, T.primary)
	p:rrect(ccx - 3, ccy - 3, 6, 6, 3, T.primary)
	if M.tp_phase == "h" then
		for v = 1, 12 do -- inner ring: 1-12
			local nx, ny = dial_xy(ccx, ccy, m.DIAL_RI, v * 30)
			draw_dial_label(p, ctx, lh, nx, ny, tostring(v), pick_h == v, T)
		end
		for v = 13, 23 do -- outer ring: 13-23
			local nx, ny = dial_xy(ccx, ccy, m.DIAL_RO, (v % 12) * 30)
			draw_dial_label(p, ctx, lh, nx, ny, tostring(v), pick_h == v, T)
		end
		local nx, ny = dial_xy(ccx, ccy, m.DIAL_RO, 0) -- outer ring: 00
		draw_dial_label(p, ctx, lh, nx, ny, "00", pick_h == 0, T)
	else
		for v = 0, 55, 5 do -- outer ring: 00/05/.../55
			local nx, ny = dial_xy(ccx, ccy, m.DIAL_RO, v * 6)
			draw_dial_label(p, ctx, lh, nx, ny, string.format("%02d", v), pick_mi == v, T)
		end
		if pick_mi % 5 ~= 0 then -- fine minute readout under the pointer
			local nx, ny = dial_xy(ccx, ccy, m.DIAL_RI, pick_mi * 6)
			draw_dial_label(p, ctx, lh, nx, ny, string.format("%02d", pick_mi), true, T)
		end
	end
	-- bottom row: +/-1 minute nudges, cancel/ok pills bottom-right
	local by = dy + card_h + 12
	if ui then
		if M.tp_phase == "m" then
			if ui:id_button("mi_dn", PAD, by, 40, lh + 14, "-1", { tonal = true }) then
				pick_mi = (pick_mi + 59) % 60
			end
			if ui:id_button("mi_up", PAD + 46, by, 40, lh + 14, "+1", { tonal = true }) then
				pick_mi = (pick_mi + 1) % 60
			end
		end
		if ui:id_button("tp_cancel", W_ - PAD - 56 - 8 - 72, by, 72, lh + 14,
			I.t("cancel"), { tonal = true }) then
			pick_h = M.tp_back_h or pick_h -- revert to the pre-dial values
			pick_mi = M.tp_back_mi or pick_mi
			M.view = "form"
			M.need_fit = true
			if p.input and M.adding then
				p.input:focus()
			end
		end
		if ui:id_button("tp_ok", W_ - PAD - 56, by, 56, lh + 14, I.t("ok"), { filled = true }) then
			M.view = "form"
			M.need_fit = true
			if p.input and M.adding then
				p.input:focus()
			end
		end
	end
end

-- ── view: "years" — Material year grid ──
local function draw_years_view(p, m)
	local ctx, T = p.ctx, p.ctx.theme
	local lh, PAD, W_ = m.LH, m.PAD, m.W
	p:draw_header(I.t("Clock"), Util.keybind_hint(ctx, "toggle_clock"), PAD)
	local y = m.HEAD_H + 14
	-- year line (active in this view; click returns to the calendar)
	local ys = tostring(view_year)
	local yw = select(1, ctx.get_text_size(ys))
	p:text(PAD, y, ys, T.primary)
	M.year_rect = { x = PAD - 4, y = y - 3, w = yw + 12, h = lh + 6 }
	y = y + lh + 4
	-- selected date line
	local sel_d = sel_ymd()
	local wsel = os.time({ year = sel_d.y, month = sel_d.mo, day = sel_d.d, hour = 12 })
	p:text(PAD, y,
		I.t("%s %s %d", I.t(os.date("%a", wsel)), I.t(os.date("%b", wsel)), sel_d.d),
		T.on_surface)
	y = y + lh + 14 + 10
	-- 5x5 grid, +/-12 years around the viewed year
	local gw = math.floor((W_ - PAD * 2) / 5)
	local gh = lh + 26
	M.year_rects = {}
	for i = 0, 24 do
		local yr = view_year - 12 + i
		local gx = PAD + (i % 5) * gw
		local gy = y + math.floor(i / 5) * gh
		local s = tostring(yr)
		local tw = select(1, ctx.get_text_size(s))
		if yr == view_year then
			p:rrect(gx + 6, gy + 3, gw - 12, gh - 6, math.floor((gh - 6) / 2), T.surface_hi)
		end
		p:text(gx + math.floor((gw - tw) / 2), gy + math.floor((gh - lh) / 2), s,
			(yr == view_year) and T.primary or T.on_surface)
		M.year_rects[#M.year_rects + 1] = { x = gx, y = gy, w = gw, h = gh, yr = yr }
	end
end

local function draw_panel(p)
	local ctx = p.ctx
	local T = ctx.theme
	local m = p.m
	local ui = p.ui
	-- self-heal: model follows the live surface size (user resize) so the
	-- view bottom, footer and schedule rows always match the real panel
	m.W, m.H = p.w, p.h
	if M.view == "time" then
		draw_time_view(p, m)
		return
	elseif M.view == "years" then
		draw_years_view(p, m)
		return
	end
	local W_, lh, PAD = m.W, m.LH, m.PAD
	-- reactive: calendar columns spread across the full live width
	local COL_W = math.floor((W_ - PAD * 2) / 7)
	-- footer reserves room for the auto-fit description input (grows with
	-- wrapped rows; Panel:tick flags the re-fit when the height changes)
	local base_in = m.BASE_IN
	local in_h = (p.input and p.input:height()) or base_in
	local foot_h = (M.adding and m.FOOT_ADD or m.FOOT_H)
		+ (M.adding and math.max(0, in_h - base_in) or 0)

	local time_str = os.date("%H:%M:%S")
	local date_str = I.t(os.date("%a")) .. ", " .. I.t(os.date("%b")) .. " " .. os.date("%d")
	p:draw_header(I.t("Clock"), Util.keybind_hint(ctx, "toggle_clock"), PAD)
	local ty = m.HEAD_H + 10
	local tw = select(1, ctx.get_text_size(time_str))
	p:text(math.floor((W_ - tw) / 2), ty, time_str, T.primary)
	local dw = select(1, ctx.get_text_size(date_str))
	p:text(math.floor((W_ - dw) / 2), ty + lh + 6, date_str, T.on_var)

	local y = ty + lh + 6 + lh + 14
	p:rect(PAD, y, W_ - PAD * 2, 1, T.outline)
	y = y + 12

	-- picker header: small year (click → years view) + viewed month
	local ys = tostring(view_year)
	local yw = select(1, ctx.get_text_size(ys))
	p:text(PAD, y, ys, T.hint)
	M.year_rect = { x = PAD - 4, y = y - 3, w = yw + 12, h = lh + 6 }
	p:text(PAD + yw + 10, y,
		I.t(os.date("%b", os.time({ year = view_year, month = view_month, day = 1, hour = 12 }))),
		T.hint)
	y = y + lh + 4

	-- selected date (big) with the month nav on the right
	local sel_d = sel_ymd()
	local wsel = os.time({ year = sel_d.y, month = sel_d.mo, day = sel_d.d, hour = 12 })
	p:text(PAD, y,
		I.t("%s %s %d", I.t(os.date("%a", wsel)), I.t(os.date("%b", wsel)), sel_d.d),
		T.on_surface)
	if ui then
		if ui:id_button("cal_prev", W_ - PAD - 28 - 8 - 28, y - 5, 28, lh + 10, "<", { tonal = true }) then
			view_month = view_month - 1
			if view_month < 1 then
				view_month, view_year = 12, view_year - 1
			end
			M.need_fit = true -- calendar row count may change
		end
		if ui:id_button("cal_next", W_ - PAD - 28, y - 5, 28, lh + 10, ">", { tonal = true }) then
			view_month = view_month + 1
			if view_month > 12 then
				view_month, view_year = 1, view_year + 1
			end
			M.need_fit = true
		end
	end
	y = y + lh + 14

	local cols = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
	for i, c in ipairs(cols) do
		local label = I.t(c)
		local cx = PAD + (i - 1) * COL_W
		local cw = select(1, ctx.get_text_size(label))
		p:text(cx + math.floor((COL_W - cw) / 2), y, label, T.hint)
	end
	y = y + lh + 10

	local dim = days_in_month(view_year, view_month)
	local fwd = first_wday(view_year, view_month)
	local row_h = m.ROW_H
	M.day_rects = {}
	local sz = lh + 14

	for row = 0, cal_rows_needed(view_year, view_month) - 1 do
		for col = 0, 6 do
			local day = row * 7 + col - fwd + 1
			if day >= 1 and day <= dim then
				local cx = PAD + col * COL_W
				local cy = y + row * row_h
				local day_str = tostring(day)
				local dw_ = select(1, ctx.get_text_size(day_str))
				local tx = cx + math.floor((COL_W - dw_) / 2)
				local is_today = day == today.day and view_month == today.month
					and view_year == today.year
				local is_sel = M.sel and M.sel.y == view_year
					and M.sel.mo == view_month and M.sel.d == day
				if is_today then
					p:rrect(
						cx + math.floor((COL_W - sz) / 2),
						cy - 7,
						sz, sz, math.floor(sz / 2), T.primary
					)
					p:text(tx, cy, day_str, T.on_primary)
				else
					-- selected day gets a soft highlight chip
					if is_sel then
						p:rrect(
							cx + math.floor((COL_W - sz) / 2),
							cy - 7,
							sz, sz, 10, T.surface_hi
						)
					end
					-- days that carry a pending schedule get a marker dot
					local has_sched = false
					for _, e in ipairs(entries) do
						if e.d == day and e.mo == view_month and e.y == view_year
							and not fired[entry_key(e)] then
							has_sched = true
							break
						end
					end
					p:text(tx, cy, day_str,
						is_sel and T.primary or (col == 0 or col == 6) and T.on_var or T.on_surface)
					if has_sched then
						p:rrect(cx + math.floor(COL_W / 2) - 2, cy + lh + 3, 4, 4, 2, T.primary)
					end
				end
				-- click target for the schedule date picker
				M.day_rects[#M.day_rects + 1] =
					{ x = cx, y = cy - 7, w = COL_W, h = sz, yr = view_year, mo = view_month, d = day }
			end
		end
	end

	-- ── schedule section ──
	y = y + row_h * cal_rows_needed(view_year, view_month) + 16
	p:rect(PAD, y, W_ - PAD * 2, 1, T.outline)
	y = y + 12

	local add_w = 48
	p:text(PAD, y, I.t("schedule"), T.hint)
	-- discoverability hint (hidden when it would collide with the add button)
	local edit_hint = I.t("click a schedule to edit")
	local hx = PAD + select(1, ctx.get_text_size(I.t("schedule"))) + 14
	local hw = select(1, ctx.get_text_size(edit_hint))
	if hx + hw <= W_ - PAD - add_w - 12 then
		p:text(hx, y, edit_hint, T.hint)
	end
	if ui then
		if ui:id_button("sched_add", W_ - PAD - add_w, y - 5, add_w, lh + 10,
			I.t("add"), { tonal = true }) and not M.adding then
			start_add(p)
		end
	end
	y = y + lh + 10

	-- clamp visible schedule rows to the space above the footer (reflow on resize)
	local row_gap = m.SCHED_GAP
	local sched_max = math.min(SCHEDULE_MAX,
		math.max(1, math.floor((m.H - foot_h - 14 - y) / row_gap)))
	local shown = 0
	M.row_rects = {} -- row click targets for editing (rebuilt every draw frame)
	for i, e in ipairs(entries) do
		if shown >= sched_max then
			break
		end
		local h, mi = entry_hm(e)
		local when = string.format("%02d-%02d %02d:%02d", e.mo, e.d, h, mi)
		local done = fired[entry_key(e)] == true
		local tcol = done and T.hint or T.primary
		local vcol = done and T.hint or T.on_surface
		p:text(PAD, y, when, tcol)
		-- text starts right after the measured time label (no fixed offset)
		local when_w = select(1, ctx.get_text_size(when))
		local tx = PAD + when_w + 12
		local avail = W_ - PAD - 56 - tx
		p:text(tx, y, Util.utf8_truncate(e.txt, math.max(4, math.floor(avail / 9))), vcol)
		-- pencil affordance; the row body itself is the edit click target
		p:text(W_ - PAD - 48, y, "✎", T.hint)
		-- click target = row body up to the delete button (no widget overlap)
		M.row_rects[#M.row_rects + 1] =
			{ x = PAD - 4, y = y - 6, w = W_ - PAD * 2 - 22, h = lh + 12, idx = i }
		if ui then
			if ui:id_button("sched_del:" .. i, W_ - PAD - 18, y - 4, 20, 20, "×",
				{ radius = 6, color = T.hint }) then
				M.del_idx = i -- remove in tick (never mutate mid-draw loop)
				break
			end
		end
		shown = shown + 1
		y = y + row_gap
	end
	if #entries == 0 then
		p:text(PAD, y, I.t("no schedule"), T.hint)
	elseif #entries > sched_max then
		local more = "+" .. (#entries - sched_max)
		p:text(W_ - PAD - select(1, ctx.get_text_size(more)), y, more, T.hint)
	end

	-- footer: date chip + time chip + description input while adding/editing
	local fy = m.H - foot_h
	p:rect(PAD, fy, W_ - PAD * 2, 1, T.outline)
	if M.adding and p.input then
		local ay = fy + 10
		local chip_h = m.CHIP_H
		-- picked date chip (display)
		local ds = sel_str()
		local dwid = select(1, ctx.get_text_size(ds)) + 24
		p:rrect(PAD, ay, dwid, chip_h, math.floor(chip_h / 2), T.surface_hi)
		p:text(PAD + 12, ay + 7, ds, T.primary)
		-- time chip opens the Material dial
		local ts = string.format("%02d:%02d", pick_h, pick_mi)
		local twid = select(1, ctx.get_text_size(ts)) + 24
		if ui and ui:id_button("pick_time", PAD + dwid + 8, ay, twid, chip_h, ts, { tonal = true }) then
			M.tp_back_h, M.tp_back_mi = pick_h, pick_mi
			M.tp_phase = "h"
			M.view = "time"
			M.need_fit = true
			p.input:blur()
		end
		local by = ay + chip_h + 10
		local iw = W_ - PAD * 2 - 122
		p.input:set_rect(PAD, by, iw, base_in)
		p.input:draw(p)
		if ui then
			if ui:id_button("add_cancel", PAD + iw + 8, by + 1, 44, lh + 8,
				"esc", { tonal = true }) then
				stop_add(p)
			end
			if ui:id_button("add_ok", PAD + iw + 58, by + 1, 56, lh + 8,
				M.edit_idx and I.t("update") or I.t("ok"), { filled = true }) then
				submit_add(p)
			end
		end
	end
end

function M.init(ctx)
	load_entries(ctx)
	M.del_idx = nil
	M.edit_idx = nil
	M.view = "form"
	P = Panel.new(ctx, {
		name = "clock",
		radius = 16,
		bg = ctx.theme.bg,
		size_fn = function(c) -- auto-fit to content
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = draw_panel,
		input = {
			placeholder = I.t("description"),
			max_bytes = 256,
			on_change = function() end,
			on_submit = function()
				if P then
					submit_add(P)
				end
			end,
			on_cancel = function()
				if P then
					stop_add(P)
				end
			end,
		},
		-- click targets (rects are rebuilt every draw frame): the time dial
		-- picks hour/minute, calendar days select the picker date, schedule
		-- rows open the pre-filled editor, the header year toggles years view
		on_press = function(p, mx, my, btn)
			if btn ~= 1 then
				return
			end
			if M.view == "time" then
				local rects = (M.tp_phase == "h") and M.hour_rects or M.min_rects
				for _, r in ipairs(rects or {}) do
					if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
						dial_pick(mx, my, r)
						return
					end
				end
				return
			end
			local yr = M.year_rect
			if yr and mx >= yr.x and mx < yr.x + yr.w and my >= yr.y and my < yr.y + yr.h then
				M.view = (M.view == "years") and "form" or "years"
				M.need_fit = true
				return
			end
			for _, r in ipairs(M.year_rects or {}) do
				if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
					view_year = r.yr
					M.view = "form"
					M.need_fit = true -- calendar row count may change
					return
				end
			end
			if M.view ~= "form" then
				return
			end
			for _, r in ipairs(M.day_rects or {}) do
				if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
					M.sel = { y = r.yr, mo = r.mo, d = r.d }
					return
				end
			end
			for _, r in ipairs(M.row_rects or {}) do
				if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
					start_edit(p, r.idx)
					return
				end
			end
		end,
		on_show = function(p)
			stop_add(p)
		end,
	})
	if P then
		P.m = build_model(ctx)
	end
	ctx.register_panel("clock", P)
end

function M.width(ctx)
	return select(1, ctx.get_text_size(str)) + 20
end

function M.tick(ctx, dt)
	-- deferred auto-fit after add/delete/month-nav/add-toggle
	if M.need_fit then
		M.need_fit = false
		if P then
			P:fit()
		end
	end
	local now = os.time()
	if now ~= last_sec then
		last_sec = now
		today = os.date("*t") -- keep "today" fresh across midnight
		str = os.date("%H:%M")
		ctx.bar.needs_redraw = true

		-- fire due alarms (once per entry)
		local due = nil
		for _, e in ipairs(entries) do
			local k = entry_key(e)
			if not fired[k] and entry_epoch(e) <= now then
				fired[k] = true
				due = due or {}
				due[#due + 1] = e
			end
		end
		if due then
			for _, e in ipairs(due) do
				local h, mi = entry_hm(e)
				ctx.notify(I.t("alarm: %s", string.format("%02d:%02d %s", h, mi, e.txt)),
					{ style = "warning", duration = 15000 })
			end
			if P and P.visible then
				P:draw()
			end
		end

		-- deferred row deletion (requested from draw)
		if M.del_idx then
			if M.edit_idx then
				if M.edit_idx == M.del_idx then
					M.edit_idx = nil
					if P then
						stop_add(P) -- the form referred to the removed row
					end
				elseif M.edit_idx > M.del_idx then
					M.edit_idx = M.edit_idx - 1
				end
			end
			table.remove(entries, M.del_idx)
			M.del_idx = nil
			save_entries(ctx)
			if P then
				P:fit() -- auto-fit to entry count
			end
			if P and P.visible then
				P:draw()
			end
		end

		if P and P.visible then
			P:draw()
		end
	end
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	s:text(x + 8, math.floor((h - lh) / 2), str, ctx.theme.fg)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn ~= 1 then
		return
	end
	local t = os.date("*t")
	view_year, view_month = t.year, t.month
	local direction = (ctx.config.position == "top") and "below" or "above"
	local anchor_y = (ctx.config.position == "top") and ctx.bar.h or (ctx.scr_h - ctx.bar.h)
	ctx.show_panel("clock", gx + gw / 2, anchor_y, direction)
end

function M.shutdown() end

return M
