-- plugins/workspace.lua — occupied workspaces bar item (niri, hyprland,
-- sway fallback): every occupied workspace shown, focused one highlighted;
-- clicking a workspace number focuses that workspace
local M = {}
local I = require("core.i18n")
local Hypr = require("core.wm.hyprland")

local POLL_MS = 500
local OUT = "/tmp/lbar-ws.json"
local DONE = "/tmp/lbar-ws.done"

local backend = nil	-- "niri" | "hyprland" | "sway" | nil
local tokens = nil	-- {{ id, tok, focused }} sorted by id
local joined = nil	-- display string "ws1 ws2 ..." for width
local key_prev = nil	-- last rendered signature (text + focus)
local pending = false	-- background job outstanding
local pending_at = 0
local refetch = false	-- fresh fetch requested (e.g. after a click focus)
local last = 0
M.hits = nil	-- per-number hit spans (x relative to item), rebuilt in draw
M._exec = nil	-- test override: dispatch fn for focus commands

local function detect()
	if os.getenv("NIRI_SOCKET") then
		return "niri"
	end
	if os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
		return "hyprland"
	end
	if os.getenv("SWAYSOCK") then
		return "sway"
	end
	return nil
end

local function slurp(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function ws_token(id, name)
	-- numeric names render as the bare id
	if name and not name:match("^%d+$") then
		return name
	end
	return tostring(id)
end

-- one job dumps both payloads into one tmpfile, sections tagged W/A:
--   W
--   <hyprctl -j workspaces>
--   A
--   <hyprctl -j activeworkspace>
-- returns tokens (windows > 0, ascending id), active id
function M.parse_hypr(s)
	local wjson, ajson, sec
	for line in (s .. "\n"):gmatch("([^\n]*)\n") do
		if line == "W" then
			sec = "W"
		elseif line == "A" then
			sec = "A"
		elseif sec == "W" and line ~= "" then
			wjson = (wjson or "") .. line
		elseif sec == "A" and line ~= "" then
			ajson = (ajson or "") .. line
		end
	end
	if not wjson then
		return nil
	end
	local active = ajson and tonumber(ajson:match('"id"%s*:%s*(%-?%d+)')) or nil
	local list = {}
	for obj in wjson:gmatch("{(.-)}") do
		local id = tonumber(obj:match('"id"%s*:%s*(%-?%d+)'))
		local wins = tonumber(obj:match('"windows"%s*:%s*(%-?%d+)'))
		if id and wins and wins > 0 then
			list[#list + 1] = { id = id, tok = ws_token(id, obj:match('"name"%s*:%s*"([^"]*)"')) }
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list, active
end

-- swaymsg -t get_workspaces -r: every entry exists (occupied); entries hold
-- num/name/focused plus a nested rect, so chunk on '{"num"' instead of braces
function M.parse_sway(s)
	local list, focused, pos = nil, nil, 1
	while true do
		local a = s:find('{"num"', pos, true)
		if not a then
			break
		end
		local b = s:find('{"num"', a + 1, true)
		local obj = s:sub(a, (b or 0) - 1)
		pos = a + 1
		local num = tonumber(obj:match('"num"%s*:%s*(%-?%d+)'))
		if num then
			list = list or {}
			list[#list + 1] = { id = num, tok = ws_token(num, obj:match('"name"%s*:%s*"([^"]*)"')) }
			if obj:find('"focused"%s*:%s*true') then
				focused = num
			end
		end
	end
	if list then
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
	end
	return list, focused
end

-- niri msg --json workspaces: array of flat objects; every workspace is
-- listed, so filter on is_occupied; focus = is_active; idx (1-based per
-- output) is the number focus-workspace takes, so idx is our id
function M.parse_niri(s)
	local list, focused, pos = nil, nil, 1
	while true do
		local a = s:find('{"id"', pos, true)
		if not a then
			break
		end
		local b = s:find('{"id"', a + 1, true)
		local obj = s:sub(a, (b or 0) - 1)
		pos = a + 1
		local idx = tonumber(obj:match('"idx"%s*:%s*(%-?%d+)'))
		if idx then
			if obj:find('"is_occupied"%s*:%s*true') then
				list = list or {}
				list[#list + 1] = { id = idx, tok = ws_token(idx, obj:match('"name"%s*:%s*"([^"]*)"')) }
			end
			if obj:find('"is_active"%s*:%s*true') then
				focused = idx
			end
		end
	end
	if list then
		table.sort(list, function(a, b)
			return a.id < b.id
		end)
	end
	return list, focused
end

-- parse by backend; test hook for parser unit tests too
function M._parse(body)
	if backend == "hyprland" then
		return M.parse_hypr(body)
	elseif backend == "niri" then
		return M.parse_niri(body)
	end
	return M.parse_sway(body)
end

-- background job: dump json to a tmpfile with a done marker, never block
local function spawn()
	os.remove(OUT)
	os.remove(DONE)
	local cmd
	if backend == "hyprland" then
		cmd = string.format(
			"( echo W; hyprctl -j workspaces; echo A; hyprctl -j activeworkspace; echo 1 > %s ) > %s 2>/dev/null &",
			DONE, OUT)
	elseif backend == "niri" then
		cmd = string.format(
			"( niri msg --json workspaces; echo 1 > %s ) > %s 2>/dev/null &",
			DONE, OUT)
	else
		cmd = string.format(
			"( swaymsg -t get_workspaces -r; echo 1 > %s ) > %s 2>/dev/null &",
			DONE, OUT)
	end
	os.execute(cmd)
	pending = true
	pending_at = os.time()
end

local function apply(ctx, t, act)
	local texts = {}
	for i, e in ipairs(t) do
		e.focused = e.id == act
		texts[i] = e.tok
	end
	local key = table.concat(texts, " ") .. "#" .. tostring(act)
	if key == key_prev then
		return
	end
	key_prev = key
	tokens = t
	joined = table.concat(texts, " ")
	M.hits = nil -- stale spans until the next draw
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

local function harvest(ctx)
	local body = slurp(OUT)
	os.remove(OUT)
	os.remove(DONE)
	if not body or body == "" then
		return
	end
	local t, act = M._parse(body)
	if not t then
		return
	end
	apply(ctx, t, act)
end

-- offline test hook: parse + apply a payload as if harvested
function M._ingest(ctx, body)
	local t, act = M._parse(body)
	if t then
		apply(ctx, t, act)
	end
end

-- immediate fresh fetch after a click focus (don't wait the poll interval)
local function kick()
	if pending then
		refetch = true
	else
		spawn()
	end
end

function M.init(ctx)
	backend = detect()
	if backend then
		os.remove(OUT)
		os.remove(DONE)
		last = POLL_MS	-- first poll right away
		local log = require("core.util").logger("workspace")
		log("backend: %s", backend)
	end
end

function M.width(ctx)
	if not backend or not joined or joined == "" then
		return 0
	end
	return 8 + ctx.text_width(I.t("WS") .. " " .. joined)
end

function M.tick(ctx, dt)
	if not backend then
		return
	end
	if pending then
		-- harvest on every tick so results land within one frame
		if slurp(DONE) then
			pending = false
			harvest(ctx)
			if refetch then
				refetch = false
				spawn()
			end
		elseif os.time() - pending_at > 5 then
			pending = false	-- job hung, retry next poll
		end
		return
	end
	if refetch then
		refetch = false
		spawn()
		return
	end
	last = last + dt
	if last >= POLL_MS then
		last = 0
		spawn()
	end
end

function M.draw(ctx, s, x, y, w, h)
	if not tokens or #tokens == 0 then
		M.hits = nil
		return
	end
	local lh = ctx.get_line_height()
	local ty = math.floor((h - lh) / 2)
	local T = ctx.theme
	local px = x + 4
	s:text(px, ty, I.t("WS") .. " ", T.fg)
	px = px + ctx.text_width(I.t("WS") .. " ")
	local sp = ctx.text_width(" ")
	-- per-number hit spans; x relative to the item start (the click
	-- handler receives lx = mx - item_x)
	M.hits = {}
	for i, e in ipairs(tokens) do
		if i > 1 then
			px = px + sp
		end
		s:text(px, ty, e.tok, e.focused and T.primary or T.fg)
		local tw = ctx.text_width(e.tok)
		M.hits[#M.hits + 1] = { x = px - x, w = tw, id = e.id, focused = e.focused }
		px = px + tw
	end
end

-- async dispatch, never blocks the draw path
local function focus_ws(id)
	local cmd
	if backend == "niri" then
		cmd = string.format("niri msg action focus-workspace %d >/dev/null 2>&1 &", id)
	elseif backend == "hyprland" then
		-- lua config provider: hyprctl dispatch joins raw args into
		-- hl.dispatch(<args>) which is invalid lua for "workspace N"
		cmd = string.format("(%s) &", Hypr.dispatch_cmd(
			string.format("hl.dispatch(hl.dsp.focus({ workspace = %d }))", id),
			string.format("workspace %d", id)))
	elseif backend == "sway" then
		cmd = string.format("swaymsg workspace number %d >/dev/null 2>&1 &", id)
	end
	if cmd then
		local exec = M._exec or os.execute
		exec(cmd)
		kick()
	end
end

-- click a workspace number -> focus that workspace; clicks outside any
-- number (label, gaps) are a no-op
function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn ~= 1 or not M.hits then
		return
	end
	for _, r in ipairs(M.hits) do
		if lx >= r.x and lx < r.x + r.w then
			if not r.focused then
				focus_ws(r.id)
			end
			return
		end
	end
end

function M.shutdown()
	backend = nil
	tokens = nil
	joined = nil
	key_prev = nil
	pending = false
	refetch = false
	M.hits = nil
end

return M
