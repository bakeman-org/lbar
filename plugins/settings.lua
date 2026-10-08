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

local POS_CHOICES = { "center", "top", "top_left", "top_right", "bottom", "bottom_left", "bottom_right" }

local function row_add(rows, y, lh, r)
	r.y = y
	r.h = r.h or (lh + 16)
	r.id = (r.kind or "edit") .. ":" .. table.concat(r.path or {}, ".") .. ":" .. (r.key or r.label or "")
	rows[#rows + 1] = r
	return y + r.h
end

local function build_rows(ctx, lh, W, tab)
	local rows = {}
	local y = 0
	if tab == "themes" then
		local CHIP_W = math.floor((W - 40 - 12) / 2)
		y = row_add(rows, y, lh, { kind = "mode", label = I.t("mode"), h = lh + 18 })
		for _, grp in ipairs({ { I.t("dark themes"), PALETTE_DARK, "dark" }, { I.t("light themes"), PALETTE_LIGHT, "light" } }) do
			y = row_add(rows, y, lh, { kind = "group", label = grp[1], h = lh + 10 })
			local col = 0
			local row_y = y
			for _, name in ipairs(grp[2]) do
				rows[#rows + 1] = {
					kind = "chip", name = name, mode = grp[3],
					x = 20 + (col % 2) * (CHIP_W + 12),
					y = row_y + math.floor(col / 2) * (lh + 22),
					h = lh + 18, w = CHIP_W, id = "chip:" .. grp[3] .. ":" .. name,
				}
				y = math.max(y, row_y + math.floor(col / 2) * (lh + 22) + lh + 18)
				col = col + 1
			end
			y = y + 12
		end
	elseif tab == "panels" then
		y = row_add(rows, y, lh, { kind = "phdr", label = I.t("panels"), h = lh + 8 })
		local names = {}
		local seen = {}
		for _, src in ipairs({ ctx.config.panels or {}, ctx.config.panel_opts or {} }) do
			for k in pairs(src) do
				if not seen[k] then
					seen[k] = true
					names[#names + 1] = k
				end
			end
		end
		table.sort(names)
		for _, name in ipairs(names) do
			y = row_add(rows, y, lh, { kind = "panel", pname = name, label = name, h = lh + 18 })
		end
	else
		local function group(label)
			y = row_add(rows, y, lh, { kind = "group", label = label, h = lh + 12 })
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
		group(I.t("fonts"))
		row({}, "font_path", I.t("font path"), "str")
		row({}, "font_size", I.t("font size"), "num", { min = 10, max = 32 })
		row({}, "fallback_font_paths", I.t("fallback fonts (;)"), "list")
		group(I.t("paths"))
		row({}, "audio_panel_dir", I.t("music dir"), "str")
		row({}, "music_state_file", I.t("music state file"), "str")
		row({ "clock" }, "schedule_file", I.t("schedule file"), "str")
		row({}, "lang", I.t("language"), "enum", { choices = { "auto", "en", "zh" } })
		group(I.t("cpu item"))
		row({ "cpu" }, "style", I.t("style"), "enum", { choices = { "text", "graph", "both" } })
		row({ "cpu" }, "interval_ms", I.t("interval ms"), "num", { min = 200 })
		row({ "cpu" }, "history", I.t("history"), "num", { min = 4, max = 120 })
		row({ "cpu" }, "color", I.t("color by load"), "bool")
		group(I.t("mem item"))
		row({ "mem" }, "style", I.t("style"), "enum", { choices = { "text", "graph", "both" } })
		row({ "mem" }, "interval_ms", I.t("interval ms"), "num", { min = 200 })
		row({ "mem" }, "color", I.t("color by load"), "bool")
		group(I.t("network"))
		row({ "wifi" }, "interface", I.t("interface"), "str")
		row({ "wifi" }, "refresh_sec", I.t("refresh sec"), "num", { min = 2 })
		group(I.t("wallpaper"))
		row({ "wallpaper" }, "dir", I.t("dir"), "str")
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
		local is_pos = r.path and r.path[1] == "panels"
		M.ctx.notify(is_pos and I.t("saved — reload to apply") or I.t("saved"), { style = "success", duration = 1500 })
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
			M.ctx.notify(I.t("saved"), { style = "success", duration = 1500 })
		end
	end
end

-- -------------------------------------------------------------------- draw

local function compute_layout(ctx, lh, us)
	local m = { lh = lh, PAD = 20 }
	m.W = 560
	m.HEADER_H = lh + 26
	m.TABS_H = lh + 30
	m.FOOTER_H = lh + 30
	if us then
		m.W = math.max(480, us.w)
		m.H = math.max(460, us.h)
	else
		m.H = math.max(520, math.min(ctx.scr_h * 0.85, 800))
	end
	m.view_y = m.HEADER_H + m.TABS_H
	m.view_h = m.H - m.view_y - m.FOOTER_H
	return m
end

local function val_str(r)
	local v = cfg_get(r.path, r.key)
	if v == nil then
		return "(unset)"
	elseif type(v) == "table" then
		return #v > 0 and table.concat(v, "; ") or "(empty)"
	end
	return tostring(v)
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
	m.view_h = m.H - m.view_y - m.FOOTER_H

	p:draw_header(I.t("settings"), Util.keybind_hint(ctx, "toggle_settings"), PAD)

	-- tab bar
	local tabs = { { "themes", I.t("themes") }, { "options", I.t("options") }, { "panels", I.t("panels") } }
	local tw = math.floor((W - PAD * 2 - 16) / 3)
	for i, t in ipairs(tabs) do
		local tx = PAD + (i - 1) * (tw + 8)
		if ui:id_button("tab_" .. t[1], tx, m.HEADER_H + 4, tw, lh + 14, t[2],
			M.tab == t[1] and { filled = true } or { tonal = true }) then
			M.tab = t[1]
			M.scroll = 0
			cancel_edit(p)
		end
	end

	-- rows for the active tab (rebuilt each frame; cheap)
	local rows, content_h = build_rows(ctx, lh, W, M.tab)
	local maxs = math.max(0, content_h - m.view_h)
	M.scroll = math.max(0, math.min(maxs, M.scroll))

	-- rows
	local sb_w = 6
	M.rows_cache = rows
	for _, r in ipairs(rows) do
		local sy = m.view_y + r.y - M.scroll
		if sy >= m.view_y - r.h and sy + r.h <= m.view_y + m.view_h + 1 then
			if r.kind == "group" then
				p:text(PAD, sy, r.label, T.hint)
			elseif r.kind == "phdr" then
				p:text(PAD, sy, I.t("panel"), T.hint)
				p:text(W - PAD - 220, sy, I.t("position"), T.hint)
				p:text(W - PAD - sb_w - 58, sy, I.t("keep open"), T.hint)
			elseif r.kind == "mode" then
				local bw = math.floor((W - PAD * 2 - 8) / 2)
				local mode = (ctx.config.theme_mode or "dark") == "light" and "light" or "dark"
				if ui:id_button("mode_dark", PAD, sy, bw, r.h, I.t("dark mode"),
					mode == "dark" and { filled = true } or { tonal = true }) then
					if mode ~= "dark" then
						apply_mode("dark")
					end
				end
				if ui:id_button("mode_light", PAD + bw + 8, sy, bw, r.h, I.t("light mode"),
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
				if ui:hover(PAD - 4, sy, W - PAD * 2 - sb_w + 4, r.h) then
					p:rrect(PAD - 4, sy, W - PAD * 2 - sb_w + 4, r.h, 8, T.surface_hover)
				end
				p:text(PAD, sy + 2, r.pname, T.on_var)
				local pv = ctx.config.panels and ctx.config.panels[r.pname] or {}
				local pos = pv.pos or "center"
				local pbw = 150
				local pi = 1
				for i2, c in ipairs(POS_CHOICES) do
					if c == pos then
						pi = i2
						break
					end
				end
				if ui:id_button("ppos:" .. r.pname, W - PAD - sb_w - 58 - pbw - 10, sy, pbw, r.h - 4, pos,
					{ tonal = true }) then
					save_enum({ path = { "panels", r.pname }, key = "pos" }, POS_CHOICES[(pi % #POS_CHOICES) + 1])
				end
				local dis = not (ctx.config.panel_opts and ctx.config.panel_opts[r.pname]
					and ctx.config.panel_opts[r.pname].dismiss_outside == false)
				local _, changed = ui:toggle("pdis:" .. r.pname, W - PAD - sb_w - 44, sy + 2, 44, 22, dis)
				if changed then
					save_panel_opt(r.pname, "dismiss_outside", nil, not dis)
				end
			else
				-- option rows: bool / enum / num / str / list
				if r.kind ~= "bool" then
					if ui:hover(PAD - 4, sy, W - PAD * 2 - sb_w + 4, r.h) then
						p:rrect(PAD - 4, sy, W - PAD * 2 - sb_w + 4, r.h, 8, T.surface_hover)
					end
				end
				p:text(PAD, sy + 2, r.label, T.on_var)
				if r.kind == "bool" then
					local v = cfg_get(r.path, r.key) == true
					local _, changed = ui:toggle("tg:" .. r.id, W - PAD - sb_w - 44, sy + 2, 44, 22, v)
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
					if ui:id_button("en:" .. r.id, W - PAD - sb_w - 150, sy, 150, r.h - 4,
						tostring(cur or choices[1]), { tonal = true }) then
						save_enum(r, choices[(idx % #choices) + 1])
					end
				else
					local vs = val_str(r)
					local vw = select(1, ctx.get_text_size(vs))
					p:text(W - PAD - sb_w - 16 - vw, sy + 2, vs, T.hint)
					p:text(W - PAD - sb_w - 10, sy + 2, "›", T.outline_var)
					if ui:clicked(PAD - 4, sy, W - PAD * 2 - sb_w + 4, r.h) then
						start_edit(p, r)
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

	-- footer
	local fy = m.H - m.FOOTER_H
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	if M.editing then
		local lbl = M.editing.label or M.editing.key or ""
		p:text(PAD, fy + 6, I.t("edit %s", lbl), T.hint)
		local iw = W - PAD * 2 - 200
		p.input:set_rect(PAD + 90, fy + 4, iw, lh + 8)
		p.input:draw(p)
		if ui:id_button("ed_cancel", PAD + 90 + iw + 10, fy + 5, 44, lh + 6, "esc", { tonal = true }) then
			cancel_edit(p)
		end
		if ui:id_button("ed_ok", PAD + 90 + iw + 62, fy + 5, 44, lh + 6, "ok", { filled = true }) then
			commit_edit(p)
		end
	else
		p:text(PAD, fy + 8, I.t("click a value to edit · saved to config.lua"), T.hint)
		local bw = 64
		local bh = lh + 8
		if ui:id_button("ft_reload", W - PAD - bw, fy + 4, bw, bh, I.t("reload"), { tonal = true }) then
			defer(function()
				ctx.actions.hot_reload()
			end)
		end
		if ui:id_button("ft_close", W - PAD - bw * 2 - 10, fy + 4, bw, bh, I.t("close"), { tonal = true }) then
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
	return select(1, ctx.get_text_size("set")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "settings" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "set", active and ctx.theme.primary or ctx.theme.on_surface)
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
	M.ctx = nil
end

return M
