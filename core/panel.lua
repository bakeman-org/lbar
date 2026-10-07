-- core/panel.lua — panel windows with MD3 styling, adaptive sizing,
-- UI widget wiring and keyboard focus support
local M = {}
local ffi = require("ffi")
local bit = require("bit")
local UIfw = require("core.ui")
local TI = require("core.text_input")

local Panel = {}
Panel.__index = Panel

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function key_translate(ctx, keycode, state)
	local buf = ffi.new("char[?]", 64)
	local sym = ctx.L.lbar_key_lookup(ctx.Lctx, keycode, state, buf, 64)
	local text = ffi.string(buf)
	local ctrl = bit.band(state, 0x4) ~= 0
	local shift = bit.band(state, 0x1) ~= 0
	return tonumber(sym), text, ctrl, shift
end

function M.new(ctx, opts)
	opts = opts or {}
	local self = setmetatable({}, Panel)
	self.ctx = ctx
	self.opts = opts
	self.name = opts.name or "panel"
	self.radius = opts.radius or 24
	self.bg = opts.bg or ctx.theme.surface
	self.visible = false
	self.animating = false
	self.anim = opts.anim or "auto"
	self.pos = opts.pos
	self.anchor_dir = nil
	self.sx, self.sy = 0, 0
	self.anim_x, self.anim_y = 0, 0
	self.tx, self.ty = 0, 0
	self.last_anchor = nil
	self.mx, self.my = -1, -1
	self._drawing = false
	self._kbd_grabbed = false
	self.user_size = nil
	self.kbd = opts.kbd == true
	self.ui = opts.ui == false and nil or UIfw.new(ctx)
	if opts.input then
		self.input = TI.new(ctx, opts.input)
		self.kbd = true
	end

	if opts.size_fn then
		self.w, self.h = opts.size_fn(ctx)
	else
		self.w, self.h = opts.w or 100, opts.h or 100
	end

	local rc = ctx.L.lbar_popup_create(ctx.Lctx, self.w, self.h, self.radius)
	if rc < 0 then
		return nil, "panel create failed: " .. rc
	end
	self.id = rc
	self.surf = ffi.new("uint32_t[?]", self.w * self.h)

	ctx._panels = ctx._panels or {}
	ctx._panels[self.name] = self
	if ctx.actions then
		ctx.actions["toggle_" .. self.name] = function()
			ctx.toggle_panel(self.name)
		end
	end
	return self
end

function Panel:refit()
	if self.opts.model_fn then
		self.m = self.opts.model_fn(self.ctx, self.user_size)
	end
	if self.user_size then
		if not self.visible and (self.user_size.w ~= self.w or self.user_size.h ~= self.h) then
			return self:resize(self.user_size.w, self.user_size.h)
		end
		return false
	end
	if not self.opts.size_fn or self.visible then
		return false
	end
	local w, h = self.opts.size_fn(self.ctx)
	if w == self.w and h == self.h then
		return false
	end
	return self:resize(w, h)
end

function Panel:resize(w, h)
	if self.visible or (w == self.w and h == self.h) then
		return false
	end
	local rc = self.ctx.L.lbar_popup_resize(self.ctx.Lctx, self.id, w, h)
	if rc ~= 0 then
		return false
	end
	self.w, self.h = w, h
	self.surf = ffi.new("uint32_t[?]", w * h)
	self.mx, self.my = -1, -1
	return true
end

function Panel:live_resize(w, h)
	w = math.max(120, math.floor(w))
	h = math.max(60, math.floor(h))
	if w == self.w and h == self.h then
		return false
	end
	local sx, sy = self.sx, self.sy
	local rc = self.ctx.L.lbar_popup_resize(self.ctx.Lctx, self.id, w, h)
	if rc ~= 0 then
		return false
	end
	self.w, self.h = w, h
	self.surf = ffi.new("uint32_t[?]", w * h)
	self.mx, self.my = -1, -1
	if self.visible then
		self.sx, self.sy = sx, sy
		self.anim_x, self.anim_y = sx, sy
		self.tx, self.ty = sx, sy
		self.animating = false
		self.ctx.L.lbar_popup_move(self.ctx.Lctx, self.id, sx, sy)
		self.ctx.L.lbar_popup_show(self.ctx.Lctx, self.id)
		if self._kbd_grabbed then
			self.ctx.L.lbar_kbd_grab(self.ctx.Lctx, self.id)
		end
		if self.opts.model_fn then
			self.m = self.opts.model_fn(self.ctx, self.user_size)
		end
		self:draw()
	end
	return true
