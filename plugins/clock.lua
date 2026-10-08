-- plugins/clock.lua — clock + calendar panel with schedule/alarms.
-- Scheduling uses a picker: click a calendar day to select the date,
-- then add → footer shows date + hour/minute steppers + a description
-- input (legacy "YYYY-MM-DD HH:MM text" parsing is kept for offline
-- tests). Entries persist to clock.schedule_file; due entries fire a
-- one-shot warning toast. Layout auto-fits content (calendar rows,
-- schedule rows, add-strip) and reflows on user resize.
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
M.sel = nil -- picked calendar day { y, mo, d } used by the add picker
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
	m.PAD = 20
	m.COL_W = lh + 26
	m.W = m.PAD * 2 + m.COL_W * 7
	m.HEAD_H = lh + 26
	m.ROW_H = lh + 10
	m.FOOT_H = lh + 30
	m.FOOT_ADD = lh * 2 + 34 -- picker row + input row while adding
	local rows = cal_rows_needed(view_year, view_month)
	local n = math.max(1, math.min(#entries, SCHEDULE_MAX))
	m.H = m.HEAD_H
		+ (lh + 6) + (lh + 4) + 12 + 1 + 10 -- time + date + divider
		+ (lh + 8) + (lh + 8) -- month + weekday rows
		+ m.ROW_H * rows -- calendar (actual row count)
		+ 12 + 1 + 10 + (lh + 8) -- divider + schedule header
		+ (lh + 6) * n + 10 -- schedule rows (>= 1 for empty state)
		+ (M.adding and m.FOOT_ADD or m.FOOT_H)
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

local function stop_add(p)
	M.adding = false
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
	local sel = sel_ymd()
	local e = { y = sel.y, mo = sel.mo, d = sel.d, mi = pick_h * 60 + pick_mi, txt = txt }
	local is_today_sel = sel.y == today.year and sel.mo == today.month and sel.d == today.day
	if entry_epoch(e) <= os.time() then
		if not is_today_sel then
			ctx.notify(I.t("time already past"), { style = "error" })
			return
		end
		-- defaulted to today but the time slipped by: roll to tomorrow
		local tom = os.date("*t", os.time({ year = e.y, month = e.mo, day = e.d, hour = 12 }) + 86400)
		e.y, e.mo, e.d = tom.year, tom.month, tom.day
	end
	add_entry(ctx, e)
	stop_add(p)
	p:draw()
end

local function draw_panel(p)
	local ctx = p.ctx
	local T = ctx.theme
	local m = p.m
	local ui = p.ui
	-- self-heal: model follows the live surface size (user resize) so the
	-- view bottom, footer and schedule rows always match the real panel
	m.W, m.H = p.w, p.h
	local W_, lh, PAD = m.W, m.LH, m.PAD
	-- reactive: calendar columns spread across the full live width
	local COL_W = math.floor((W_ - PAD * 2) / 7)
	local foot_h = M.adding and m.FOOT_ADD or m.FOOT_H

	local time_str = os.date("%H:%M:%S")
	local date_str = I.t(os.date("%a")) .. ", " .. I.t(os.date("%b")) .. " " .. os.date("%d")
	p:draw_header(I.t("Clock"), Util.keybind_hint(ctx, "toggle_clock"), PAD)
	local ty = m.HEAD_H + 6
	local tw = select(1, ctx.get_text_size(time_str))
	p:text(math.floor((W_ - tw) / 2), ty, time_str, T.primary)
	local dw = select(1, ctx.get_text_size(date_str))
	p:text(math.floor((W_ - dw) / 2), ty + lh + 4, date_str, T.on_var)

	local y = ty + lh + 4 + lh + 12
	p:rect(PAD, y, W_ - PAD * 2, 1, T.outline)
	y = y + 10

	-- month row with prev/next navigation
	local month_str = I.t("%d-%02d", view_year, view_month)
	local mw = select(1, ctx.get_text_size(month_str))
	p:text(math.floor((W_ - mw) / 2), y, month_str, T.on_surface)
	if ui then
		if ui:id_button("cal_prev", PAD, y - 4, 26, lh + 8, "<", { tonal = true }) then
			view_month = view_month - 1
			if view_month < 1 then
				view_month, view_year = 12, view_year - 1
			end
			M.need_fit = true -- calendar row count may change
		end
		if ui:id_button("cal_next", W_ - PAD - 26, y - 4, 26, lh + 8, ">", { tonal = true }) then
			view_month = view_month + 1
			if view_month > 12 then
				view_month, view_year = 1, view_year + 1
			end
			M.need_fit = true
		end
	end
	y = y + lh + 8

	local cols = { "Su", "Mo", "Tu", "We", "Th", "Fr", "Sa" }
	for i, c in ipairs(cols) do
		local label = I.t(c)
		local cx = PAD + (i - 1) * COL_W
		local cw = select(1, ctx.get_text_size(label))
		p:text(cx + math.floor((COL_W - cw) / 2), y, label, T.hint)
	end
	y = y + lh + 8

	local dim = days_in_month(view_year, view_month)
	local fwd = first_wday(view_year, view_month)
	local row_h = m.ROW_H
	M.day_rects = {}
	local sz = lh + 10

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
					local pad = 5
					p:rrect(
						cx + math.floor((COL_W - sz) / 2),
						cy - pad + 2,
						sz, sz, math.floor(sz / 2), T.primary
					)
					p:text(tx, cy, day_str, T.on_primary)
				else
					-- selected day gets a soft highlight chip
					if is_sel then
						p:rrect(
							cx + math.floor((COL_W - sz) / 2),
							cy - 2,
							sz, sz, 8, T.surface_hi
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
						p:rrect(cx + math.floor(COL_W / 2) - 2, cy + lh + 1, 4, 4, 2, T.primary)
					end
				end
				-- click target for the schedule date picker
				M.day_rects[#M.day_rects + 1] =
					{ x = cx, y = cy - 3, w = COL_W, h = lh + 6, yr = view_year, mo = view_month, d = day }
			end
		end
	end

	-- ── schedule section ──
	y = y + row_h * cal_rows_needed(view_year, view_month) + 12
	p:rect(PAD, y, W_ - PAD * 2, 1, T.outline)
	y = y + 10

	p:text(PAD, y, I.t("schedule"), T.hint)
	if ui then
		local add_w = 44
		if ui:id_button("sched_add", W_ - PAD - add_w, y - 4, add_w, lh + 8,
			I.t("add"), { tonal = true }) and not M.adding then
			start_add(p)
		end
	end
	y = y + lh + 8

	-- clamp visible schedule rows to the space above the footer (reflow on resize)
	local row_gap = lh + 6
	local sched_max = math.min(SCHEDULE_MAX,
		math.max(1, math.floor((m.H - foot_h - 12 - y) / row_gap)))
	local shown = 0
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
		local avail = W_ - PAD - 26 - tx
		p:text(tx, y, Util.utf8_truncate(e.txt, math.max(4, math.floor(avail / 9))), vcol)
		if ui then
			if ui:id_button("sched_del:" .. i, W_ - PAD - 18, y - 3, 18, 18, "×",
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

	-- footer: date + time picker and description input while adding
	local fy = m.H - foot_h
	p:rect(PAD, fy, W_ - PAD * 2, 1, T.outline)
	if M.adding and p.input then
		local ay = fy + 8
		p:text(PAD, ay + 2, sel_str(), T.primary)
		local bx = PAD + 118
		local function stepper(dec_id, inc_id, x, val, wrap_dec, wrap_inc)
			if ui and ui:id_button(dec_id, x, ay - 2, 24, lh + 6, "-", { tonal = true }) then
				val = wrap_dec
			end
			local vs = string.format("%02d", val)
			local vw = select(1, ctx.get_text_size(vs))
			p:text(x + 24 + math.floor((30 - vw) / 2), ay, vs, T.on_surface)
			if ui and ui:id_button(inc_id, x + 54, ay - 2, 24, lh + 6, "+", { tonal = true }) then
				val = wrap_inc
			end
			return val
		end
		pick_h = stepper("h_dec", "h_inc", bx, pick_h,
			(pick_h - 1) % 24, (pick_h + 1) % 24)
		p:text(bx + 78 + 4, ay, ":", T.hint)
		pick_mi = stepper("m_dec", "m_inc", bx + 90, pick_mi,
			(pick_mi - 5) % 60, (pick_mi + 5) % 60)

		local by = ay + lh + 10
		local iw = W_ - PAD * 2 - 110
		p.input:set_rect(PAD, by, iw, lh + 8)
		p.input:draw(p)
		if ui then
			if ui:id_button("add_cancel", PAD + iw + 8, by + 1, 44, lh + 6,
				"esc", { tonal = true }) then
				stop_add(p)
			end
			if ui:id_button("add_ok", PAD + iw + 58, by + 1, 44, lh + 6,
				I.t("ok"), { filled = true }) then
				submit_add(p)
			end
		end
	end
end

function M.init(ctx)
	load_entries(ctx)
	M.del_idx = nil
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
		-- calendar day click targets (rects are rebuilt every draw frame)
		on_press = function(p, mx, my, btn)
			if btn ~= 1 or not M.day_rects then
				return
			end
			for _, r in ipairs(M.day_rects) do
				if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
					M.sel = { y = r.yr, mo = r.mo, d = r.d }
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
