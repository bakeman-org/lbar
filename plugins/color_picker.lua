local M = {}
local Panel = require("core.panel")
local Clipboard = require("core.clipboard")
local Util = require("core.util")

local log = Util.logger("color_picker")

local ZOOM = 10
local GRID = 15
local PAD = 12
local XK_ESCAPE = 0xff1b

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

local function in_rect(mx, my, r)
	return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

local function draw_mag(p)
	local ctx = p.ctx
	local half = math.floor(GRID / 2)
	p:clear(0x000000)
	if M.ok then
		for gy = 0, GRID - 1 do
			for gx = 0, GRID - 1 do
				local i = (gy * GRID + gx) * 3
				local col = M.buf[i] * 0x10000 + M.buf[i + 1] * 0x100 + M.buf[i + 2]
				p:rect(PAD + gx * ZOOM, PAD + gy * ZOOM, ZOOM, ZOOM, col)
			end
		end
	end
	local cx0 = PAD + half * ZOOM
	local cy0 = PAD + half * ZOOM
	p:rect(cx0 - 1, cy0 - 1, ZOOM + 2, 1, 0xffffff)
	p:rect(cx0 - 1, cy0 + ZOOM, ZOOM + 2, 1, 0xffffff)
	p:rect(cx0 - 1, cy0, 1, ZOOM, 0xffffff)
	p:rect(cx0 + ZOOM, cy0, 1, ZOOM, 0xffffff)
	if M.color then
		p:text(PAD, PAD + GRID * ZOOM + 10, hex_of(M.color), ctx.theme.on_surface)
	end
end

local function sample(rx, ry)
	local half = math.floor(GRID / 2)
	local rc = M.ctx.L.lbar_x_get_region(
		M.ctx.Lctx, rx - half, ry - half, GRID, GRID, M.buf, GRID * GRID * 3)
	M.ok = rc == 0
	if M.ok then
		local i = half * GRID + half
		M.color = { r = M.buf[i * 3], g = M.buf[i * 3 + 1], b = M.buf[i * 3 + 2] }
	end
	return M.ok
end

local function finish_pick(ok)
	local ctx = M.ctx
	M.picking = false
	ctx.L.lbar_ptr_ungrab(ctx.Lctx)
	ctx.L.lbar_kbd_ungrab(ctx.Lctx)
	M.mag:hide(true)
	if ok and M.color then
		local hex = hex_of(M.color)
		if Clipboard.copy(hex) then
			ctx.notify(hex .. "  copied")
		else
			ctx.notify(hex)
		end
	end
end

local function start_pick()
	local ctx = M.ctx
	if ctx.backend_kind ~= "x11" then
		ctx.notify("color picker needs X11")
		return
	end
	ctx.close_panels()
	M.ok = false
	M.mx, M.my = math.floor(ctx.scr_w / 2), math.floor(ctx.scr_h / 2)
	sample(M.mx, M.my)
	M.mag:show_xy(
		math.floor((ctx.scr_w - M.mag.w) / 2),
		math.floor((ctx.scr_h - M.mag.h) / 2))
	ctx.active_panel = M.mag
	ctx.L.lbar_ptr_grab(ctx.Lctx, M.mag.id)
	ctx.L.lbar_kbd_grab(ctx.Lctx, M.mag.id)
	M.picking = true
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
	M.ok = false
	M.mx, M.my = -1, -1

	M.buf = ctx.ffi.new("unsigned char[?]", GRID * GRID * 3)

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
			M.mx, M.my = rx, ry
			local nx, ny = rx + 20, ry + 20
			if nx + p.w > ctx.scr_w then
				nx = rx - p.w - 20
			end
			if ny + p.h > ctx.scr_h then
				ny = ry - p.h - 20
			end
			if nx < 0 then
				nx = 0
			end
			if ny < 0 then
				ny = 0
			end
			p:move_to(nx, ny)
			sample(rx, ry)
		end,
		on_press = function(p, mx, my, btn, rx, ry)
			if M.picking then
				if btn == 1 then
					M.mx, M.my = rx, ry
					if sample(rx, ry) then
						finish_pick(true)
					else
						finish_pick(false)
					end
				elseif btn ~= 4 and btn ~= 5 then
					finish_pick(false)
				end
			end
		end,
		on_key = function(p, sym)
			if M.picking and sym == XK_ESCAPE then
				finish_pick(false)
				return true
			end
			return M.picking
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
