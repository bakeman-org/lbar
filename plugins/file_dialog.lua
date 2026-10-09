-- plugins/file_dialog.lua — file/folder picker; backend chain zenity →
-- pcmanfm → built-in panel. External pickers run as async background
-- subshells writing /tmp tmpfiles plus DONE markers harvested in tick, so
-- the main loop never blocks. No bar item: the panel is lazily created on
-- the first M.open call and doubles as the tick host (the main loop only
-- ticks registered panels). The built-in panel mimics the zenity file
-- selector: editable location bar on top, flat scrollable list (folders
-- first, thin separators), right-aligned Cancel/OK footer. Panel rows:
-- first click selects, clicking the selected row activates it (open dir /
-- confirm selection); keyboard: up/down selection, enter activates, esc
-- closes.
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("file_dialog")
local XK_ESCAPE = 0xff1b
local XK_UP = 0xff52
local XK_DOWN = 0xff54
local XK_RETURN = 0xff0d
local XK_KP_ENTER = 0xff8d

local P = nil -- lazy panel, created on first open

local st = {
	title = "",
	kind = "any",
	on_select = nil,
	dir = "/",
	entries = nil, -- nil = listing in flight
	sel = 1, -- keyboard/mouse row selection (1-based into entries)
	scroll = 0,
	want_sel = nil, -- entry name to preselect once the listing lands
}
M.need_fit = false
M.rects = nil -- entry click targets, rebuilt each draw frame
local job = nil -- /tmp path of the in-flight ls job
local pending_pick = nil -- path picked from draw; applied in M.tick
local pending_ok = nil -- OK pressed in draw; applied in M.tick
local zen_cache = nil -- zenity availability, checked once
local zen_job = nil -- /tmp base of the in-flight zenity job
local pcm_bin = nil -- pcmanfm binary present, checked once
local pcm_pick = nil -- pcmanfm stdout pick capability, probed once
M._zenity = nil -- test override: true/false forces availability
M._zen_cmd = nil -- test override: binary used in place of zenity
M._spawn = nil -- test override: spawn fn for the zenity job
M._pcmanfm = nil -- test override: true/false forces pcmanfm capability

local function shq(s)
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- zenity preferred: mature external dialog tool; built-in panel is the
-- fallback (checked once and cached; M._zenity forces it in tests)
local function have_zenity()
	if M._zenity ~= nil then
		return M._zenity
	end
	if zen_cache == nil then
		local r = os.execute("command -v zenity >/dev/null 2>&1")
		zen_cache = (r == true or r == 0)
	end
	return zen_cache
end

