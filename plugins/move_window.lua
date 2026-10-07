local M = {}
local Util = require("core.util")

local log = Util.logger("move_window")

local DEFAULT_STEP = 30

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
	if ap and ap.visible and ap.move_by then
		return ap
	end
	for _, p in pairs(ctx._panels or {}) do
		if p.visible and p.move_by then
			return p
		end
	end
	return nil
end

local function try_move_panel(ctx, dx, dy)
	local p = pick_active_panel(ctx)
	if not p then
		return false
	end
	p:move_by(dx, dy)
	return true
end

local function move_external(dx, dy)
	if M.wm == "i3" then
		local dir = dx < 0 and "left" or dx > 0 and "right" or dy < 0 and "up" or "down"
		os.execute(string.format(
			"i3-msg 'move %s %d px' >/dev/null 2>&1 &", dir, math.abs(dx + dy)))
	elseif M.wm == "hyprland" then
		if M.mode == "auto_float" then
			os.execute(string.format([[
(
  if hyprctl -j activewindow 2>/dev/null | grep -q '"floating": *false'; then
    hyprctl dispatch togglefloating >/dev/null 2>&1
  fi
  hyprctl dispatch moveactive %d %d >/dev/null 2>&1
) &
]], dx, dy))
		else
			os.execute(string.format(
				"hyprctl dispatch moveactive %d %d >/dev/null 2>&1 &", dx, dy))
		end
	end
end

local function move(dx, dy)
	if try_move_panel(M.ctx, dx, dy) then
		return
	end
	move_external(dx, dy)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true

	local cfg = ctx.config.move_window or {}
	M.step = math.max(1, tonumber(cfg.step) or DEFAULT_STEP)
	M.mode = cfg.mode or "auto_float"

	if has_cmd("i3-msg") then
		M.wm = "i3"
	elseif has_cmd("hyprctl") then
		M.wm = "hyprland"
	else
		M.wm = nil
		log("no i3-msg or hyprctl - external window move unavailable")
	end

	ctx.actions["move_win_left"] = function()
		move(-M.step, 0)
	end
	ctx.actions["move_win_right"] = function()
		move(M.step, 0)
	end
	ctx.actions["move_win_up"] = function()
		move(0, -M.step)
	end
	ctx.actions["move_win_down"] = function()
		move(0, M.step)
	end

	log("ready: step=%d wm=%s", M.step, tostring(M.wm))
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