end

function Panel:move_to(x, y)
	local ctx = self.ctx
	x = clamp(math.floor(x), 0, ctx.scr_w - self.w)
	y = clamp(math.floor(y), 0, ctx.scr_h - self.h)
	self.sx, self.sy = x, y
	self.user_pos = { x = x, y = y }
	if self.visible then
		self.anim_x, self.anim_y = x, y
		self.tx, self.ty = x, y
		self.animating = false
		ctx.L.lbar_popup_move(ctx.Lctx, self.id, x, y)
	end
	return true
end

function Panel:move_by(dx, dy)
	return self:move_to(self.sx + dx, self.sy + dy)
end

-- ── surface-like API (parity with core/bar.lua) ──
function Panel:clear(c)
	self.ctx.L.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, c)
end
function Panel:rect(x, y, w, h, c)
	self.ctx.L.surf_fill(self.surf, self.w, self.h, x, y, w, h, c)
end
function Panel:rrect(x, y, w, h, r, c)
	self.ctx.L.surf_rrect_aa(self.surf, self.w, self.h, x, y, w, h, r, c)
end
function Panel:text(x, y, str, fg)
	self.ctx.L.xft_draw_rgba(self.ctx.ft_ctx, self.surf, self.w, self.h, x, y, str, fg)
end

function Panel:header_close(h)
	local ctx, T = self.ctx, self.ctx.theme
	local W = self.w
	local sz = 28
	local r = { x = W - sz - 6, y = math.floor((h - sz) / 2), w = sz, h = sz }
	self.rect_close = r
	local hover = self.mx >= r.x and self.mx < r.x + r.w
		and self.my >= r.y and self.my < r.y + r.h
	self:rrect(r.x, r.y, r.w, r.h, 8, hover and T.surface_hover or T.surface_hi)
	local lh = ctx.get_line_height()
	local hy = math.floor((h - lh) / 2)
	local xs = select(1, ctx.get_text_size("×"))
	self:text(r.x + math.floor((r.w - xs) / 2), hy, "×", T.on_var)
	return r
end

function Panel:draw_header(title, hint, pad)
	pad = pad or 20
	local ctx, T = self.ctx, self.ctx.theme
	local lh = ctx.get_line_height()
	local H = lh + 26
	self:rect(0, 0, self.w, H, T.surface)
	local hy = math.floor((H - lh) / 2)
	self:text(pad, hy, title, T.primary)
	local r = self:header_close(H)
	if hint then
		local hw = select(1, ctx.get_text_size(hint))
		local hx = r.x - 12 - hw
		if hx > pad + select(1, ctx.get_text_size(title)) + 12 then
			self:text(hx, hy, hint, T.hint)
		end
	end
	self:rect(0, H - 1, self.w, 1, T.outline)
	self.header_h = H
	return H
end

function Panel:header_hit(mx, my)
	local r = self.rect_close
	if not r then
		return false
	end
	return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function Panel:layout_free()
	local ctx, w, h = self.ctx, self.w, self.h
	local pcfg = (ctx.config.panels or {})[self.name] or {}
	local pos = self.pos or pcfg.pos or "center"
	local cx = math.floor((ctx.scr_w - w) / 2)
	local cy = math.floor((ctx.scr_h - h) / 2)
	local sx, sy
	if pos == "top" then
		sx, sy = cx, 8
	elseif pos == "bottom" then
		sx, sy = cx, ctx.scr_h - h - 8
	elseif pos == "left" then
		sx, sy = 8, cy
	elseif pos == "right" then
		sx, sy = ctx.scr_w - w - 8, cy
	elseif pos == "top_left" then
		sx, sy = 8, 8
	elseif pos == "top_right" then
		sx, sy = ctx.scr_w - w - 8, 8
	elseif pos == "bottom_left" then
		sx, sy = 8, ctx.scr_h - h - 8
	elseif pos == "bottom_right" then
		sx, sy = ctx.scr_w - w - 8, ctx.scr_h - h - 8
	else
		sx, sy = cx, cy
	end
	return sx, sy
end