-- pcmanfm second choice. The binary may exist, but mainstream pcmanfm
-- (1.x, including this machine's build) has no --pick/--choose style mode
-- that writes the chosen path to stdout — its picker only returns the
-- selection to its own GUI. Probe the help text once (~16 ms, cached) for
-- such a flag; without it we fast-fail to the built-in panel and log the
-- reason instead of guessing an argv contract.
local function have_pcmanfm()
	if M._pcmanfm ~= nil then
		return M._pcmanfm
	end
	if pcm_bin == nil then
		local r = os.execute("command -v pcmanfm >/dev/null 2>&1")
		pcm_bin = (r == true or r == 0)
	end
	if pcm_pick == nil then
		pcm_pick = false
		if pcm_bin then
			local r = os.execute("pcmanfm --help 2>&1 | grep -qE -- '--pick|--choose'")
			pcm_pick = (r == true or r == 0)
		end
		if not pcm_pick then
			log("pcmanfm: no stdout pick mode%s, using built-in dialog",
				pcm_bin and "" or " (not installed)")
		end
	end
	return pcm_pick
end

-- async zenity run: background subshell writes the picked path to a /tmp
-- tmpfile plus a DONE marker holding the exit code; M.tick harvests so the
-- main loop never blocks
local function zen_start(kind, title, path)
	local base = string.format("/tmp/lbar-zenity-%d-%d", os.time(), math.random(10000))
	os.remove(base)
	os.remove(base .. ".done")
	local args = { (M._zen_cmd or "zenity") .. " --file-selection" }
	if kind == "dir" then
		args[#args + 1] = "--directory"
	end
	if title and title ~= "" then
		args[#args + 1] = "--title " .. shq(title)
	end
	if path and path ~= "" then
		args[#args + 1] = "--filename " .. shq(path)
	end
	local cmd = string.format("( %s > %s 2>/dev/null; echo $? > %s.done ) &",
		table.concat(args, " "), shq(base), shq(base))
	local spawn = M._spawn or os.execute
	spawn(cmd)
	zen_job = base
end

local function strip_slash(p)
	p = tostring(p or "")
	while #p > 1 and p:sub(-1) == "/" do
		p = p:sub(1, -2)
	end
	return p
end

local function parent_dir(p)
	p = strip_slash(p)
	if p == "/" then
		return nil -- at root: no parent, hide the up button
	end
	local d = p:match("^(.+)/[^/]+$")
	if d == nil or d == "" then
		return "/" -- top-level dir ("/tmp") still has a parent
	end
	return d
end

-- "file" | "dir" | "missing": classify via `test -d` — LuaJIT's f:read(0)
-- returns nil even for regular files, so it cannot tell files from dirs
local function probe(p)
	local r = os.execute("test -d " .. shq(p))
	if r == true or r == 0 then
		return "dir"
	end
	local f = io.open(p, "r")
	if not f then
		return "missing"
	end
	f:close()
	return "file"
end

-- rough char budget for a pixel width (paths are mostly ASCII)
local function fit_chars(ctx, avail)
	local cw = select(1, ctx.get_text_size("n"))
	return math.max(2, math.floor(avail / math.max(4, cw)))
end

-- async listing: `ls -p` gives dirs a trailing "/" and skips hidden files
-- (a hidden-file variant would add -A for an "almost all" toggle)
local function start_list(dir)
	st.dir = dir
	st.entries = nil
	st.scroll = 0
	st.sel = 1
	if P and P.input then
		P.input:set_value(dir) -- location bar tracks the current directory
	end
	job = string.format("/tmp/lbar-fdialog-%d-%d", os.time(), math.random(10000))
	os.remove(job) -- stale leftovers from a same-second relaunch
	os.remove(job .. ".done")
	os.execute(string.format("( ls -p %s > %s 2>/dev/null; echo 1 > %s.done ) &",
		shq(dir), shq(job), shq(job)))
end

local function pick(p, path)
	if path == nil or path == "" then
		return
	end
	local cb = st.on_select
	p:hide(true)
	if cb then
		local ok, err = pcall(cb, strip_slash(path))
		if not ok then
			log("on_select error: %s", tostring(err))
		end
	end
end

local function row_click(p, idx)
	local e = st.entries and st.entries[idx]
	if not e then
		return
	end
	-- GTK style: first click selects, clicking the already-selected row
	-- activates it (open dir / confirm selection); two quick presses =
	-- select + activate with no timing logic
	local activate = st.sel == idx
	st.sel = idx -- mouse and keyboard share one selection
	if not activate then
		p:draw()
		return
	end
	local full = (st.dir == "/" and "/" or st.dir .. "/") .. e.name
	if e.dir then
		start_list(full) -- activate opens the folder
	else
		pick(p, full) -- activate confirms the file
	end
end

-- OK in the footer (GTK semantics): file → confirm; folder → open, except
-- folder mode where it confirms the folder; nothing selected in folder
-- mode confirms the current directory
local function apply_ok(p)
	local e = st.entries and st.sel and st.entries[st.sel]
	if e then
		local full = (st.dir == "/" and "/" or st.dir .. "/") .. e.name
		if not e.dir or st.kind == "dir" then
			pick(p, full)
		else
			start_list(full)
		end
	elseif st.kind == "dir" then
		pick(p, st.dir)
	end
end

local function list_rows()
	return st.entries and math.max(1, math.min(#st.entries, 10)) or 1
end

-- shared list geometry: y offset, height, visible row count
local function list_geo(p)
	local m = p.m
	-- a wrapped location path pushes the list start down; the panel grows
	-- to match via Panel:fit, so the visible row count stays stable
	local ex = p.input and p.input:extra_h() or 0
	local ly = m.HEAD_H + m.GAP + m.LOC_H + m.GAP + ex
	local list_h = math.max(m.ROW_H, p.h - m.FOOT_H - m.GAP - ly)
	return ly, list_h, math.max(1, math.floor(list_h / m.ROW_H))
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		PAD = 20,
		GAP = 10,
		HEAD_H = lh + 26,
		LOC_H = lh + 14,
		ROW_H = lh + 12,
		FOOT_H = lh + 24,
	}
	m.W = 560
	m.LOC_Y = m.HEAD_H + m.GAP
	m.LIST_Y = m.LOC_Y + m.LOC_H + m.GAP
	m.H = m.LIST_Y + list_rows() * m.ROW_H + m.GAP + m.FOOT_H
	if user_size then
		m.W = math.max(420, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	-- self-heal on resize: re-derive all layout from the live surface
	m.W, m.H = p.w, p.h
	local lh, PAD, GAP, W = m.LH, m.PAD, m.GAP, m.W

	p:draw_header(st.title or I.t("open file"), nil, PAD)

	-- location row: ".." up button + editable path of the current
	-- directory (zenity-style location bar)
	m.LOC_Y = m.HEAD_H + GAP
	local loc_y = m.LOC_Y
	local up_w = 36
	if ui and parent_dir(st.dir) then
		if ui:id_button("fd_up", PAD, loc_y, up_w, m.LOC_H, "..",
			{ tonal = true, radius = 8 }) then
			start_list(parent_dir(st.dir))
		end
	end
	if p.input then
		p.input:set_rect(PAD + up_w + 8, loc_y, W - PAD * 2 - up_w - 8, m.LOC_H)
		p.input:draw(p)
	end

	-- flat scrollable entry list, zenity style: full-width rows, folders
	-- first (folder glyph + primary tint), thin separators between rows
	m.LIST_Y = m.LOC_Y + m.LOC_H + GAP
	local row_h = m.ROW_H
	local ly, list_h, max_rows = list_geo(p)
	local rx, rw = PAD, W - PAD * 2
	local n = st.entries and #st.entries or 0
	-- clamp only; keeping a moving keyboard selection in view is the
	-- on_key handler's job (a fixed sel=1 must not snap scroll back to 0)
	st.scroll = math.max(0, math.min(st.scroll, math.max(0, n - max_rows)))
	M.rects = {}
	local shown = 0
	if not st.entries then
		p:text(rx, ly + 4, I.t("scanning…"), T.hint)
	elseif n == 0 then
		p:text(rx, ly + 4, I.t("empty folder"), T.hint)
	else
		local gy = rx + 12 -- glyph column
		local tx = rx + 38 -- name column
		for i = st.scroll + 1, n do
			if shown >= max_rows then
				break
			end
			local e = st.entries[i]
			local ry = ly + shown * row_h
			local cy = ry + math.floor(row_h / 2)
			local sel = st.sel == i
			if (shown > 0 or st.scroll > 0) and not sel then
				p:rect(rx, ry, rw, 1, T.outline) -- hairline above the row
			end
			local row_bg = (sel and T.surface_hi)
				or (ui:hover(rx, ry, rw, row_h) and T.surface_hover)
				or nil
			if row_bg then
				p:rect(rx, ry, rw, row_h, row_bg) -- flat band, no chip
			end
			if e.dir then
				-- folder glyph: tab + rounded body
				p:rect(gy + 2, cy - 6, 9, 3, T.primary)
				p:rrect(gy + 2, cy - 4, 18, 11, 3, T.primary)
			else
				-- file glyph: rounded page with two text lines
				p:rrect(gy + 4, cy - 7, 14, 15, 2, T.on_var)
				local lc = row_bg or T.bg
				p:rect(gy + 7, cy - 2, 8, 2, lc)
				p:rect(gy + 7, cy + 2, 8, 2, lc)
			end
			p:text(tx, ry + math.floor((row_h - lh) / 2),
				Util.utf8_truncate(e.name, fit_chars(ctx, rx + rw - tx - 12)),
				e.dir and T.primary or T.on_var)
			M.rects[#M.rects + 1] = { x = rx, y = ry, w = rw, h = row_h, idx = i }
			shown = shown + 1
		end
		if n > max_rows then
			st.scroll = ui:scrollbar("fd_sb", W - 16, ly, 6, max_rows * row_h, st.scroll, n - max_rows)
		end
	end

	-- zenity footer: hairline + right-aligned cancel / ok
	local fy = m.H - m.FOOT_H
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local bh = lh + 12
	local by = fy + math.floor((m.H - fy - bh) / 2)
	local bw_c = math.max(72, select(1, ctx.get_text_size(I.t("cancel"))) + 28)
	local bw_o = math.max(72, select(1, ctx.get_text_size(I.t("ok"))) + 28)
	local ox = W - PAD - bw_o
	local cx = ox - 10 - bw_c
	if ui:id_button("fd_cancel", cx, by, bw_c, bh, I.t("cancel"), { tonal = true }) then
		p:hide()
	end
	if ui:id_button("fd_ok", ox, by, bw_o, bh, I.t("ok"), { filled = true }) then
		pending_ok = true -- applied in tick (never decide mid-draw)
	end
end

local function create_panel(ctx)
	local panel = Panel.new(ctx, {
		name = "file_dialog",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			return build_model(c, us)
		end,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = I.t("location"),
			max_bytes = 1024,
			on_change = function() end,
			on_submit = function(v)
				-- location bar: enter navigates to a directory, confirms a
				-- file; relative paths resolve against the current dir
				if not P then
					return
				end
				local path = strip_slash(v)
				if path == "" then
					return
				end
				if path:sub(1, 1) ~= "/" then
					path = st.dir == "/" and "/" .. path or st.dir .. "/" .. path
				end
				local k = probe(path)
				if k == "dir" then
					start_list(path)
				elseif k == "file" then
					pending_pick = path -- confirm via tick
				else
					log("no such path: %s", path)
				end
			end,
			on_cancel = function()
				if P then
					P:hide()
				end
			end,
		},
		on_key = function(p, sym)
			if sym == XK_ESCAPE then
				p:hide()
				return true
			end
			local n = st.entries and #st.entries or 0
			if n == 0 or not st.sel or st.sel < 1 then
				return false
			end
			if sym == XK_UP or sym == XK_DOWN then
				st.sel = math.max(1, math.min(n, st.sel + (sym == XK_UP and -1 or 1)))
				-- scroll just enough to keep the selection in view
				local _, _, max_rows = list_geo(p)
				if st.sel - 1 < st.scroll then
					st.scroll = st.sel - 1
				elseif st.sel > st.scroll + max_rows then
					st.scroll = st.sel - max_rows
				end
				return true
			end
			if (sym == XK_RETURN or sym == XK_KP_ENTER)
				and not (p.input and p.input.focused) then
				row_click(p, st.sel)
				return true
			end
			return false
		end,
		-- entry click targets are rebuilt every draw frame
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				st.scroll = st.scroll + (btn == 4 and -3 or 3)
				p:draw()
				return
			end
			if btn == 1 and M.rects then
				for _, r in ipairs(M.rects) do
					if mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
						row_click(p, r.idx)
						return
					end
				end
			end
		end,
	})
	if not panel then
		return nil
	end
	panel.m = build_model(ctx)
	-- no bar item: the main loop only ticks registered panels, so pump
	-- M.tick (zenity + ls harvest, deferred picks) from the panel's own
	-- tick; must run while hidden too — the zenity path never shows it
	local base_tick = panel.tick
	function panel:tick(dt, ...)
		base_tick(self, dt, ...)
		M.tick(self.ctx, dt)
	end
	return panel
end

-- M.open(ctx, { title, path, kind = "dir"|"file"|"any", on_select })
-- backend chain: zenity → pcmanfm → built-in panel. External pickers run
-- async; the built-in panel closes on ESC / cancel, and selection fires
-- on_select(path) (absolute, trailing "/" stripped) then hides the panel.
function M.open(ctx, opts)
	opts = opts or {}
	st.title = opts.title or I.t("open file")
	st.kind = opts.kind or "any"
	st.on_select = opts.on_select
	if not P then
		P = create_panel(ctx)
		if not P then
			log("panel create failed")
		else
			ctx.register_panel("file_dialog", P)
			log("ready")
		end
	end
	local start = strip_slash(opts.path)
	if start == "" then
		start = os.getenv("HOME") or "/"
	end
	-- 1st choice zenity: the lazy panel (created above) stays hidden and
	-- only serves as the tick host that harvests the async result
	if P and have_zenity() then
		if P.visible then
			P:hide(true)
		end
		zen_start(st.kind, st.title, start)
		return
	end
	-- 2nd choice pcmanfm: have_pcmanfm() probes once for a stdout pick
	-- mode and fast-fails (reason logged) — no mainstream build has one, so
	-- the chain always lands on the built-in panel for now
	have_pcmanfm()
	if not P then
		return
	end
	-- built-in panel: browse the file's folder (or the parent of a
	-- not-yet-existing path); the file itself is preselected once the
	-- listing lands (st.want_sel)
	st.want_sel = nil
	local browse = start
	if probe(start) ~= "dir" then
		st.want_sel = start:match("[^/]+$")
		browse = parent_dir(start) or "/"
	end
	st.scroll = 0
	st.sel = 1
	st.entries = nil
	if P.input then
		P.input:blur()
	end
	start_list(browse)
	-- route through ctx.show_panel: one visible panel at a time, and the
	-- dialog becomes active_panel so keys / pointer reach it
	ctx.show_panel("file_dialog")
end

-- poll the async listing; deferred picks / OK are applied here (never
-- hide the panel mid-draw from a footer button)
function M.tick(ctx, dt)
	if pending_pick then
		local path = pending_pick
		pending_pick = nil
		if P then
			pick(P, path)
		end
	end
	if pending_ok then
		pending_ok = nil
		if P then
			apply_ok(P)
		end
	end
	if M.need_fit then
		M.need_fit = false
		if P then
			P:fit()
		end
	end
	-- zenity harvest: exit 0 + non-empty output = picked; cancel (exit 1)
	-- does nothing; runs with no visible panel (the panel is just the
	-- tick host)
	if zen_job then
		local df = io.open(zen_job .. ".done", "r")
		if df then
			local rc = tonumber(df:read("*l")) or -1
			df:close()
			local spath
			local sf = io.open(zen_job, "r")
			if sf then
				local line = sf:read("*l")
				sf:close()
				if line and line ~= "" then
					spath = line
				end
			end
			os.remove(zen_job)
			os.remove(zen_job .. ".done")
			zen_job = nil
			if rc == 0 and spath and st.on_select then
				local ok, err = pcall(st.on_select, strip_slash(spath))
				if not ok then
					log("on_select error: %s", tostring(err))
				end
			end
		end
	end
	if not job or not P or not P.visible then
		return
	end
	local f = io.open(job .. ".done", "r")
	if not f then
		return
	end
	f:close()
	local out = io.open(job, "r")
	job = nil
	local entries = {}
	if out then
		for line in out:lines() do
			if line ~= "" then
				local is_dir = line:sub(-1) == "/"
				local name = is_dir and line:sub(1, -2) or line
				if name ~= "" then
					entries[#entries + 1] = { name = name, dir = is_dir }
				end
			end
		end
		out:close()
	end
	table.sort(entries, function(a, b)
		if a.dir ~= b.dir then
			return a.dir
		end
		return a.name:lower() < b.name:lower()
	end)
	st.entries = entries
	st.sel = 1 -- fresh listing: selection restarts at the first row
	st.scroll = 0
	if st.want_sel then
		local want = st.want_sel
		st.want_sel = nil
		for i, e in ipairs(entries) do
			if e.name == want then
				st.sel = i
				if P then
					local _, _, max_rows = list_geo(P)
					st.scroll = math.max(0, math.min(i - 1, math.max(0, #entries - max_rows)))
				end
				break
			end
		end
	end
	M.need_fit = true -- entry count may change the natural height
	if P then
		P:draw()
	end
end

-- offline test hooks
M._state = function()
	return st
end
M._rects = function()
	return M.rects
end

function M.shutdown()
	P = nil
	job = nil
	pending_pick = nil
	pending_ok = nil
	zen_job = nil
end

return M
