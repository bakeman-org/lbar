-- core/ui.lua — MD3 widget framework (ported from xpet)
local M = {}
local UI = {}
UI.__index = UI

function M.new(ctx)
	local self = setmetatable({}, UI)
	self.ctx = ctx
	self.surf = nil
	self.mx, self.my = -1, -1
	self.mdown = false
	self.mrelease = nil
	self.active_id = nil
	self._focus_id = nil
	return self
end

function UI:begin(surf)
	self.surf = surf
	if not self.mdown then
		self.active_id = nil
	end
end

function UI:finish()
	self.mrelease = nil
end

function UI:press(mx, my)
	self.mx, self.my = mx, my
	self.mdown = true
end

function UI:move(mx, my)
	self.mx, self.my = mx, my
end

function UI:release(mx, my)
	self.mdown = false
	self.mrelease = { x = mx, y = my }
end

function UI:leave()
	self.mx, self.my = -1, -1
	self.mdown = false
end

function UI:hover(x, y, w, h)
	return self.mx >= x and self.mx < x + w and self.my >= y and self.my < y + h
end

function UI:clicked(x, y, w, h)
	if not self.mrelease then
		return false
	end
	local r = self.mrelease
	return r.x >= x and r.x < x + w and r.y >= y and r.y < y + h
end

function UI:line_h(pad)
	return self.ctx.get_line_height() + (pad or 6)
end

function UI:label(x, y_top, text, color, bg)
	local T = self.ctx.theme
	if bg then
		self.surf:rect(
			x - 2,
			y_top - 2,
			select(1, self.ctx.get_text_size(text)) + 4,
			self.ctx.get_line_height() + 4,
			bg
		)
	end
	self.surf:text(x, y_top, text, color or T.on_surface)
end

function UI:label_c(x, y_top, w, text, color, bg)
	local T = self.ctx.theme
	if bg then
		self.surf:rect(x, y_top - 2, w, self.ctx.get_line_height() + 4, bg)
	end
	local tw = select(1, self.ctx.get_text_size(text))
	self.surf:text(math.floor(x + w / 2 - tw / 2), y_top, text, color or T.on_surface)
end

function UI:id_button(id, x, y, w, h, text, opts)
	opts = opts or {}
	local T = self.ctx.theme
	local hover = self:hover(x, y, w, h)
	local bg, fg
	if opts.filled then
		bg = hover and T.primary_hi or (opts.color or T.primary)
		fg = T.on_primary
	elseif opts.tonal then
		bg = hover and T.surface_hover or (opts.bg or T.secondary_ctr)
		fg = opts.color or T.primary
	else
		bg = hover and T.surface_hover or (opts.bg or T.surface_hi)
		fg = opts.color or T.on_surface
	end
	local r = opts.radius or math.floor(h / 2)
	self.surf:rrect(x, y, w, h, r, bg)
	local lh = self.ctx.get_line_height()
	local tw = select(1, self.ctx.get_text_size(text))
	self.surf:text(math.floor(x + w / 2 - tw / 2), math.floor(y + h / 2 - lh / 2), text, fg)
	return self:clicked(x, y, w, h)
end

function UI:button(x, y, w, h, text, opts)
	return self:id_button("btn:" .. x .. ":" .. y .. ":" .. text, x, y, w, h, text, opts)
end

function UI:slider(id, x, y, w, value, opts)
	opts = opts or {}
	local T = self.ctx.theme
	local min_v, max_v = opts.min or 0, opts.max or 1
	local norm = math.max(0, math.min(1, (value - min_v) / (max_v - min_v)))
	local hit_r = opts.hit_r or 14

	local over = self.mx >= x - hit_r
		and self.mx <= x + w + hit_r
		and self.my >= y - hit_r
		and self.my <= y + hit_r
	if self.mdown and over and not self.active_id then
		self.active_id = id
	end

	local new_v = value
	if self.active_id == id then
		local px = math.max(x, math.min(x + w, self.mx))
		new_v = min_v + (px - x) / w * (max_v - min_v)
	end

	self.surf:rrect(x, y, w, 6, 3, opts.track or T.surface_hi)
	local fw = math.max(6, math.floor(w * norm))
	self.surf:rrect(x, y, fw, 6, 3, opts.color or T.primary)
	local hx = x + math.floor(w * norm)
	self.surf:rrect(hx - 8, y - 5, 16, 16, 8, opts.handle or T.on_surface)

	return new_v, new_v ~= value
end

-- Material-style pill switch: fully rounded track, circular thumb that
-- slides off→on. Track takes theme.primary when on / a dim surface with a
-- hairline outline when off; the thumb grows when on and while pressed.
-- Works at any w >= h and keeps the (value, changed) return pair.
function UI:toggle(id, x, y, w, h, value, opts)
	opts = opts or {}
	local T = self.ctx.theme
	local over = self:hover(x, y, w, h)
	local pressed = over and self.mdown
	local track = value and (opts.on_color or T.primary) or (opts.off_color or T.surface_hi)
	if value then
		self.surf:rrect(x, y, w, h, h / 2, track)
	else
		self.surf:rrect(x, y, w, h, h / 2, T.outline)
		self.surf:rrect(x + 1, y + 1, w - 2, h - 2, h / 2 - 1, track)
	end
	local d = h - 10 + (value and 3 or 0) + (pressed and 2 or 0)
	d = math.max(8, math.min(d, h - 4, w - 8))
	local kx = value and (x + w - d - (h - d) / 2) or (x + (h - d) / 2)
	local knob = opts.knob or (value and T.on_primary or T.on_var)
	self.surf:rrect(kx, y + (h - d) / 2, d, d, d / 2, knob)
	if self:clicked(x, y, w, h) then
		return not value, true
	end
	return value, false
