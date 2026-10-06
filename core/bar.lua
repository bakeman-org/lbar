-- core/bar.lua
local M = {}
local ffi = require("ffi")

local Bar = {}
Bar.__index = Bar

function M.new(ctx, cfg)
	local self = setmetatable({}, Bar)
	self.ctx = ctx
	self.cfg = cfg
	self.plugins = {}
	self.hover_plugin = nil
	self.needs_redraw = true

	self.h = cfg.height or 30
	self.pos = cfg.position or "top"
	self.w = ctx.scr_w
	self.x = 0
	self.y = (self.pos == "top") and 0 or (ctx.scr_h - self.h)
	self.padding = cfg.padding or 12
	self.gap = cfg.gap or 10

	local rc = ctx.L.lbar_bar_create(ctx.Lctx, self.h, self.pos == "top" and 0 or 1)
	if rc ~= 0 then
		return nil, "lbar_bar_create failed: " .. rc
	end

	self.w = ctx.L.lbar_bar_width(ctx.Lctx)
	self.h = ctx.L.lbar_bar_height(ctx.Lctx)
	self.surf = ffi.new("uint32_t[?]", self.w * self.h)
	return self
end

-- ── Surface-like methods (so plugins can call s:text / s:rect / s:rrect) ──
function Bar:clear(c)
	self.ctx.L.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, c)
end
function Bar:rect(x, y, w, h, c)
	self.ctx.L.surf_fill(self.surf, self.w, self.h, x, y, w, h, c)
end
function Bar:rrect(x, y, w, h, r, c)
	self.ctx.L.surf_rrect_aa(self.surf, self.w, self.h, x, y, w, h, r, c)
end
function Bar:text(x, y, str, fg)
	self.ctx.L.xft_draw_rgba(self.ctx.ft_ctx, self.surf, self.w, self.h, x, y, str, fg)
end

function Bar:add_plugin(name, mod)
	if mod.init then
		local ok, err = pcall(mod.init, self.ctx)
		if not ok then
			self.ctx.log("plugin %s init failed: %s", name, tostring(err))
			return
		end
	end
	self.plugins[#self.plugins + 1] = { name = name, mod = mod, x = 0, w = 0 }
end

function Bar:layout()
	local x = self.padding
	for _, p in ipairs(self.plugins) do
		local w = 0
		if p.mod.width then
			local ok, r = pcall(p.mod.width, self.ctx)
			if ok and type(r) == "number" and r > 0 then
				w = r
			end
		end
		p.x = x
		p.w = w
		x = x + w + self.gap
	end
end

function Bar:sync_size()
	local nw = self.ctx.L.lbar_bar_width(self.ctx.Lctx)
	local nh = self.ctx.L.lbar_bar_height(self.ctx.Lctx)
	if nw ~= self.w or nh ~= self.h then
		self.w, self.h = nw, nh
		self.surf = ffi.new("uint32_t[?]", self.w * self.h)
		self.ctx.scr_w = self.w
		self.needs_redraw = true
	end
end

function Bar:draw()
	self:sync_size()
	local FT = self.ctx.L
	FT.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, self.cfg.bar_bg or 0x1c1c1e)
	self:layout()

	for _, p in ipairs(self.plugins) do
		if p.mod.draw and p.w > 0 then
			local is_hover = (self.hover_plugin == p)
			local is_active = (self.ctx.active_plugin_name == p.name and self.ctx.popup_visible)
			if is_hover or is_active then
				FT.surf_rrect_aa(self.surf, self.w, self.h, p.x - 6, 4, p.w + 12, self.h - 8, 6, 0x2a2a2d)
			end
			-- pass the Bar itself — it exposes :text/:rect/:rrect/:clear
			local ok, err = pcall(p.mod.draw, self.ctx, self, p.x, 0, p.w, self.h)
			if not ok then
				self.ctx.log("plugin %s draw: %s", p.name, tostring(err))
			end
		end
	end
	self.ctx.L.lbar_bar_flush(self.ctx.Lctx, self.surf)
	self.needs_redraw = false
end

function Bar:tick(dt)
	self:sync_size()
	for _, p in ipairs(self.plugins) do
		if p.mod.tick then
			local ok, err = pcall(p.mod.tick, self.ctx, dt)
			if not ok then
				self.ctx.log("plugin %s tick: %s", p.name, tostring(err))
			end
		end
	end
	if self.needs_redraw then
		self:draw()
	end
end

function Bar:plugin_at(mx, my)
	for _, p in ipairs(self.plugins) do
		if mx >= p.x and mx < p.x + p.w then
			return p
		end
	end
	return nil
end

function Bar:on_motion(mx, my)
	local p = self:plugin_at(mx, my)
	if p ~= self.hover_plugin then
		self.hover_plugin = p
		self.needs_redraw = true
	end
end

function Bar:on_click(btn, mx, my)
	local p = self:plugin_at(mx, my)
	if p and p.mod.on_click then
		local ok, err = pcall(p.mod.on_click, self.ctx, btn, mx - p.x, my, p.x, p.w)
		if not ok then
			self.ctx.log("plugin %s on_click: %s", p.name, tostring(err))
		end
	end
end

function Bar:destroy()
	for _, p in ipairs(self.plugins) do
		if p.mod.shutdown then
			pcall(p.mod.shutdown)
		end
		package.loaded["plugins." .. p.name] = nil
	end
	self.plugins = {}
end

return M
