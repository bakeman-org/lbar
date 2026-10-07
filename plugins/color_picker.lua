local M = {}
local ffi = require("ffi")
local Panel = require("core.panel")
local Clipboard = require("core.clipboard")
local Util = require("core.util")

local log = Util.logger("color_picker")

local ZOOM = 10
local GRID = 15
local PAD = 12
local STEP = 8
local GAP = 24

local XK_ESCAPE = 0xff1b
local XK_LEFT = 0xff51
local XK_UP = 0xff52
local XK_RIGHT = 0xff53
local XK_DOWN = 0xff54
local XK_RETURN = 0xff0d
local XK_KP_ENTER = 0xff8d

local function hex_of(c)
	return string.format("#%02X%02X%02X", c.r, c.g, c.b)
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 22
	m.W = 420
	m.APPBAR = lh + 26
	m.SWATCH_H = 96
	m.BTN_H = lh + 22
	m.HEX_Y = m.APPBAR + 16 + m.SWATCH_H + 12
	m.BTN_Y = m.HEX_Y + lh + 14
	m.H = m.BTN_Y + m.BTN_H + 18
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function pixel_at(x, y)
	local s = M.screen
	if not s or x < 0 or y < 0 or x >= s.w or y >= s.h then
		return nil
	end
	local i = (y * s.w + x) * 3
	return s.buf[i], s.buf[i + 1], s.buf[i + 2]
end

local function color_at(x, y)
	local r, g, b = pixel_at(x, y)
	if not r then
		return nil
	end
	return { r = r, g = g, b = b }
end

local function capture_x11(ctx)
	local w, h = ctx.scr_w, ctx.scr_h
	local buf = ffi.new("unsigned char[?]", w * h * 3)
	local rc = ctx.L.lbar_x_get_region(ctx.Lctx, 0, 0, w, h, buf, w * h * 3)
	if rc ~= 0 then
		return nil
	end
	return { w = w, h = h, buf = buf }
end

local function capture_wayland(ctx)
	local w, h = ctx.scr_w, ctx.scr_h
	local p = io.popen(string.format("grim -g '0,0 %dx%d' - 2>/dev/null", w, h))
	if not p then
		return nil
	end
	local data = p:read("*a")
	p:close()
	if not data or #data < 16 then
		return nil
	end
	local pos = 1
	if data:sub(1, 2) ~= "P6" then
		return nil
	end
	pos = 3
	local vals = {}
	for i = 1, 3 do
		while pos <= #data do
			local b = data:byte(pos)
			if b == 35 then
				while pos <= #data and data:byte(pos) ~= 10 do
					pos = pos + 1
				end
			elseif b == 10 or b == 13 or b == 32 or b == 9 then
				pos = pos + 1
			else
				break
			end
		end
		local v = 0
		local started = false
		while pos <= #data do
			local b = data:byte(pos)
			if b < 48 or b > 57 then
				break
			end
			v = v * 10 + (b - 48)
			started = true
			pos = pos + 1
		end
		if not started then
			return nil
		end
		vals[i] = v
	end
	pos = pos + 1
	local sw, sh = vals[1], vals[2]
	local need = sw * sh * 3
	if sw <= 0 or sh <= 0 or #data - pos + 1 < need then
		return nil
	end
	local buf = ffi.new("unsigned char[?]", need)
	ffi.copy(buf, data:sub(pos, pos + need - 1))
	return { w = sw, h = sh, buf = buf }
end

local function start_pick()
	local ctx = M.ctx
	for _, pn in pairs(ctx._panels or {}) do
		if pn ~= M.mag and pn.visible then
			pn:hide(true)
		end
	end
	local scr = ctx.backend_kind == "x11" and capture_x11(ctx) or capture_wayland(ctx)
	if not scr then
		ctx.notify(ctx.backend_kind == "x11" and "screen capture failed"
			or "screen capture failed (install grim)", { style = "error" })
		return
	end
	M.screen = scr
	M.picking = true
	M.cx = math.floor(ctx.scr_w / 2)
	M.cy = math.floor(ctx.scr_h / 2)
	M.color = color_at(M.cx, M.cy)
	M.mag:show_xy(math.floor((ctx.scr_w - M.mag.w) / 2), math.floor((ctx.scr_h - M.mag.h) / 2))
	ctx.active_panel = M.mag
	ctx.L.lbar_ptr_grab(ctx.Lctx, M.mag.id)
	ctx.L.lbar_kbd_grab(ctx.Lctx, M.mag.id)
end

local function place_mag(p)
	local ctx = M.ctx
	local nx, ny = M.cx + GAP, M.cy + GAP
	if nx + p.w > ctx.scr_w then
		nx = M.cx - p.w - GAP
	end
	if ny + p.h > ctx.scr_h then
		ny = M.cy - p.h - GAP
	end
	if nx < 0 then
		nx = 0
	end
	if ny < 0 then
		ny = 0
	end
	p:move_to(nx, ny)
end