function Panel:anim_dir()
	local a = self.anim
	if a == "auto" then
		if self.anchor_dir == "above" then
			a = "slide_up"
		elseif self.anchor_dir == "below" then
			a = "slide_down"
		elseif self.pos and self.pos:find("bottom") then
			a = "slide_up"
		elseif self.pos and self.pos:find("right") then
			a = "slide_left"
		elseif self.pos and self.pos:find("left") then
			a = "slide_right"
		else
			a = "slide_down"
		end
	end
	return a
end

function Panel:show_at(anchor_x, anchor_y, direction)
	local ctx = self.ctx
	self:refit()
	self.anchor_dir = direction or "below"
	self.pos = nil
	local x = math.floor(anchor_x - self.w / 2)
	x = clamp(x, 8, ctx.scr_w - 8 - self.w)
	local y
	if self.anchor_dir == "above" then
		y = anchor_y - self.h
	else
		y = anchor_y
	end
	y = clamp(y, 8, ctx.scr_h - 8 - self.h)
	self.sx, self.sy = x, y
	self.last_anchor = { x = anchor_x, y = anchor_y, dir = self.anchor_dir }
	self:_begin_show()
end

function Panel:show_xy(x, y)
	local ctx = self.ctx
	self:refit()
	self.anchor_dir = nil
	self.pos = nil
	self.last_anchor = nil
	self.sx = clamp(math.floor(x), 0, ctx.scr_w - self.w)
	self.sy = clamp(math.floor(y), 0, ctx.scr_h - self.h)
	self:_begin_show()
end

function Panel:show()
	local ctx = self.ctx
	self:refit()
	self.anchor_dir = nil
	self.pos = self.opts.pos
	if self.user_pos then
		self.sx = clamp(self.user_pos.x, 0, ctx.scr_w - self.w)
		self.sy = clamp(self.user_pos.y, 0, ctx.scr_h - self.h)
	else
		self.sx, self.sy = self:layout_free()
	end
	self:_begin_show()
end

function Panel:_begin_show()
	local ctx = self.ctx
	local L = ctx.L
	if ctx._panel_closing and ctx._panel_closing ~= self then
		ctx._panel_closing:_finish_hide()
	end
	ctx._panel_closing = nil
	self.visible = true
	self.animating = false
	self.anim_x, self.anim_y = self.sx, self.sy
	self.tx, self.ty = self.sx, self.sy
	local a = self:anim_dir()
	if a ~= "none" then
		local off = 40
		if a == "slide_down" then
			self.anim_y = self.sy - off
		elseif a == "slide_up" then
			self.anim_y = self.sy + off
		elseif a == "slide_left" then
			self.anim_x = self.sx + off
		elseif a == "slide_right" then
			self.anim_x = self.sx - off
		end
		self.animating = true
	end
	L.lbar_popup_move(ctx.Lctx, self.id, math.floor(self.anim_x), math.floor(self.anim_y))
	L.lbar_popup_show(ctx.Lctx, self.id)
	if self.opts.ptr_grab ~= false then
		L.lbar_ptr_grab(ctx.Lctx, self.id)
	end
	ctx.popup_visible = true
	if self.opts.on_show then
		self.opts.on_show(self)
	end
	self:draw()
end

function Panel:_kbd_sync()
	local want = false
	if self.input and self.input.focused then
		want = true
	elseif self.ui and self.ui.any_focus and self.ui:any_focus() then
		want = true
	end
	if want and not self._kbd_grabbed then
		self.ctx.L.lbar_kbd_grab(self.ctx.Lctx, self.id)
		self._kbd_grabbed = true
	elseif not want and self._kbd_grabbed then
		self.ctx.L.lbar_kbd_ungrab(self.ctx.Lctx)
		self._kbd_grabbed = false
	end
end

function Panel:_finish_hide()
	local ctx = self.ctx
	self.animating = false
	ctx._panel_closing = nil
	self.anim_x, self.anim_y = self.sx, self.sy
	if self.input then
		self.input:blur()
	end
	if self.ui and self.ui.blur_input then
		self.ui:blur_input()
	end
	if self._kbd_grabbed then
		self._kbd_grabbed = false
		ctx.L.lbar_kbd_ungrab(ctx.Lctx)
	end
	if self.opts.ptr_grab ~= false then
		ctx.L.lbar_ptr_ungrab(ctx.Lctx)
	end
	ctx.L.lbar_popup_hide(ctx.Lctx, self.id)
	if self.opts.on_hide then
		self.opts.on_hide(self)
	end
end

