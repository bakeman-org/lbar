-- plugins/color_picker.lua — in-panel painter-style color picker:
-- SV square + hue slider + preview with HEX / RGB / HSV readouts, each
-- click-to-copy (no screen capture involved)
local M = {}
local ffi = require("ffi")
local Panel = require("core.panel")
local Clipboard = require("core.clipboard")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("color_picker")

local function hsv_to_rgb(h, s, v)
	h = (h % 360) / 60
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	local r, g, b
	if i == 0 then
		r, g, b = v, t, p
	elseif i == 1 then
		r, g, b = q, v, p
	elseif i == 2 then
		r, g, b = p, v, t
	elseif i == 3 then
		r, g, b = p, q, v
	elseif i == 4 then
		r, g, b = t, p, v
	else
		r, g, b = v, p, q
	end
	return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function rgb_to_hsv(r, g, b)
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h * 60
	end
	return h, mx > 0 and d / mx or 0, mx / 255
end

local function hex_of(c)
	return string.format("#%02X%02X%02X", c.r, c.g, c.b)
end

local function fmt_rgb(c)
	return string.format("rgb(%d, %d, %d)", c.r, c.g, c.b)
end

local function fmt_hsv(h, s, v)
	return string.format("hsv(%d, %d%%, %d%%)", math.floor(h + 0.5), math.floor(s * 100 + 0.5),
		math.floor(v * 100 + 0.5))
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 24
	m.W = 420
	m.APPBAR = lh + 26
	m.SQ_Y = m.APPBAR + 16
	m.SQ_H = 200
	m.HUE_Y = m.SQ_Y + m.SQ_H + 14
	m.HUE_H = 16
	m.PREV_Y = m.HUE_Y + m.HUE_H + 16
	m.PREV_H = lh * 3 + 10
	m.CHIP_Y = m.PREV_Y + m.PREV_H + 14
	m.CHIP_H = lh + 14
	m.H = m.CHIP_Y + m.CHIP_H + 20
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

-- pixel caches: the SV square re-renders only when the hue (or size)
-- changes; each draw just memcpy's the cached rows into the panel surface
local sq_cache = { hue = -1, w = 0, h = 0, buf = nil }
local hue_cache = { w = 0, buf = nil }

local function ensure_sq_buf(w, h, hue)
	if sq_cache.buf and sq_cache.w == w and sq_cache.h == h and sq_cache.hue == hue then
		return sq_cache.buf
	end
	if not sq_cache.buf or sq_cache.w ~= w or sq_cache.h ~= h then
		sq_cache.buf = ffi.new("uint32_t[?]", w * h)
		sq_cache.w, sq_cache.h = w, h
	end
	sq_cache.hue = hue
	local br, bg, bb = hsv_to_rgb(hue, 1, 1)
	local buf = sq_cache.buf
	for y = 0, h - 1 do
		local v = 1 - y / (h - 1)
		local row = y * w
		for x = 0, w - 1 do
			local s = x / (w - 1)
			local r = v * (s * br + (1 - s) * 255)
			local g = v * (s * bg + (1 - s) * 255)
			local b = v * (s * bb + (1 - s) * 255)
			buf[row + x] = 0xFF000000 + math.floor(r) * 0x10000 + math.floor(g) * 0x100 + math.floor(b)
		end
	end
	return buf
end

local function ensure_hue_buf(w)
	if hue_cache.buf and hue_cache.w == w then
		return hue_cache.buf
	end
	if not hue_cache.buf or hue_cache.w ~= w then
		hue_cache.buf = ffi.new("uint32_t[?]", w)
		hue_cache.w = w
	end
	local buf = hue_cache.buf
	for x = 0, w - 1 do
		local r, g, b = hsv_to_rgb(x / (w - 1) * 360, 1, 1)
		buf[x] = 0xFF000000 + r * 0x10000 + g * 0x100 + b
	end
	return buf
end

local function blit_rows(p, buf, x0, y0, w, rows, src_skip)
	local surf, W = p.surf, p.w
	for i = 0, rows - 1 do
		ffi.copy(surf + (y0 + i) * W + x0, buf + (src_skip or 0) + i * w, w * 4)
	end
end

local function update_color()
	local r, g, b = hsv_to_rgb(M.h, M.s, M.v)
	M.color = { r = r, g = g, b = b }
end

local function set_sv_from_pos(p, mx, my)
	local m = p.m
	local w = m.W - m.PAD * 2
	if w < 2 or m.SQ_H < 2 then
		return
	end
	M.s = math.max(0, math.min(1, (mx - m.PAD) / (w - 1)))
	M.v = math.max(0, math.min(1, 1 - (my - m.SQ_Y) / (m.SQ_H - 1)))
	update_color()
end

local function set_hue_from_pos(p, mx)
	local m = p.m
	local w = m.W - m.PAD * 2
	if w < 2 then
		return
	end
	M.h = ((mx - m.PAD) / (w - 1)) % 1 * 360
	update_color()
end