end

function UI:card(x, y, w, h, opts)
	opts = opts or {}
	local T = self.ctx.theme
	local r = opts.radius or 16
	self.surf:rrect(x, y, w, h, r, opts.bg or T.surface_hi)
end

-- MIUI segmented control: pill container (surface_hi) with a raised active
-- segment (bg pill, primary text); inactive segments use hint text.
-- items = { label, ... }; returns the 1-based index clicked this frame (0 = none)
function UI:segmented(x, y, w, h, items, active_idx)
	local T = self.ctx.theme
	local lh = self.ctx.get_line_height()
	self.surf:rrect(x, y, w, h, math.floor(h / 2), T.surface_hi)
	local n = #items
	if n == 0 then
		return 0
	end
	local seg_w = math.floor(w / n)
	local clicked = 0
	for i = 1, n do
		local sx = x + (i - 1) * seg_w
		local sw = i == n and (w - seg_w * (n - 1)) or seg_w
		local active = i == active_idx
		if active then
			self.surf:rrect(sx + 3, y + 3, sw - 6, h - 6, math.floor((h - 6) / 2), T.bg)
		end
		local text = items[i]
		local tw = select(1, self.ctx.get_text_size(text))
		self.surf:text(math.floor(sx + (sw - tw) / 2), math.floor(y + (h - lh) / 2), text,
			active and T.primary or T.hint)
		if clicked == 0 and self:clicked(sx, y, sw, h) then
			clicked = i
		end
	end
	return clicked
end

function UI:divider(x, y, w, color)
	self.surf:rect(x, y, w, 1, color or self.ctx.theme.outline)
end

function UI:scrollbar(id, x, y, w, h, offset, max_offset, opts)
	opts = opts or {}
	local T = self.ctx.theme
	self.surf:rrect(x, y, w, h, math.floor(w / 2), opts.track or T.surface)
	if max_offset <= 0 then
		return math.max(0, offset), false
	end
	local th = math.max(24, math.floor(h * h / (h + max_offset)))
	if h - th < 1 then
		return math.max(0, offset), false
	end
	local ty = y + math.floor((h - th) * math.max(0, offset) / max_offset)
	local over = self.mx >= x - 4 and self.mx <= x + w + 4
		and self.my >= y and self.my <= y + h
	if self.mdown and over and self.active_id ~= id then
		self.active_id = id
		self._sb_grab = self.my - ty
	end
	local dragging = self.active_id == id and self.mdown
	if dragging and self._sb_grab then
		local nty = self.my - self._sb_grab
		local noff = math.floor((nty - y) / (h - th) * max_offset + 0.5)
		offset = math.max(0, math.min(max_offset, noff))
	end
	self.surf:rrect(x, ty, w, th, math.floor(w / 2), opts.color or T.outline)
	return offset, dragging
end

function UI:progress(x, y, w, h, pct, color, track)
	local T = self.ctx.theme
	track = track or T.surface_hover
	self.surf:rrect(x, y, w, h, h / 2, track)
	if pct > 0 then
		local fw = math.max(h, math.floor(w * math.min(100, pct) / 100))
		self.surf:rrect(x, y, fw, h, h / 2, color or T.primary)
	end
end

function UI:focus_input(id)
	self._focus_id = id
end

function UI:blur_input()
	self._focus_id = nil
end

function UI:has_focus(id)
	return self._focus_id == id
end

function UI:any_focus()
	return self._focus_id ~= nil
end

function UI:text_field(id, x, y, w, h, value, opts)
	opts = opts or {}
	local T = self.ctx.theme
	local hover = self:hover(x, y, w, h)
	local focused = self:has_focus(id)

	local clicked = self:clicked(x, y, w, h)
	if clicked then
		self._focus_id = id
		focused = true
	end

	local bg = focused and T.surface_hi or (hover and T.surface_hover or T.surface)
	local r = opts.radius or math.floor(h / 2)
	self.surf:rrect(x, y, w, h, r, bg)

	if focused then
		self.surf:rect(x + r, y, w - 2 * r, 1, T.primary)
		self.surf:rect(x + r, y + h - 1, w - 2 * r, 1, T.primary)
	end

	local lh = self.ctx.get_line_height()
	local ty = y + math.floor((h - lh) / 2)
	local text = value or ""
	local fg
	if text == "" and opts.placeholder then
		text = opts.placeholder
		fg = T.hint
	else
		fg = focused and T.on_surface or T.on_var
	end
	if focused then
		text = text .. "▏"
	end

	self.surf:text(x + 12, ty, text, fg)
	return clicked
end

return M