function Panel:hide(instant)
	local ctx = self.ctx
	if not self.visible then
		return
	end
	self.visible = false
	ctx.popup_visible = false
	if ctx.active_panel == self then
		ctx.active_panel = nil
	end
	local a = self:anim_dir()
	if instant or a == "none" then
		self:_finish_hide()
		return
	end
	self.animating = true
	ctx._panel_closing = self
	local off = 40
	if a == "slide_down" then
		self.tx, self.ty = self.sx, self.sy - off
	elseif a == "slide_up" then
		self.tx, self.ty = self.sx, self.sy + off
	elseif a == "slide_left" then
		self.tx, self.ty = self.sx + off, self.sy
	else
		self.tx, self.ty = self.sx - off, self.sy
	end
end

function Panel:tick(dt)
	if self.input and self.visible then
		local prev = self.input.blink_on
		self.input:tick(dt)
		if prev ~= self.input.blink_on then
			self:draw()
		end
	end
	if not self.animating then
		return
	end
	local k = 1 - math.exp(-dt / 55)
	local function step(a, t)
		local d = t - a
		if math.abs(d) < 1.5 then
			return t
		end
		return a + d * k
	end
	self.anim_x = step(self.anim_x, self.tx)
	self.anim_y = step(self.anim_y, self.ty)
	self.ctx.L.lbar_popup_move(self.ctx.Lctx, self.id, math.floor(self.anim_x), math.floor(self.anim_y))
	if self.anim_x == self.tx and self.anim_y == self.ty then
		if self.visible then
			self.animating = false
		else
			self:_finish_hide()
		end
	end
end

function Panel:draw()
	if self._drawing then
		return
	end
	self._drawing = true
	local L = self.ctx.L
	L.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, self.bg)
	if self.ui then
		self.ui:begin(self)
	end
	if self.opts.draw then
		local ok, err = pcall(self.opts.draw, self, self)
		if not ok then
			self.ctx.log("panel %s draw error: %s", self.name, tostring(err))
		end
	end
	if self.ui then
		self.ui:finish()
	end
	L.lbar_popup_flush(self.ctx.Lctx, self.id, self.surf)
	self._drawing = false
end

function Panel:on_motion(mx, my, rx, ry)
	if self.opts.ptr_grab ~= false
		and (mx < 0 or my < 0 or mx >= self.w or my >= self.h) then
		if self.mx ~= -1 or self.my ~= -1 then
			self.mx, self.my = -1, -1
			if self.ui then
				self.ui:move(-1, -1)
			end
			self:draw()
		end
		return
	end
	self.mx, self.my = mx, my
	if self.ui then
		self.ui:move(mx, my)
	end
	if self.input then
		self.input:on_mouse_move(mx, my)
	end
	if self.opts.on_motion then
		self.opts.on_motion(self, mx, my, rx, ry)
	end
	self:draw()
end

function Panel:on_press(btn, mx, my, rx, ry)
	self.mx, self.my = mx, my
	if self.ui and btn == 1 then
		self.ui:press(mx, my)
	end
	if self.input and btn == 1 then
		if not self.input:on_mouse_press(mx, my, false) then
			self.input:blur()
		end
	end
	if self.opts.on_press then
		self.opts.on_press(self, mx, my, btn, rx, ry)
	end
	self:draw()
	self:_kbd_sync()
	return true
end

function Panel:on_release(btn, mx, my, rx, ry)
	self.mx, self.my = mx, my
	if self.ui and btn == 1 then
		self.ui:release(mx, my)
	end
	if self.input then
		self.input:on_mouse_release()
	end
	if self.opts.on_release then
		self.opts.on_release(self, mx, my, btn, rx, ry)
	end
	self:draw()
	self:_kbd_sync()
	return true
end

function Panel:on_key(keycode, state)
	local sym, text, ctrl, shift = key_translate(self.ctx, keycode, state)
	if self.input and self.input.focused then
		if self.input:on_key(sym, ctrl, shift, text) then
			self:draw()
			return true
		end
	end
	if not self.opts.on_key then
		return false
	end
	local ok, handled = pcall(self.opts.on_key, self, sym, text, ctrl, shift, state)
	if ok and handled then
		self:draw()
	end
	return ok and handled or false
end

function Panel:blur_input()
	if self.input then
		self.input:blur()
	end
	if self.ui and self.ui.blur_input then
		self.ui:blur_input()
	end
	self:_kbd_sync()
end

function Panel:destroy()
	if self.visible then
		self:hide(true)
	end
	self.surf = nil
end

return M
