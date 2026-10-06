local M = {}
local ffi = require("ffi")

local Popup = {}
Popup.__index = Popup

function M.new(ctx, opts)
	local self = setmetatable({}, Popup)
	self.ctx = ctx
	self.opts = opts or {}
	self.w = opts.w
	self.h = opts.h
	self.radius = opts.radius or 12
	self.bg = opts.bg or 0x1c1c1e
	self.visible = false
	self.mx, self.my = -1, -1
	self._drawing = false

	local rc = ctx.L.lbar_popup_create(ctx.Lctx, self.w, self.h, self.radius)
	if rc ~= 0 then
		return nil, "popup create failed: " .. rc
	end
	self.surf = ffi.new("uint32_t[?]", self.w * self.h)
	return self
end

function Popup:show(anchor_x, anchor_y, direction)
	local ctx = self.ctx
	local x = math.floor(anchor_x - self.w / 2)
	if x < 8 then
		x = 8
	end
	if x + self.w > ctx.scr_w - 8 then
		x = ctx.scr_w - 8 - self.w
	end

	local y
	if direction == "above" then
		y = anchor_y - self.h
	else
		y = anchor_y
	end
	if y < 8 then
		y = 8
	end
	if y + self.h > ctx.scr_h - 8 then
		y = ctx.scr_h - 8 - self.h
	end

	ctx.L.lbar_popup_move(ctx.Lctx, x, y)
	ctx.L.lbar_popup_show(ctx.Lctx)
	self.visible = true
	ctx.popup_visible = true
	if self.opts.on_show then
		self.opts.on_show(self)
	end
	self:draw()
end

function Popup:hide()
	if not self.visible then
		return
	end
	self.visible = false
	self.ctx.popup_visible = false
	self.ctx.L.lbar_popup_hide(self.ctx.Lctx)
	if self.opts.on_hide then
		self.opts.on_hide(self)
	end
end

function Popup:draw()
	if self._drawing then
		return
	end
	self._drawing = true
	local L = self.ctx.L
	L.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, self.bg)
	if self.opts.draw then
		local ok, err = pcall(self.opts.draw, self, self)
		if not ok then
			self.ctx.log("popup draw error: %s", tostring(err))
		end
	end
	L.lbar_popup_flush(self.ctx.Lctx, self.surf)
	self._drawing = false
end

function Popup:on_motion(mx, my)
	if mx ~= self.mx or my ~= self.my then
		self.mx, self.my = mx, my
		self:draw()
	end
end

function Popup:on_press(btn, mx, my)
	self.mx, self.my = mx, my
	if self.opts.on_press then
		local consumed = self.opts.on_press(self, mx, my, btn)
		self:draw()
		return consumed ~= false
	end
	self:draw()
	return true
end

function Popup:destroy()
	if self.visible then
		self:hide()
	end
	self.surf = nil
end

return M
