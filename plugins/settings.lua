-- plugins/settings.lua — settings panel: tabs for themes / options / panels
-- covers (almost) every config.lua key; edits persist in-place into config.lua
-- NOTE: destructive actions (hot reload / close) are deferred to M.tick —
-- running them from inside draw() destroys the panel mid-draw
local M = {}
local Panel = require("core.panel")
local Theme = require("core.theme")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("settings")
local XK_ESCAPE = 0xff1b

-- keys that need a hot reload to take effect (bar geometry / fonts)
local HOT_KEYS = {
	position = true,
	height = true,
	padding = true,
	gap = true,
	bar_margin = true,
	font_path = true,
	font_size = true,
	fallback_font_paths = true,
}

local function defer(fn)
	M.pending_action = fn
end

local function q(s)
	return "'" .. tostring(s):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

-- ---------------------------------------------------------------- config io

-- advance past comments / strings; returns index of next structural char
local function next_tok(text, i, n)
	while i <= n do
		local c = text:sub(i, i)
		if c == "-" and text:sub(i, i + 1) == "--" then
			if text:sub(i + 2, i + 3) == "[[" then
				local e = text:find("]]", i + 4, true)
				i = e and e + 2 or n + 1
			else
				local e = text:find("\n", i, true)
				i = e or n + 1
			end
		elseif c == "'" or c == '"' then
			local qch = c
			i = i + 1
			while i <= n do
				local b = text:sub(i, i)
				if b == "\\" then
					i = i + 2
				elseif b == qch then
					i = i + 1
					break
				else
					i = i + 1
				end
			end
		else
			return i
		end
	end
	return n + 1
end

