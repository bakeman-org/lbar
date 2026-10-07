local M = {}
local Util = require("core.util")

local log = Util.logger("resize_window")

local DEFAULT_STEP = 30
local MIN_PANEL_W = 220
local MIN_PANEL_H = 100

local function has_cmd(cmd)
	local f = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if not f then
		return false
	end
	local r = f:read("*l")
	f:close()
	return r ~= nil and r ~= ""
end

local function pick_active_panel(ctx)
	local ap = ctx.active_panel
	if ap and ap.visible and ap.live_resize then
		return ap
	end
	for _, p in pairs(ctx._panels or {}) do
		if p.visible and p.live_resize then
			return p
		end
	end
	return nil
end

local function try_resize_panel(ctx, dx, dy)
	local p = pick_active_panel(ctx)
	if not p then
		return false
	end
	p._orig_geom = p._orig_geom or { w = p.w, h = p.h, x = p.sx, y = p.sy }
	local nw = math.max(MIN_PANEL_W, p.w + dx)
	local nh = math.max(MIN_PANEL_H, p.h + dy)
	p.user_size = { w = nw, h = nh }
	p:live_resize(nw, nh)
	return true
end

local function resize_external(dx, dy)
	if M.wm == "i3" then
		local axis = dx ~= 0 and "width" or "height"
		local op = (dx > 0 or dy > 0) and "grow" or "shrink"
		local amt = math.abs(dx + dy)
		os.execute(string.format(
			"i3-msg 'resize %s %s %d px' >/dev/null 2>&1 &", op, axis, amt))
	elseif M.wm == "hyprland" then
		os.execute(string.format(
			"hyprctl dispatch resizeactive %d %d >/dev/null 2>&1 &", dx, dy))
	end
end

local function resize(dx, dy)
	if try_resize_panel(M.ctx, dx, dy) then
		return
	end
	resize_external(dx, dy)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true

	local cfg = ctx.config.resize_window or {}
	M.step = math.max(4, tonumber(cfg.step) or DEFAULT_STEP)

	if has_cmd("i3-msg") then
		M.wm = "i3"
	elseif has_cmd("hyprctl") then
		M.wm = "hyprland"
	else
		M.wm = nil
		log("no i3-msg or hyprctl - external window resize unavailable")
	end

	ctx.actions["resize_win_wider"] = function()
		resize(M.step, 0)
	end
	ctx.actions["resize_win_narrower"] = function()
		resize(-M.step, 0)
	end
	ctx.actions["resize_win_taller"] = function()
		resize(0, M.step)
	end
	ctx.actions["resize_win_shorter"] = function()
		resize(0, -M.step)
	end

	ctx.actions["reset_active_window"] = function()
		local p = pick_active_panel(ctx)
		if p then
			p.user_size = nil
			if p._orig_geom then
				local g = p._orig_geom
				p:live_resize(g.w, g.h)
				p:move_to(g.x, g.y)
			end
		end
	end

	log("ready: step=%d wm=%s", M.step, tostring(M.wm))
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
