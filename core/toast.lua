-- core/toast.lua — toast notifications (ported from xpet, popup-slot backed)
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local utf8_truncate = Util.utf8_truncate

local Toast = {}
Toast.__index = Toast

local PAD_X = 20
local PAD_Y = 14
local ACCENT_W = 4
local RADIUS = 16
local DEFAULT_DURATION = 3000
local MAX_CHARS = 512
local MAX_LINE_W_RATIO = 0.72
local MAX_LINES = 8

local STYLE_KEYS = {
	info = "primary",
	success = "good",
	warning = "warn",
	error = "crit",
	plain = nil,
}

local function resolve_style(ctx, s)
	local T = ctx.theme
	local key = type(s) == "string" and (STYLE_KEYS[s] or STYLE_KEYS.info) or nil
	return {
		bg = T.surface_hi,
		fg = T.on_surface,
		accent = key and T[key] or nil,
	}
end

local function wrap_text(ctx, text, max_w, max_lines)
	if select(1, ctx.get_text_size(text)) <= max_w then
		return text, 1
	end
	local lines = {}
	local buf = {}
	local buf_w = 0
	local i = 1
	local L = #text
	local line_count = 0
	while i <= L do
		local step = Util.utf8_step(text, i)
		local ch = text:sub(i, i + step - 1)
		if ch == "\n" then
			lines[#lines + 1] = table.concat(buf)
			buf = {}
			buf_w = 0
			line_count = line_count + 1
			if max_lines and line_count >= max_lines then
				return table.concat(lines, "\n"), line_count
			end
		else
			local cw = select(1, ctx.get_text_size(ch))
			if buf_w + cw > max_w and #buf > 0 then
				lines[#lines + 1] = table.concat(buf)
				buf = { ch }
				buf_w = cw
				line_count = line_count + 1
				if max_lines and line_count >= max_lines then
					if i < L then
						buf[#buf + 1] = "…"
					end
					lines[#lines + 1] = table.concat(buf)
					return table.concat(lines, "\n"), line_count
				end
			else
				buf[#buf + 1] = ch
				buf_w = buf_w + cw
			end
		end
		i = i + step
	end
	if #buf > 0 then
		lines[#lines + 1] = table.concat(buf)
		line_count = line_count + 1
	end
	return table.concat(lines, "\n"), line_count
end

function M.new(ctx)
	local self = setmetatable({}, Toast)
	self.ctx = ctx
	self.panel = nil
	self.style = nil
	self.text = nil
	self.deadline = 0
	self.visible = false
	self.anchor = nil
	self.x, self.y = 0, 0
	self.w, self.h = 0, 0
	return self
end

function Toast:_ensure_panel(w, h)
	if not self.panel then
		local toast = self
		self.panel = Panel.new(self.ctx, {
			name = "toast",
			w = w,
			h = h,
			radius = RADIUS,
			anim = "none",
			ptr_grab = false,
			draw = function(p)
				local st = toast.style
				if not st then
					return
				end
				p.bg = st.bg
				p:clear(st.bg)
				if st.accent then
					p:rrect(0, 0, ACCENT_W, p.h, ACCENT_W / 2, st.accent)
				end
				p:text(PAD_X + (st.accent and ACCENT_W or 0), PAD_Y, toast.text or "", st.fg)
			end,
		})
	else
		if self.panel.w ~= w or self.panel.h ~= h then
			self.panel:live_resize(w, h)
		end
	end
	return self.panel
end

function Toast:_prepare(text, style)
	local max_w = math.floor(self.ctx.scr_w * MAX_LINE_W_RATIO)
	text = utf8_truncate(text, MAX_CHARS)
	text = wrap_text(self.ctx, text, max_w, MAX_LINES)
	local tw, th = self.ctx.get_text_size(text)
	local pad_l = PAD_X + (style.accent and ACCENT_W or 0)
	return text, tw + pad_l + PAD_X, th + PAD_Y * 2
end

function Toast:show(text, opts)
	if not text or text == "" then
		return
	end
	opts = opts or {}
	local style = resolve_style(self.ctx, opts.style)
	local prepared, bw, bh = self:_prepare(text, style)

	local p = self:_ensure_panel(bw, bh)
	self.text = prepared
	self.style = style
	self.w, self.h = bw, bh
	self.deadline = opts.duration or DEFAULT_DURATION
	self.anchor = opts.anchor

	local tx, ty
	if self.anchor then
		tx, ty = self.anchor({ w = bw, h = bh })
	else
		tx = math.floor((self.ctx.scr_w - bw) / 2)
		ty = math.floor(self.ctx.scr_h * 0.82)
	end
	tx = math.max(8, math.min(self.ctx.scr_w - bw - 8, tx))
	ty = math.max(8, math.min(self.ctx.scr_h - bh - 8, ty))
	p:show_xy(tx, ty)
	self.x, self.y = tx, ty
	self.visible = true
end

function Toast:tick(dt_ms)
	if not self.visible then
		return
	end
	self.deadline = self.deadline - dt_ms
	if self.deadline <= 0 then
		self:hide()
	end
end

function Toast:hide()
	if self.panel then
		self.panel:hide(true)
	end
	self.visible = false
	self.deadline = 0
	self.anchor = nil
end

function Toast:invalidate()
	self.panel = nil
	self.visible = false
	self.text = nil
	self.style = nil
	self.deadline = 0
	self.anchor = nil
end

function Toast:clear()
	self:hide()
end

return M