-- locate scope body for path (e.g. {"panels","clock"} or {} = top level)
-- returns body_start, body_end (inside braces), close_idx (the '}')
local function find_scope(text, path)
	path = path or {}
	local n = #text
	local i = 1
	local depth = 0
	local assign_name = nil
	local stack = {}
	while i <= n do
		i = next_tok(text, i, n)
		if i > n then
			break
		end
		local c = text:sub(i, i)
		if c == "{" then
			depth = depth + 1
			if #stack == 0 and depth == 1 then
				stack[1] = { open = i, depth = 1 }
			elseif #stack < #path + 1 and depth == #stack + 1
				and assign_name == path[#stack] then
				stack[#stack + 1] = { open = i, depth = depth }
			end
			assign_name = nil
			i = i + 1
		elseif c == "}" then
			local st = stack[#stack]
			if st and st.depth == depth then
				stack[#stack] = nil
				if #stack == #path then
					return st.open + 1, i - 1, i
				end
			end
			depth = depth - 1
			assign_name = nil
			i = i + 1
		elseif c:match("[%w_]") then
			local j = i
			while j <= n and text:sub(j, j):match("[%w_]") do
				j = j + 1
			end
			local name = text:sub(i, j - 1)
			local k = next_tok(text, j, n)
			while k <= n and text:sub(k, k):match("%s") do
				k = k + 1
			end
			if k <= n and text:sub(k, k) == "=" and text:sub(k + 1, k + 1) ~= "=" then
				assign_name = name
			end
			i = j
		else
			i = i + 1
		end
	end
	return nil
end

-- brace delta of one line (skips strings and comments)
local function line_delta(line)
	local i, n = 1, #line
	local d = 0
	while i <= n do
		local c = line:sub(i, i)
		if c == "-" and line:sub(i, i + 1) == "--" then
			break
		elseif c == "'" or c == '"' then
			local qch = c
			i = i + 1
			while i <= n do
				local b = line:sub(i, i)
				if b == "\\" then
					i = i + 2
				elseif b == qch then
					i = i + 1
					break
				else
					i = i + 1
				end
			end
		elseif c == "{" then
			d = d + 1
			i = i + 1
		elseif c == "}" then
			d = d - 1
			i = i + 1
		else
			i = i + 1
		end
	end
	return d
end

-- find `key = value` inside [s,e] at relative depth 0
-- returns vstart, vend (value span), lstart, lend (full line span incl \n)
local function find_key_range(text, s, e, key)
	local kpat = "^%s*" .. key:gsub("%W", "%%%0") .. "%s*="
	local pos = s
	local depth = 0
	while pos <= e do
		local nl = text:find("\n", pos, true)
		local lend = nl and math.min(nl, e + 1) - 1 or e
		local line = text:sub(pos, lend)
		if depth == 0 and line:match(kpat) then
			local eq = line:find("=", 1, true)
			if eq then
				local vstart = pos + eq
				while text:sub(vstart, vstart) == " " or text:sub(vstart, vstart) == "\t" do
					vstart = vstart + 1
				end
				local i2, d2 = vstart, 0
				local vend
				while i2 <= e do
					local c = text:sub(i2, i2)
					if c == "'" or c == '"' then
						local qch = c
						i2 = i2 + 1
						while i2 <= e do
							local b = text:sub(i2, i2)
							if b == "\\" then
								i2 = i2 + 2
							elseif b == qch then
								i2 = i2 + 1
								break
							else
								i2 = i2 + 1
							end
						end
					elseif c == "-" and text:sub(i2, i2 + 1) == "--" then
						local nl2 = text:find("\n", i2, true)
						i2 = nl2 and nl2 or e + 1
					elseif c == "," and d2 == 0 then
						vend = i2 - 1
						break
					elseif c == "{" then
						d2 = d2 + 1
						i2 = i2 + 1
					elseif c == "}" then
						d2 = d2 - 1
						i2 = i2 + 1
					elseif c == "\n" and d2 == 0 then
						vend = i2 - 1
						break
					else
						i2 = i2 + 1
					end
				end
				if not vend or vend > e then
					vend = e
				end
				while vend > vstart and text:sub(vend, vend):match("%s") do
					vend = vend - 1
				end
				return vstart, vend, pos, nl or #text
			end
		end
		depth = depth + line_delta(line)
		pos = (nl or #text) + 1
		if nl and nl > e then
			break
		end
	end
	return nil
end

-- write one key inside config.lua; path = {} for top-level, {sec} or {a,b}...
local function save_value(path, key, lit, remove)
	path = path or {}
	local ctx = M.ctx
	local cfgpath = ctx.config_path or (ctx.SCRIPT_DIR .. "/config.lua")
	local f = io.open(cfgpath, "r")
	if not f then
		log("save %s failed: cannot read %s", key, cfgpath)
		return false
	end
	local text = f:read("*a")
	f:close()
	local s, ebody, eclose = find_scope(text, path)
	if not s then
		-- scope missing entirely: create it as a table in its parent
		if #path > 0 then
			local parent = {}
			for i = 1, #path - 1 do
				parent[i] = path[i]
			end
			return save_value(parent, path[#path], "{ " .. key .. " = " .. lit .. " }")
		end
		log("save %s: top-level scope not found", key)
		return false
	end
	local out
	local vstart, vend, lstart, lend = find_key_range(text, s, ebody, key)
	if remove then
		if not vstart then
			return true
		end
		local after = text:sub(lend, lend) == "\n" and lend + 1 or lend
		out = text:sub(1, lstart - 1) .. text:sub(after)
	elseif vstart then
		out = text:sub(1, vstart - 1) .. lit .. text:sub(vend + 1)
	else
		-- insert new key; handle single-line scope (`k = { v }`)
		local nl_in = text:find("\n", s, true)
		if nl_in and nl_in < eclose then
			local pre = text:sub(1, eclose - 1)
			local at = pre:match(".*\n()") or 1
			local indent = string.rep("    ", #path + 1)
			out = text:sub(1, at - 1) .. indent .. key .. " = " .. lit .. ",\n" .. text:sub(at)
		else
			local body = text:sub(s, ebody):match("^(.-)%s*$")
			local sep = body:match("%S") and ", " or " "
			out = text:sub(1, s - 1) .. body .. sep .. key .. " = " .. lit .. " " .. text:sub(ebody + 1)
		end
	end
	local fo = io.open(cfgpath, "w")
	if not fo then
		log("save %s failed: cannot write %s", key, cfgpath)
		return false
	end
	fo:write(out)
	fo:close()
	-- our own write must not trigger the auto-reload watcher
	ctx.skip_reload_once = true
	log("saved %s = %s", table.concat(path, ".") .. (next(path) and "." or "") .. key, lit or "nil")
	return true
end

-- set value in the live config tree, creating intermediate tables
local function cfg_set(path, key, val)
	local t = M.ctx.config
	for _, k in ipairs(path or {}) do
		if type(t[k]) ~= "table" then
			t[k] = {}
		end
		t = t[k]
	end
	if val == nil then
		t[key] = nil
	else
		t[key] = val
	end
end

local function cfg_get(path, key)
	local t = M.ctx.config
	for _, k in ipairs(path or {}) do
		if type(t) ~= "table" then
			return nil
		end
		t = t[k]
	end
	return type(t) == "table" and t[key] or nil
end

-- ------------------------------------------------------------------- theme

local function redraw_all()
	local ctx = M.ctx
	for _, p in pairs(ctx._panels or {}) do
		p.bg = ctx.theme.bg
		if p.visible and p ~= M.panel then
			p:draw()
		end
	end
	if M.panel then
		M.panel.bg = ctx.theme.bg
	end
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

local function apply_theme(name, mode)
	local ctx = M.ctx
	local cfg = ctx.config
	if mode == "light" then
		cfg.theme_light = name
	else
		cfg.theme = name
	end
	ctx.theme = Theme.build(cfg)
	redraw_all()
	ctx.notify(I.t("theme: %s", name), { style = "info" })
end

local function apply_mode(mode)
	local ctx = M.ctx
	ctx.config.theme_mode = mode
	ctx.theme = Theme.build(ctx.config)
	redraw_all()
	save_value({}, "theme_mode", "'" .. mode .. "'")
	ctx.notify(I.t("mode: %s", mode), { style = "info" })
end

-- -------------------------------------------------------------------- rows

local PALETTE_DARK, PALETTE_LIGHT = {}, {}
for name, pal in pairs(Theme.palettes) do
	if pal.dark then
		PALETTE_DARK[#PALETTE_DARK + 1] = name
	else
		PALETTE_LIGHT[#PALETTE_LIGHT + 1] = name
	end
end
table.sort(PALETTE_DARK)
table.sort(PALETTE_LIGHT)

local POS_CHOICES = { "center", "top", "top_left", "top_right", "bottom", "bottom_left", "bottom_right", "left", "right", "auto" }

-- MIUIX-style geometry: rounded card rows, unified side padding, small
-- hint-coloured group titles in their own band with wide group separation
local PAD, SB_W = 20, 6
local ROW_GAP = 8 -- gap between row cards
local CARD_R = 14 -- row card corner radius
local GROUP_GAP = 28 -- gap between a card and the next group title
local SW_W, SW_H = 46, 26 -- pill switch size

local function row_h(lh)
	return math.max(46, lh + 28)
end

local function group_h(lh)
	return lh + 8
end

-- widen the gap before a group header (rows already carry ROW_GAP)
local function group_gap(rows, y)
	if #rows > 0 then
		y = y + GROUP_GAP - ROW_GAP
	end
	return y
end

local function row_add(rows, y, lh, r)
	r.y = y
	r.h = r.h or row_h(lh)
	r.id = (r.kind or "edit") .. ":" .. table.concat(r.path or {}, ".") .. ":" .. (r.key or r.label or "")
	rows[#rows + 1] = r
	return y + r.h + ROW_GAP
end

local function build_rows(ctx, lh, W, tab)
	local rows = {}
	local y = 14 -- breathing room under the segmented tab control
	if tab == "themes" then
		local card_w = W - PAD * 2 - SB_W
		local CHIP_W = math.floor((card_w - 12) / 2)
		local chip_h = math.max(40, lh + 22)
		y = row_add(rows, y, lh, { kind = "mode", label = I.t("mode") })
		for _, grp in ipairs({ { I.t("dark themes"), PALETTE_DARK, "dark" }, { I.t("light themes"), PALETTE_LIGHT, "light" } }) do
			y = group_gap(rows, y)
			y = row_add(rows, y, lh, { kind = "group", label = grp[1], h = group_h(lh) })
			local col = 0
			local row_y = y
			for _, name in ipairs(grp[2]) do
				local cx = PAD + (col % 2) * (CHIP_W + 12)
				local cy = row_y + math.floor(col / 2) * (chip_h + 10)
				rows[#rows + 1] = {
					kind = "chip", name = name, mode = grp[3],
					x = cx, y = cy, h = chip_h, w = CHIP_W, id = "chip:" .. grp[3] .. ":" .. name,
				}
				y = math.max(y, cy + chip_h)
				col = col + 1
			end
			y = y + ROW_GAP
		end
	elseif tab == "panels" then
		y = row_add(rows, y, lh, { kind = "phdr", label = I.t("panels"), h = lh + 12 })
		local names = {}
		local seen = {}
		for _, src in ipairs({ ctx._panels or {}, ctx.config.panels or {}, ctx.config.panel_opts or {} }) do
			for k in pairs(src) do
				if not seen[k] then
					seen[k] = true
					names[#names + 1] = k
				end
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			y = row_add(rows, y, lh, { kind = "panel", pname = name, label = name })
		end
	else
		local function group(label)
			y = group_gap(rows, y)
			y = row_add(rows, y, lh, { kind = "group", label = label, h = group_h(lh) })
		end
		local function row(path, key, label, kind, extra)
			local r = { path = path, key = key, label = label, kind = kind or "str" }
			if extra then
				for k, v in pairs(extra) do
					r[k] = v
				end
			end
			y = row_add(rows, y, lh, r)
		end
		group(I.t("bar"))
		row({}, "position", I.t("position"), "enum", { choices = { "top", "bottom" } })
		row({}, "height", I.t("height"), "str")
		row({}, "padding", I.t("padding"), "num", { min = 0 })
		row({}, "gap", I.t("gap"), "num", { min = 0 })
		row({}, "bar_margin", I.t("bar margin"), "num", { min = 0 })
		group(I.t("style"))
		row({}, "corner", I.t("corner style"), "enum", { choices = { "round", "square" } })
		group(I.t("fonts"))
		row({}, "font_path", I.t("font path"), "str", { pick = "file" })
		row({}, "font_size", I.t("font size"), "num", { min = 10, max = 32 })
		row({}, "fallback_font_paths", I.t("fallback fonts (;)"), "list")
		group(I.t("paths"))
		row({}, "audio_panel_dir", I.t("music dir"), "str", { pick = "dir" })
		row({}, "music_state_file", I.t("music state file"), "str", { pick = "file" })
		row({ "clock" }, "schedule_file", I.t("schedule file"), "str", { pick = "file" })
		row({}, "lang", I.t("language"), "enum", { choices = { "auto", "en", "zh" } })
		group(I.t("cpu item"))
		row({ "cpu" }, "interval_ms", I.t("interval ms"), "num", { min = 200 })
		row({ "cpu" }, "color", I.t("color by load"), "bool")
		group(I.t("mem item"))
		row({ "mem" }, "interval_ms", I.t("interval ms"), "num", { min = 200 })
		row({ "mem" }, "color", I.t("color by load"), "bool")
		group(I.t("network"))
		row({ "wifi" }, "interface", I.t("interface"), "str")
		row({ "wifi" }, "refresh_sec", I.t("refresh sec"), "num", { min = 2 })
		group(I.t("wallpaper"))
		row({ "wallpaper" }, "dir", I.t("dir"), "str", { pick = "dir" })
		row({ "wallpaper" }, "depth", I.t("depth"), "num", { min = 1, max = 8 })
		row({ "wallpaper" }, "set_cmd", I.t("set cmd ($f)"), "str", { allow_empty_remove = true })
		group(I.t("power"))
		row({ "power" }, "lock_cmd", I.t("lock cmd"), "str")
		row({ "power" }, "logout_cmd", I.t("logout cmd"), "str", { allow_empty_remove = true })
		row({ "power" }, "confirm", I.t("confirm actions"), "bool")
		group(I.t("launcher"))
		row({ "launcher" }, "use_dmenu_path", I.t("use dmenu_path"), "bool")
		group(I.t("pomodoro"))
		row({ "pomodoro" }, "work_min", I.t("work min"), "num", { min = 1 })
		row({ "pomodoro" }, "break_min", I.t("break min"), "num", { min = 1 })
		group(I.t("misc"))
		row({ "clip_hist" }, "max_items", I.t("clip max items"), "num", { min = 5 })
		row({ "weather" }, "units", I.t("weather units"), "enum", { choices = { "c", "f" } })
		row({ "weather" }, "refresh_sec", I.t("weather refresh sec"), "num", { min = 60 })
		row({ "move_window" }, "step", I.t("move step px"), "num", { min = 1 })
		row({ "move_window" }, "mode", I.t("move mode"), "str")
		row({ "resize_window" }, "step", I.t("resize step px"), "num", { min = 1 })
	end
	return rows, y
end

-- -------------------------------------------------------------------- edit

local function start_edit(p, r)
	M.editing = r
	local cur
	if r.kind == "num" then
		cur = tostring(cfg_get(r.path, r.key) or "")
	elseif r.kind == "list" then
		local v = cfg_get(r.path, r.key)
		if type(v) == "table" then
			cur = table.concat(v, ";")
		else
			cur = v and tostring(v) or ""
		end
	else
		cur = cfg_get(r.path, r.key)
		cur = cur and tostring(cur) or ""
	end
	if p.input then
		p.input:set_value(cur)
		p.input:focus()
	end
end

local function cancel_edit(p)
	M.editing = nil
	if p and p.input then
		p.input:blur()
		p.input:set_value("")
	end
end

local function commit_edit(p)
	local ed = M.editing
	if not ed then
		return
	end
	local v = p.input and p.input.value or ""
	v = v:match("^%s*(.-)%s*$")
	local lit, newval, remove
	if ed.kind == "num" then
		local n = tonumber(v)
		if not n then
			M.ctx.notify(I.t("not a number: %s", v), { style = "error" })
			return
		end
		if ed.min then
			n = math.max(ed.min, math.min(ed.max or math.huge, n))
		end
		n = math.floor(n)
		lit, newval = tostring(n), n
	elseif ed.kind == "list" then
		local items, disp = {}, {}
		for it in (v .. ";"):gmatch("(.-);") do
			it = it:match("^%s*(.-)%s*$")
			if it ~= "" then
				items[#items + 1] = q(it)
				disp[#disp + 1] = it
			end
		end
		lit = #items > 0 and "{ " .. table.concat(items, ", ") .. " }" or "{}"
		newval = disp
	else
		if v == "" and ed.allow_empty_remove then
			remove, newval = true, nil
		else
			lit, newval = q(v), v
		end
	end
	if save_value(ed.path, ed.key, lit, remove) then
		cfg_set(ed.path, ed.key, newval)
		if HOT_KEYS[ed.key] and #(ed.path or {}) == 0 then
			M.ctx.notify(I.t("saved — reloading…"), { style = "info" })
			defer(function()
				M.ctx.actions.hot_reload()
			end)
		else
			local need_r = ed.path and ed.path[1] == "panels"
			M.ctx.notify(need_r and I.t("saved — reload to apply") or I.t("saved"), { style = "success" })
		end
	end
	cancel_edit(p)
end

local function save_bool(r, val)
	if save_value(r.path, r.key, tostring(val)) then
		cfg_set(r.path, r.key, val)
		M.ctx.notify(I.t("saved"), { style = "success", duration = 1500 })
	end
end

local function save_enum(r, val)
	if save_value(r.path, r.key, q(val)) then
		cfg_set(r.path, r.key, val)
		-- language switch takes effect immediately (no reload needed)
		if r.key == "lang" and #(r.path or {}) == 0 then
			I.init(M.ctx)
			redraw_all()
		end
		-- corner style also reshapes the popup windows (radius is fixed at
		-- creation): hot reload rebuilds them so the look stays uniform
		if r.key == "corner" and #(r.path or {}) == 0 then
			M.ctx.notify(I.t("saved — reloading…"), { style = "info" })
			defer(function()
				M.ctx.actions.hot_reload()
			end)
			return
		end
		-- panel pos changes apply on the next open (no reload needed)
		M.ctx.notify(I.t("saved"), { style = "success", duration = 1500 })
	end
end

local function save_panel_opt(name, field, lit, val)
	local path = { "panel_opts" }
	if field == "dismiss_outside" then
		if save_value(path, name, "{ dismiss_outside = " .. tostring(val) .. " }") then
			local po = M.ctx.config.panel_opts or {}
			po[name] = { dismiss_outside = val }
			M.ctx.config.panel_opts = po
			local reg = M.ctx._panels and M.ctx._panels[name]
			if reg and reg.opts then
				reg.opts.ptr_grab = val
			end
			-- re-sync the wayland outside-click catcher / x11 grab
			if M.ctx.sync_ptr_grab then
				M.ctx.sync_ptr_grab()
			end
			M.ctx.notify(I.t("saved"), { style = "success", duration = 1500 })
		end
	end
end

-- persist a plain string value (used by the file-picker rows); mirrors the
-- str branch of commit_edit incl. the hot-reload keys
local function save_str(r, v)
	if save_value(r.path, r.key, q(v)) then
		cfg_set(r.path, r.key, v)
		if HOT_KEYS[r.key] and #(r.path or {}) == 0 then
			M.ctx.notify(I.t("saved — reloading…"), { style = "info" })
			defer(function()
				M.ctx.actions.hot_reload()
			end)
		else
			local need_r = r.path and r.path[1] == "panels"
			M.ctx.notify(need_r and I.t("saved — reload to apply") or I.t("saved"),
				{ style = "success", duration = 1500 })
		end
	end
end

-- open the in-house file picker for a path row; selection goes through
-- the same save path as inline edits
local function open_picker(r)
	require("plugins.file_dialog").open(M.ctx, {
		title = r.label,
		path = cfg_get(r.path, r.key),
		kind = r.pick,
		on_select = function(np)
			save_str(r, np)
			redraw_all()
			-- the dialog replaced this panel (one popup at a time); reopen
			if M.ctx.show_panel then
				M.ctx.show_panel("settings")
			end
		end,
	})
end

-- -------------------------------------------------------------------- draw

local function compute_layout(ctx, lh, us)
	local m = { lh = lh, PAD = PAD }
	m.W = 560
	m.HEADER_H = lh + 26
	m.TABS_H = lh + 30
	m.FOOTER_H = lh + 30
	m.view_y = m.HEADER_H + m.TABS_H
	if us then
		m.W = math.max(480, us.w)
		m.H = math.max(460, us.h)
	else
		-- natural height follows the (roomy) rows of the active tab, capped
		-- at 85% of the screen; overflow scrolls inside the view
		local _, ch = build_rows(ctx, lh, m.W, M.tab or "themes")
		m.H = math.max(520, math.min(ctx.scr_h * 0.85, m.view_y + ch + m.FOOTER_H))
	end
	m.view_h = m.H - m.view_y - m.FOOTER_H
	return m
end

local function val_str(r)
	local v = cfg_get(r.path, r.key)
	if v == nil then
		return I.t("(unset)")
	elseif type(v) == "table" then
		return #v > 0 and table.concat(v, "; ") or I.t("(empty)")
	end
	return tostring(v)
end

-- rough char budget for a pixel width (paths are mostly ASCII)
local function fit_chars(ctx, avail)
	local cw = select(1, ctx.get_text_size("n"))
	return math.max(2, math.floor(avail / math.max(4, cw)))
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh, PAD, W = m.lh, m.PAD, m.W

	-- self-heal on resize: model follows the live surface size so the view
	-- bottom and footer always match the real panel (no row/overlap drift)
	m.W, m.H = p.w, p.h
	m.view_y = m.HEADER_H + m.TABS_H
	-- the edit input grows downward when its text wraps: keep it inside the
	-- footer band (grown below) and shrink the view to stay clear of it
	local in_extra = p.input and p.input:extra_h() or 0
	m.view_h = m.H - m.view_y - m.FOOTER_H - in_extra

	-- rows for the active tab (rebuilt each frame; cheap)
	local rows, content_h = build_rows(ctx, lh, W, M.tab)
	local maxs = math.max(0, content_h - m.view_h)
	M.scroll = math.max(0, math.min(maxs, M.scroll))

	-- scrollable content is painted FIRST; the fixed chrome (header, tab
	-- strip, footer) is painted on top further down, which clips every row
	-- to the view band without needing a scissor primitive
	local sb_w = SB_W
	local CR = W - PAD - sb_w -- card right edge
	local card_x = PAD
	local card_w = CR - card_x
	local sw_x = CR - 16 - SW_W
	local pos_bw = 130
	local pos_x = sw_x - 12 - pos_bw
	local enum_bw = 150
	M.rows_cache = rows
	for _, r in ipairs(rows) do
		local sy = m.view_y + r.y - M.scroll
		if sy >= m.view_y - r.h and sy <= m.view_y + m.view_h + 1 then
			local ty = sy + math.floor((r.h - lh) / 2)
			local swy = sy + math.floor((r.h - SW_H) / 2)
			if r.kind == "group" then
				p:text(PAD + 6, sy + r.h - lh - 2, r.label, T.hint)
			elseif r.kind == "phdr" then
				local hy = sy + r.h - lh - 2
				p:text(PAD + 6, hy, I.t("panel"), T.hint)
				local pw = select(1, ctx.get_text_size(I.t("position")))
				p:text(pos_x + math.floor((pos_bw - pw) / 2), hy, I.t("position"), T.hint)
				local dw = select(1, ctx.get_text_size(I.t("keep open")))
				p:text(CR - 16 - dw, hy, I.t("keep open"), T.hint)
			elseif r.kind == "mode" then
				local bw = math.floor((card_w - 8) / 2)
				local mode = (ctx.config.theme_mode or "dark") == "light" and "light" or "dark"
				if ui:id_button("mode_dark", card_x, sy, bw, r.h, I.t("dark mode"),
					mode == "dark" and { filled = true } or { tonal = true }) then
					if mode ~= "dark" then
						apply_mode("dark")
					end
				end
				if ui:id_button("mode_light", card_x + bw + 8, sy, card_w - bw - 8, r.h, I.t("light mode"),
					mode == "light" and { filled = true } or { tonal = true }) then
					if mode ~= "light" then
						apply_mode("light")
					end
				end
			elseif r.kind == "chip" then
				local active = (r.mode == "dark" and r.name == ctx.config.theme)
					or (r.mode == "light" and r.name == ctx.config.theme_light)
				if ui:id_button(r.id, r.x, sy, r.w, r.h, r.name,
					active and { filled = true } or { tonal = true }) then
					apply_theme(r.name, r.mode)
					save_value({}, r.mode == "light" and "theme_light" or "theme", "'" .. r.name .. "'")
				end
			elseif r.kind == "panel" then
				local hovered = ui:hover(card_x, sy, card_w, r.h)
				p:rrect(card_x, sy, card_w, r.h, CARD_R, hovered and T.surface_hover or T.surface)
				p:text(card_x + 16, ty, r.pname, T.on_var)
				local pv = ctx.config.panels and ctx.config.panels[r.pname] or {}
				local pos = pv.pos or "center"
				local pi = 1
				for i2, c in ipairs(POS_CHOICES) do
					if c == pos then
						pi = i2
						break
					end
				end
				if ui:id_button("ppos:" .. r.pname, pos_x, sy + 6, pos_bw, r.h - 12, pos,
					{ tonal = true }) then
					save_enum({ path = { "panels", r.pname }, key = "pos" }, POS_CHOICES[(pi % #POS_CHOICES) + 1])
				end
				local dis = not (ctx.config.panel_opts and ctx.config.panel_opts[r.pname]
					and ctx.config.panel_opts[r.pname].dismiss_outside == false)
				local _, changed = ui:toggle("pdis:" .. r.pname, sw_x, swy, SW_W, SW_H, dis)
				if changed then
					save_panel_opt(r.pname, "dismiss_outside", nil, not dis)
				end
			else
				-- option rows: bool / enum / num / str / list
				local hovered = r.kind ~= "bool" and ui:hover(card_x, sy, card_w, r.h)
				p:rrect(card_x, sy, card_w, r.h, CARD_R, hovered and T.surface_hover or T.surface)
				p:text(card_x + 16, ty, r.label, T.on_var)
				if r.kind == "bool" then
					local v = cfg_get(r.path, r.key) == true
					local _, changed = ui:toggle("tg:" .. r.id, sw_x, swy, SW_W, SW_H, v)
					if changed then
						save_bool(r, not v)
					end
				elseif r.kind == "enum" then
					local cur = cfg_get(r.path, r.key)
					local choices = r.choices
					local idx = 1
					for i2, c in ipairs(choices) do
						if c == cur then
							idx = i2
							break
						end
					end
					if ui:id_button("en:" .. r.id, CR - 16 - enum_bw, sy + 6, enum_bw, r.h - 12,
						tostring(cur or choices[1]), { tonal = true }) then
						save_enum(r, choices[(idx % #choices) + 1])
					end
				else
					-- str / num / list: value right-aligned, truncated to
					-- the space between the label and the chevron
					local vs = val_str(r)
					local lbl_w = select(1, ctx.get_text_size(r.label))
					local chw = select(1, ctx.get_text_size("›"))
					local val_right = CR - 16 - chw - 8
					local avail = val_right - (card_x + 16 + lbl_w + 12)
					vs = Util.utf8_truncate(vs, fit_chars(ctx, math.max(40, avail)))
					local vw = select(1, ctx.get_text_size(vs))
					p:text(val_right - vw, ty, vs, T.hint)
					p:text(CR - 16 - chw, ty, "›", T.outline_var)
					if ui:clicked(card_x, sy, card_w, r.h) then
						if r.pick then
							-- path row: open the file picker (deferred —
							-- never create/hide panels mid-draw)
							local row = r
							defer(function()
								open_picker(row)
							end)
						else
							start_edit(p, r)
						end
					end
				end
			end
		end
	end

	-- scrollbar (right edge, inside padding)
	if maxs > 0 then
		local off = ui:scrollbar("set_scroll", W - 14, m.view_y, sb_w, m.view_h, M.scroll, maxs)
		M.scroll = off
	end

	-- fixed chrome painted last so scrolled content can never overlap it

	-- header: opaque surface fill also covers rows scrolled past the top
	p:draw_header(I.t("settings"), Util.keybind_hint(ctx, "toggle_settings"), PAD)

	-- tab strip: opaque band over the scroll area, then the shared MIUI
	-- segmented control from core/ui.lua
	local fy = m.H - m.FOOTER_H - in_extra
	p:rect(0, m.HEADER_H, W, m.TABS_H, p.bg)
	local tabs = { "themes", "options", "panels" }
	local seg_h = lh + 18
	local seg_y = m.HEADER_H + math.floor((m.TABS_H - seg_h) / 2)
	local labels = {}
	for i, t in ipairs(tabs) do
		labels[i] = I.t(t)
	end
	local sel = ui:segmented(PAD, seg_y, W - PAD * 2, seg_h, labels,
		M.tab and (function()
			for i, t in ipairs(tabs) do
				if t == M.tab then
					return i
				end
			end
		end)() or 1)
	if sel > 0 then
		local t = tabs[sel]
		if M.tab ~= t then
			M.tab = t
			M.scroll = 0
			-- natural height differs per tab: refit from M.tick
			M.need_fit = true
		end
		cancel_edit(p)
	end

	-- footer: opaque band covers rows scrolled past the bottom; pill
	-- buttons laid out like a MIUI dialog (primary action filled)
	p:rect(0, fy, W, m.FOOTER_H + in_extra, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	if M.editing then
		local lbl = M.editing.label or M.editing.key or ""
		local bh = lh + 12
		local bo = math.floor((m.FOOTER_H - bh) / 2)
		p:text(PAD, mid_y, I.t("edit %s", lbl), T.hint)
		local iw = W - PAD * 2 - 200
		p.input:set_rect(PAD + 90, fy + bo + 2, iw, lh + 8)
		p.input:draw(p)
		if ui:id_button("ed_cancel", PAD + 90 + iw + 10, fy + bo, 44, bh, "esc", { tonal = true }) then
			cancel_edit(p)
		end
		if ui:id_button("ed_ok", PAD + 90 + iw + 62, fy + bo, 44, bh, I.t("ok"), { filled = true }) then
			commit_edit(p)
		end
	else
		p:text(PAD, mid_y, I.t("click a value to edit · saved to config.lua"), T.hint)
		local bw = 72
		local bh = lh + 14
		local bo = math.floor((m.FOOTER_H - bh) / 2)
		if ui:id_button("ft_reload", W - PAD - bw, fy + bo, bw, bh, I.t("reload"), { tonal = true }) then
			defer(function()
				ctx.actions.hot_reload()
			end)
		end
		if ui:id_button("ft_close", W - PAD - bw * 2 - 10, fy + bo, bw, bh, I.t("close"), { filled = true }) then
			defer(function()
				ctx.actions.close_panels()
			end)
		end
	end
end

-- -------------------------------------------------------------------- init

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending_action = nil
	M.tab = "themes"
	M.scroll = 0
	M.editing = nil
	M.need_fit = false
	local panel = Panel.new(ctx, {
		name = "settings",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			return compute_layout(c, c.get_line_height(), us)
		end,
		size_fn = function(c)
			local m = compute_layout(c, c.get_line_height())
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = I.t("new value"),
			max_bytes = 512,
			on_change = function() end,
			on_submit = function()
				commit_edit(M.panel)
			end,
			on_cancel = function()
				if M.editing then
					cancel_edit(M.panel)
				else
					if M.panel then
						M.panel:hide()
					end
				end
			end,
		},
		on_key = function(p, sym)
			if sym == XK_ESCAPE and not M.editing then
				p:hide()
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				local dir = btn == 4 and -1 or 1
				local rows = M.rows_cache
				local row_h = rows and #rows > 0 and rows[1].h or 30
				M.scroll = M.scroll + dir * row_h * 3
				p:draw()
				return
			end
		end,
		on_show = function(p)
			M.scroll = 0
			M.editing = nil
			if p.input then
				p.input:set_value("")
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("settings", panel)
	log("ready")
end

function M.tick(ctx, dt)
	if M.need_fit then
		M.need_fit = false
		if M.panel then
			M.panel:fit()
		end
	end
	if M.pending_action then
		local fn = M.pending_action
		M.pending_action = nil
		local ok, err = pcall(fn)
		if not ok then
			log("pending action error: %s", tostring(err))
		end
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("settings"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "settings" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("settings"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "settings", gx, gw)
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.pending_action = nil
	M.editing = nil
	M.need_fit = nil
	M.ctx = nil
end

return M