local function copy_value(ctx, val)
	if val and Clipboard.copy(val) then
		ctx.notify(val .. "  " .. I.t("copied"))
	else
		ctx.notify(val, { style = "info" })
	end
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	local lh = m.LH

	-- self-heal on resize: width follows the live surface
	m.W, m.H = p.w, p.h
	local W, PAD = m.W, m.PAD
	local sq_w = W - PAD * 2

	p:draw_header(I.t("Color Picker"), Util.keybind_hint(ctx, "toggle_color_picker"), PAD)

	-- SV square (s → right, v → up) + cursor ring
	if sq_w >= 2 then
		local buf = ensure_sq_buf(sq_w, m.SQ_H, M.h)
		blit_rows(p, buf, PAD, m.SQ_Y, sq_w, m.SQ_H)
		local cxp = PAD + math.floor(M.s * (sq_w - 1))
		local cyp = m.SQ_Y + math.floor((1 - M.v) * (m.SQ_H - 1))
		p:rect(cxp - 5, cyp - 5, 10, 10, 0xffffff)
		p:rect(cxp - 3, cyp - 3, 6, 6, 0x000000)
		-- restore the exact pixels inside the ring (clamped to the square)
		local sx0 = math.max(0, cxp - 3 - PAD)
		local sy0 = math.max(0, cyp - 3 - m.SQ_Y)
		local w6 = math.min(6, sq_w - sx0)
		local h6 = math.min(6, m.SQ_H - sy0)
		for i = 0, h6 - 1 do
			ffi.copy(p.surf + (cyp - 3 + i) * W + cxp - 3, buf + (sy0 + i) * sq_w + sx0, w6 * 4)
		end
	end

	-- hue bar + cursor line
	if sq_w >= 2 then
		local hbuf = ensure_hue_buf(sq_w)
		blit_rows(p, hbuf, PAD, m.HUE_Y, sq_w, m.HUE_H)
		local hx = PAD + math.floor(M.h / 360 * (sq_w - 1))
		p:rect(hx - 2, m.HUE_Y - 3, 4, m.HUE_H + 6, 0x000000)
		p:rect(hx - 1, m.HUE_Y - 2, 2, m.HUE_H + 4, 0xffffff)
	end

	-- preview swatch + readouts
	p:rrect(PAD, m.PREV_Y, 72, m.PREV_H, 10, M.color.r * 0x10000 + M.color.g * 0x100 + M.color.b)
	local tx = PAD + 72 + 16
	p:text(tx, m.PREV_Y, hex_of(M.color), T.on_var)
	p:text(tx, m.PREV_Y + lh, fmt_rgb(M.color), T.hint)
	p:text(tx, m.PREV_Y + lh * 2, fmt_hsv(M.h, M.s, M.v), T.hint)

	-- copy chips: HEX / RGB / HSV
	local ui = p.ui
	local chips = {
		{ id = "cp_hex", label = "HEX", val = hex_of(M.color) },
		{ id = "cp_rgb", label = "RGB", val = fmt_rgb(M.color) },
		{ id = "cp_hsv", label = "HSV", val = fmt_hsv(M.h, M.s, M.v) },
	}
	local cx = PAD
	for _, c in ipairs(chips) do
		local cw = select(1, ctx.get_text_size(c.label)) + 28
		if ui:id_button(c.id, cx, m.CHIP_Y, cw, m.CHIP_H, c.label, { tonal = true, radius = math.floor(m.CHIP_H / 2) }) then
			copy_value(ctx, c.val)
		end
		cx = cx + cw + 10
	end
end

local function in_sq(p, mx, my)
	local m = p.m
	return mx >= m.PAD and mx < m.W - m.PAD and my >= m.SQ_Y and my < m.SQ_Y + m.SQ_H
end

local function in_hue(p, mx, my)
	local m = p.m
	return mx >= m.PAD and mx < m.W - m.PAD and my >= m.HUE_Y - 4 and my < m.HUE_Y + m.HUE_H + 4
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("Pick"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "color_picker" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("Pick"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "color_picker", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.h, M.s, M.v = 210, 0.7, 0.9
	M.drag = nil
	update_color()

	local panel = Panel.new(ctx, {
		name = "color_picker",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_press = function(p, mx, my, btn)
			if btn == 1 then
				if p:header_hit(mx, my) then
					p:hide()
					return
				end
				if in_sq(p, mx, my) then
					M.drag = "sq"
					set_sv_from_pos(p, mx, my)
				elseif in_hue(p, mx, my) then
					M.drag = "hue"
					set_hue_from_pos(p, mx)
				end
			elseif btn == 4 and in_hue(p, mx, my) then
				M.h = (M.h + 4) % 360
				update_color()
			elseif btn == 5 and in_hue(p, mx, my) then
				M.h = (M.h - 4) % 360
				update_color()
			end
		end,
		on_motion = function(p, mx, my)
			if M.drag == "sq" then
				set_sv_from_pos(p, mx, my)
			elseif M.drag == "hue" then
				set_hue_from_pos(p, mx)
			end
		end,
		on_release = function()
			M.drag = nil
		end,
		on_key = function(p, sym)
			if sym == 0xff1b then
				p:hide()
				return true
			end
			return false
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("color_picker", panel)

	log("ready")
end

function M.shutdown()
	M.ready = false
	M.drag = nil
	M.ctx = nil
end

return M