local function draw_mag(p)
	local ctx = p.ctx
	local half = math.floor(GRID / 2)
	p:clear(0x000000)
	for gy = 0, GRID - 1 do
		for gx = 0, GRID - 1 do
			local r, g, b = pixel_at(M.cx - half + gx, M.cy - half + gy)
			local col = r and (r * 0x10000 + g * 0x100 + b) or 0x000000
			p:rect(PAD + gx * ZOOM, PAD + gy * ZOOM, ZOOM, ZOOM, col)
		end
	end
	local cx0 = PAD + half * ZOOM
	local cy0 = PAD + half * ZOOM
	p:rect(cx0 - 1, cy0 - 1, ZOOM + 2, 1, 0xffffff)
	p:rect(cx0 - 1, cy0 + ZOOM, ZOOM + 2, 1, 0xffffff)
	p:rect(cx0 - 1, cy0, 1, ZOOM, 0xffffff)
	p:rect(cx0 + ZOOM, cy0, 1, ZOOM, 0xffffff)
	local label = M.color and hex_of(M.color) or "—"
	if M.screen then
		label = string.format("%s  %d,%d", label, M.cx, M.cy)
	end
	p:text(PAD, PAD + GRID * ZOOM + 10, label, ctx.theme.on_surface)
end

local function finish_pick(ok)
	local ctx = M.ctx
	M.picking = false
	ctx.L.lbar_ptr_ungrab(ctx.Lctx)
	ctx.L.lbar_kbd_ungrab(ctx.Lctx)
	M.mag:hide(true)
	M.screen = nil
	if ok and M.color then
		local hex = hex_of(M.color)
		if Clipboard.copy(hex) then
			ctx.notify(hex .. "  copied")
		else
			ctx.notify(hex)
		end
	end
end

local function move_cursor(p, dx, dy)
	local s = M.screen
	if not s then
		return
	end
	local step = M.step or STEP
	M.cx = math.max(0, math.min(s.w - 1, M.cx + dx * step))
	M.cy = math.max(0, math.min(s.h - 1, M.cy + dy * step))
	M.color = color_at(M.cx, M.cy)
	place_mag(p)
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	local lh, W = m.LH, m.W

	local hint = Util.keybind_hint(ctx, "toggle_color_picker")
	p:draw_header("Color Picker", hint, m.PAD)

	local sw = W - m.PAD * 2
	local sy = m.APPBAR + 16
	p:rrect(m.PAD - 4, sy - 4, sw + 8, m.SWATCH_H + 8, 12, T.outline)
	local col = M.color and (M.color.r * 0x10000 + M.color.g * 0x100 + M.color.b)
		or T.surface_hi
	p:rrect(m.PAD, sy, sw, m.SWATCH_H, 10, col)

	local hex = M.color and hex_of(M.color) or "not picked"
	local hexw = select(1, ctx.get_text_size(hex))
	p:text(math.floor((W - hexw) / 2), m.HEX_Y, hex, T.on_surface)

	local bw = math.floor((W - m.PAD * 2 - 14) / 2)
	local ui = p.ui
	if ui:id_button("cp_pick", m.PAD, m.BTN_Y, bw, m.BTN_H, "Pick", { filled = true }) then
		start_pick()
	end
	if ui:id_button("cp_copy", m.PAD + bw + 14, m.BTN_Y, bw, m.BTN_H, "Copy", { tonal = true }) then
		if M.color then
			local hex2 = hex_of(M.color)
			if Clipboard.copy(hex2) then
				ctx.notify(hex2 .. "  copied")
			else
				ctx.notify(hex2)
			end
		else
			ctx.notify("nothing picked yet")
		end
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size("pick")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "color_picker" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "pick", active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "color_picker", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.picking = false
	M.color = nil
	M.screen = nil
	M.cx, M.cy = 0, 0
	M.step = STEP

	local panel = Panel.new(ctx, {
		name = "color_picker",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("color_picker", panel)

	local mag = Panel.new(ctx, {
		name = "color_mag",
		radius = 4,
		bg = 0x000000,
		ui = false,
		anim = "none",
		kbd = true,
		ptr_grab = false,
		size_fn = function(c)
			local lh = c.get_line_height()
			return PAD * 2 + GRID * ZOOM, PAD + GRID * ZOOM + 10 + lh + PAD
		end,
		draw = draw_mag,
		on_motion = function(p, mx, my, rx, ry)
			if not M.picking or not M.screen then
				return
			end
			M.cx = math.max(0, math.min(M.screen.w - 1, rx))
			M.cy = math.max(0, math.min(M.screen.h - 1, ry))
			M.color = color_at(M.cx, M.cy)
			place_mag(p)
		end,
		on_press = function(p, mx, my, btn, rx, ry)
			if not M.picking then
				return
			end
			if btn == 1 then
				if M.screen then
					M.cx = math.max(0, math.min(M.screen.w - 1, rx))
					M.cy = math.max(0, math.min(M.screen.h - 1, ry))
					M.color = color_at(M.cx, M.cy)
				end
				finish_pick(true)
			elseif btn ~= 4 and btn ~= 5 then
				finish_pick(false)
			end
		end,
		on_key = function(p, sym, text, ctrl, shift)
			if not M.picking then
				return false
			end
			M.step = shift and 1 or STEP
			if sym == XK_ESCAPE then
				finish_pick(false)
				return true
			elseif sym == XK_LEFT then
				move_cursor(p, -1, 0)
			elseif sym == XK_RIGHT then
				move_cursor(p, 1, 0)
			elseif sym == XK_UP then
				move_cursor(p, 0, -1)
			elseif sym == XK_DOWN then
				move_cursor(p, 0, 1)
			elseif sym == XK_RETURN or sym == XK_KP_ENTER then
				finish_pick(true)
				return true
			end
			return true
		end,
	})
	if not mag then
		log("magnifier panel create failed")
		return
	end
	M.mag = mag

	log("ready")
end

function M.shutdown()
	if M.picking then
		finish_pick(false)
	end
	M.ready = false
	M.ctx = nil
end

return M
