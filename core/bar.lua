-- core/bar.lua — MD3 floating bar
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

	self.margin = tonumber(cfg.bar_margin) or 0
	local lh = ctx.get_line_height()
	local h_cfg = tonumber(cfg.height)
	if cfg.height == nil or cfg.height == "auto" or h_cfg == nil then
		self.h = lh + 18
	else
		self.h = h_cfg
	end
	self.pos = cfg.position or "top"
	self.w = ctx.scr_w - 2 * self.margin
	self.x = self.margin
	self.y = (self.pos == "top") and self.margin or (ctx.scr_h - self.h - self.margin)
	self.padding = tonumber(cfg.padding) or 16
	self.gap = tonumber(cfg.gap) or 6

	local rc = ctx.L.lbar_bar_create(ctx.Lctx, self.h, self.pos == "top" and 0 or 1, self.margin)
	if rc ~= 0 then
		return nil, "lbar_bar_create failed: " .. rc
	end

	self.w = ctx.L.lbar_bar_width(ctx.Lctx)
	self.h = ctx.L.lbar_bar_height(ctx.Lctx)
	self.surf = ffi.new("uint32_t[?]", self.w * self.h)
	return self
end

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
	local total = 0
	for _, p in ipairs(self.plugins) do
		local w = 0
		if p.mod.width then
			local ok, r = pcall(p.mod.width, self.ctx)
			if ok and type(r) == "number" and r > 0 then
				w = r
			end
		end
		p.w = w
		total = total + w
	end
	local n = #self.plugins
	local gap = self.gap
	if n > 1 then
		local avail = self.w - self.padding * 2
		local fit = math.floor((avail - total) / (n - 1))
		gap = math.max(2, math.min(self.gap, fit))
	end
	local x = self.padding
	for _, p in ipairs(self.plugins) do
		p.x = x
		x = x + p.w + gap
	end
	-- overflow: squeeze so every item stays inside the bar
	local max_end = self.w - self.padding
	if n > 1 and x - gap > max_end then
		gap = math.max(0, math.floor((max_end - self.padding - total) / (n - 1)))
		x = self.padding
		for _, p in ipairs(self.plugins) do
			p.x = x
			x = x + p.w + gap
		end
		if x - gap > max_end and total > 0 then
			local scale = (max_end - self.padding) / total
			local acc = 0
			for _, p in ipairs(self.plugins) do
				p.x = self.padding + math.floor(acc)
				acc = acc + p.w * scale
			end
			self.ctx.log("bar: %d items overflow, squeezed to fit", n)
		end
	end
end

function Bar:sync_size()
	local nw = self.ctx.L.lbar_bar_width(self.ctx.Lctx)
	local nh = self.ctx.L.lbar_bar_height(self.ctx.Lctx)
	if nw ~= self.w or nh ~= self.h then
		self.w, self.h = nw, nh
		self.surf = ffi.new("uint32_t[?]", self.w * self.h)
		self.needs_redraw = true
	end
end

function Bar:draw()
	self:sync_size()
	local FT = self.ctx.L
	local T = self.ctx.theme
	FT.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, 0x00000000)
	if self.margin > 0 then
		FT.surf_rrect_aa(self.surf, self.w, self.h, 0, 0, self.w, self.h, self.h / 2, T.surface)
	else
		FT.surf_fill(self.surf, self.w, self.h, 0, 0, self.w, self.h, T.surface)
	end
	self:layout()

	for _, p in ipairs(self.plugins) do
		if p.mod.draw and p.w > 0 then
			local is_hover = (self.hover_plugin == p)
			local is_active = (self.ctx.active_plugin_name == p.name and self.ctx.popup_visible)
			if is_hover or is_active then
				FT.surf_rrect_aa(self.surf, self.w, self.h, p.x - 6, 4, p.w + 12, self.h - 8, (self.h - 8) / 2, T.secondary_ctr)
			end
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
		local ok, err = pcall(p.mod.on_click, self.ctx, btn, mx - p.x, my, p.x + self.margin, p.w)
		if not ok then
			self.ctx.log("plugin %s on_click: %s", p.name, tostring(err))
		end
	elseif self.ctx.popup_visible then
		self.ctx.close_panels()
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
