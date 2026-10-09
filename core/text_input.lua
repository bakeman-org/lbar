-- core/text_input.lua — full text editor widget (ported from xpet)
local M = {}
local Clipboard = require("core.clipboard")
local I = require("core.i18n")
local Util = require("core.util")

local TI = {}
TI.__index = TI

local PASTE_MAX = 512

local utf8_step = Util.utf8_step
local utf8_prev = Util.utf8_prev
local utf8_next = Util.utf8_next

-- truncate to n bytes without splitting a UTF-8 codepoint
local function utf8_safe_cut(s, n)
	if n >= #s then
		return s
	end
	while n > 0 do
		local b = s:byte(n + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		n = n - 1
	end
	return s:sub(1, n)
end

local function splice(s, a, b, insert)
	return s:sub(1, a - 1) .. (insert or "") .. s:sub(b)
end

local function prev_word(s, i)
	if i <= 1 then
		return 1
	end
	local j = i - 1
	while j >= 1 and s:byte(j) == 0x20 do
		j = j - 1
	end
	while j >= 1 and s:byte(j) ~= 0x20 do
		j = utf8_prev(s, j + 1) - 1
	end
	return j + 1
end

local function next_word(s, i)
	local n = #s
	if i > n then
		return n + 1
	end
	local j = i
	while j <= n and s:byte(j) ~= 0x20 do
		j = utf8_next(s, j)
	end
	while j <= n and s:byte(j) == 0x20 do
		j = j + 1
	end
	return j
end

function M.new(ctx, opts)
	opts = opts or {}
	local self = setmetatable({}, TI)
	self.ctx = ctx
	self.value = opts.value or ""
	self.cursor = #self.value + 1
	self.anchor = nil
	self.scroll_x = 0
	self.focused = false
	self.blink_on = true
	self.blink_t = 0
	self.blink_ms = 530

	-- multi-line auto-fit: text wraps at the input width and the widget
	-- grows downward (up to max_lines visual rows); opts.wrap = false
	-- restores the classic clipped single-line behaviour
	self.wrap = opts.wrap ~= false
	self.max_lines = opts.max_lines or 3
	self._cache_val = nil
	self.scroll_line = 0
	self.goal_x = nil
	self._cur_row = nil
	self._lines = nil
	self._lines_w = nil
	self._base_h = nil
	self._on_grow = opts.on_grow

	self.x, self.y, self.w, self.h = 0, 0, 0, 0
	self.icon = opts.icon ~= false
	self.clear_btn = opts.clear_btn ~= false
	self.pad_l = opts.pad_l or (self.icon and 30 or 12)
	self.pad_r = opts.pad_r or (self.clear_btn and 26 or 12)
	self.placeholder = opts.placeholder
	self.font_lh = ctx.get_line_height()
	self.max_bytes = opts.max_bytes or 8192

	self.on_change = opts.on_change
	self.on_submit = opts.on_submit
	self.on_cancel = opts.on_cancel
	self.on_limit = opts.on_limit

	self.dragging = false
	self.drag_origin = nil

	self.preedit = nil

	self._paste_tmp = nil
	self._paste_pending = false

	self._click_count = 0
	self._last_click_t = 0
	self._last_click_x = 0
	self._last_click_y = 0

	-- android-style editing affordances: long-press word select, draggable
	-- cursor/selection handles and the floating copy/cut/paste toolbar
	self.notify = ctx.notify
	self._toolbar = false
	self._tb = nil -- last drawn toolbar layout (hit rects)
	self._sel_a = nil -- last drawn selection handle hit rects
	self._sel_b = nil
	self._cur_handle = nil
	self._handle_drag = nil -- "cur" | "a" | "b"
	self._press_ms = 0
	self._press_moved = false
	self._lp_fired = false
	self._press_mx, self._press_my = 0, 0

	self._char_w = {}
	self._prefix_w = { [1] = 0 }
	self._positions = { 1 }
	self._dirty = true

	return self
end

function TI:_invalidate()
	self._dirty = true
end

function TI:_emit_change()
	self:_invalidate()
	self.goal_x = nil
	self._cur_row = nil
	self._toolbar = false
	-- content changed: follow the caret — wrap mode stops growing at
	-- max_lines and scrolls instead, so typing must reveal the last char
	self:_ensure_cursor_visible()
	if self.on_change then
		self.on_change(self.value)
	end
end

function TI:_rebuild_cache()
	local s = self.value
	local n = #s
	local char_w = {}
	local prefix_w = { [1] = 0 }
	local positions = { 1 }
	local acc = 0
	local i = 1
	while i <= n do
		local step = utf8_step(s, i)
		local ni = i + step
		if ni > n + 1 then
			ni = n + 1
		end
		local ch = s:sub(i, ni - 1)
		local w = select(1, self.ctx.get_text_size(ch))
		char_w[i] = w
		acc = acc + w
		prefix_w[ni] = acc
		positions[#positions + 1] = ni
		i = ni
	end
	self._char_w = char_w
	self._prefix_w = prefix_w
	self._positions = positions
	self._dirty = false
	self._cache_val = s
	self._lines = nil -- value changed: visual layout must be recomputed
end

-- wrap the byte range [a, b] (inclusive, newline-free) into visual rows
-- that fit maxw pixels: greedy word-wrap on spaces, hard break for
-- over-long words. rows are { s = first byte, e = one-past-last byte,
-- w = pixel width, hard = terminated by an explicit newline }
local function wrap_range(self, s, a, b, maxw, lines)
	local prefix = self._prefix_w
	local ls = a
	while ls <= b do
		local le = ls
		local i = ls
		while i <= b do
			local ni = utf8_next(s, i)
			if ni > b + 1 then
				ni = b + 1
			end
			if (prefix[ni] or 0) - (prefix[ls] or 0) > maxw then
				break
			end
			le = ni
			i = ni
		end
		if le > b then
			-- remainder of the segment fits on this row
			lines[#lines + 1] = { s = ls, e = le, w = (prefix[le] or 0) - (prefix[ls] or 0) }
			ls = le
		elseif le > ls then
			-- overflow: prefer breaking at a word boundary
			local sp = nil
			local j = le - 1
			while j > ls do
				if s:byte(j) == 0x20 then
					sp = j
					break
				end
				j = j - 1
			end
			if sp then
				le = sp + 1
			elseif s:byte(le) == 0x20 then
				le = le + 1 -- keep the space as invisible line-end padding
			end
			lines[#lines + 1] = { s = ls, e = le, w = (prefix[le] or 0) - (prefix[ls] or 0) }
			ls = le
		else
			-- single char wider than the row: hard break mid-word
			le = utf8_next(s, ls)
			if le > b + 1 then
				le = b + 1
			end
			lines[#lines + 1] = { s = ls, e = le, w = (prefix[le] or 0) - (prefix[ls] or 0) }
			ls = le
		end
	end
end

-- visual layout of self.value at the current text_w (cached). the cache is
-- stamped with the value it was built from: a stale stamp (value assigned
-- without going through set_value/_insert) forces a rebuild, so prefix
-- lookups can never disagree with the string being wrapped
function TI:_layout()
	if
		not self._dirty
		and self._lines
		and self._lines_w == self.text_w
		and self._cache_val == self.value
	then
		return self._lines
	end
	if self._dirty or self._cache_val ~= self.value then
		self:_rebuild_cache()
	end
	local s = self.value
	local n = #s
	local lines = {}
	if not self.wrap or n == 0 or not self.text_w then
		lines[1] = { s = 1, e = n + 1, w = self._prefix_w[n + 1] or 0 }
		self._lines = lines
		self._lines_w = self.text_w
		return lines
	end
	local maxw = self.text_w
	if maxw < 8 then
		maxw = 8
	end
	local a = 1
	while a <= n do
		local nl = s:find("\n", a, true)
		local b = nl and (nl - 1) or n
		local count0 = #lines
		if b >= a then
			wrap_range(self, s, a, b, maxw, lines)
		end
		if nl then
			if #lines == count0 then
				-- empty segment: blank visual row
				lines[#lines + 1] = { s = nl, e = nl + 1, w = 0, hard = true }
			else
				local last = lines[#lines]
				last.e = nl + 1
				last.hard = true
			end
			a = nl + 1
		else
			break
		end
	end
	if #lines == 0 then
		lines[1] = { s = 1, e = n + 1, w = 0 }
	end
	self._lines = lines
	self._lines_w = self.text_w
	return lines
end

-- byte position -> (row, pixel x within the row). hint disambiguates a
-- wrap boundary (row end == next row start) to the cursor's own row
function TI:_rowcol_of(p, hint)
	local lines = self:_layout()
	local prefix = self._prefix_w
	local nl = #lines
	if nl == 0 then
		return 1, 0
	end
	if p < 1 then
		p = 1
	end
	if p > lines[nl].e then
		p = lines[nl].e
	end
	local function row_x(k)
		local ln = lines[k]
		local x = (prefix[p] or 0) - (prefix[ln.s] or 0)
		if x < 0 then
			x = 0
		end
		if x > (ln.w or 0) then
			x = ln.w or 0
		end
		return k, x
	end
	if hint and hint >= 1 and hint <= nl then
		local ln = lines[hint]
		if p >= ln.s and p <= ln.e then
			return row_x(hint)
		end
	end
	for k = 1, nl do
		if p <= lines[k].e then
			return row_x(k)
		end
	end
	return row_x(nl)
end

-- nearest byte position to target_x (pixels) on visual row
function TI:_pos_in_row(row, target_x)
	local lines = self:_layout()
	local ln = lines[row]
	if not ln then
		return self.cursor
	end
	local s = self.value
	local prefix = self._prefix_w
	local best, bx = ln.s, 0
	local p = ln.s
	while true do
		local x = (prefix[p] or 0) - (prefix[ln.s] or 0)
		if x < 0 then
			x = 0
		end
		if x > (ln.w or 0) then
			x = ln.w or 0
		end
		if math.abs(x - target_x) < math.abs(bx - target_x) then
			best, bx = p, x
		end
		if p >= ln.e then
			break
		end
		p = utf8_next(s, p)
		if p > ln.e then
			p = ln.e
		end
	end
	return best
end

-- mouse point -> byte position (wrap mode): row from y, column from x
function TI:_pos_at(mx, my)
	local lines = self:_layout()
	local nl = #lines
	local base_h = self._base_h or self.h
	local text_y = self.y + math.floor((base_h - self.font_lh) / 2)
	local vis = math.min(nl, self.max_lines)
	if vis < 1 then
		vis = 1
	end
	local row = math.floor((my - text_y) / self.font_lh) + 1 + self.scroll_line
	if row < self.scroll_line + 1 then
		row = self.scroll_line + 1
	end
	if row > self.scroll_line + vis then
		row = self.scroll_line + vis
	end
	if row < 1 then
		row = 1
	end
	if row > nl then
		row = nl
	end
	return self:_pos_in_row(row, mx - self.text_x)
end

function TI:set_rect(x, y, w, h)
	w = tonumber(w) or 0
	h = tonumber(h) or 0
	if w ~= self.w then
		self:_invalidate()
	end
	self.x, self.y, self.w, self.h = x, y, w, h
	self.text_x = x + self.pad_l
	self.text_w = w - self.pad_l - self.pad_r
	if self.wrap then
		-- h is the host's base height; the widget expands downward from it
		self._base_h = h
		self:_sync_h()
	end
end

function TI:set_value(s)
	s = s or ""
	if self.max_bytes and #s > self.max_bytes then
		local cut = self.max_bytes
		while cut > 0 do
			local b = s:byte(cut + 1)
			if not b or b < 0x80 or b >= 0xC0 then
				break
			end
			cut = cut - 1
		end
		s = s:sub(1, cut)
	end
	self.value = s
	if self.cursor > #self.value + 1 then
		self.cursor = #self.value + 1
	end
	if self.anchor and self.anchor > #self.value + 1 then
		self.anchor = #self.value + 1
	end
	self:_emit_change()
end

function TI:focus()
	self.focused = true
	self.blink_on = true
	self.blink_t = 0
end

function TI:blur()
	self.focused = false
	self.anchor = nil
	self.dragging = false
	self.preedit = nil
	self._toolbar = false
	self._tb = nil
	self._sel_a, self._sel_b, self._cur_handle = nil, nil, nil
	self._handle_drag = nil
	self._press_ms = 0
	self._lp_fired = false
end

function TI:has_selection()
	return self.anchor and self.anchor ~= self.cursor
end

function TI:sel_range()
	if not self:has_selection() then
		return nil, nil
	end
	local a, b = self.anchor, self.cursor
	if a > b then
		a, b = b, a
	end
	return a, b
end

function TI:contains(mx, my)
	if self.wrap then
		self:_sync_h()
	end
	return mx >= self.x and mx < self.x + self.w and my >= self.y and my < self.y + self.h
end

function TI:_x_of(i)
	if self._dirty then
		self:_rebuild_cache()
	end
	local w = self._prefix_w[i] or 0
	return self.text_x - self.scroll_x + w
end

function TI:_pos_of(x)
	if self._dirty then
		self:_rebuild_cache()
	end
	local n = #self.value
	if n == 0 then
		return 1
	end
	local target = x - self.text_x + self.scroll_x
	if target <= 0 then
		return 1
	end
	local positions = self._positions
	local prefix_w = self._prefix_w
	local lo, hi = 1, #positions
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		local p = positions[mid]
		if (prefix_w[p] or 0) < target then
			lo = mid + 1
		else
			hi = mid
		end
	end
	if lo > 1 then
		local a = positions[lo - 1]
		local b = positions[lo]
		local wa = prefix_w[a] or 0
		local wb = prefix_w[b] or 0
		if target - wa < wb - target then
			return a
		end
	end
	return positions[lo]
end

-- effective widget height for the current visual row count (wrap mode):
-- base height assigned by the host + one line height per extra row
function TI:_sync_h()
	if not self._base_h or not self.text_w then
		return
	end
	local lines = self:_layout()
	local rows = #lines
	if rows < 1 then
		rows = 1
	end
	if rows > self.max_lines then
		rows = self.max_lines
	end
	local max_scroll = #lines - rows
	if max_scroll < 0 then
		max_scroll = 0
	end
	if self.scroll_line > max_scroll then
		self.scroll_line = max_scroll
	end
	if self.scroll_line < 0 then
		self.scroll_line = 0
	end
	local nh = self._base_h + (rows - 1) * self.font_lh
	if nh ~= self.h then
		self.h = nh
		if self._on_grow then
			self._on_grow(self, nh)
		end
	end
end

-- current desired height (grows with wrapped rows); hosts may call this
-- from size_fn / tick to re-fit the panel around the input
function TI:height()
	if self.wrap then
		self:_sync_h()
	end
	return self.h
end

-- pixel growth beyond the base height the host assigned via set_rect
-- (0 while the text fits the base row). hosts shift their layout by this
-- amount in draw and Panel:fit grows the panel to match
function TI:extra_h()
	if self.wrap and self._base_h and self.text_w then
		self:_sync_h()
		return self.h - self._base_h
	end
	return 0
end

function TI:_ensure_cursor_visible()
	if not self.text_w then
		return
	end
	if not self.wrap then
		local cx = self:_x_of(self.cursor)
		local left = self.text_x
		local right = self.text_x + self.text_w
		if cx < left then
			self.scroll_x = self.scroll_x - (left - cx)
		elseif cx > right - 2 then
			self.scroll_x = self.scroll_x + (cx - (right - 2))
		end
		if self.scroll_x < 0 then
			self.scroll_x = 0
		end
		return
	end
	local lines = self:_layout()
	local nl = #lines
	local vis = math.min(nl, self.max_lines)
	if vis < 1 then
		vis = 1
	end
	local row = self:_rowcol_of(self.cursor, self._cur_row)
	if row < self.scroll_line + 1 then
		self.scroll_line = row - 1
	elseif row > self.scroll_line + vis then
		self.scroll_line = row - vis
	end
	local max_scroll = nl - vis
	if max_scroll < 0 then
		max_scroll = 0
	end
	if self.scroll_line > max_scroll then
		self.scroll_line = max_scroll
	end
	if self.scroll_line < 0 then
		self.scroll_line = 0
	end
end

function TI:_delete_selection()
	local a, b = self:sel_range()
	if not a then
		return false
	end
	self.value = splice(self.value, a, b)
	self.cursor = a
	self.anchor = nil
	self:_emit_change()
	return true
end

function TI:_insert(text)
	if not text or text == "" then
		return
	end
	if self:has_selection() then
		self:_delete_selection()
	end
	if self.max_bytes then
		local budget = self.max_bytes - #self.value
		if budget <= 0 then
			if self.on_limit then
				self.on_limit()
			end
			return
		end
		if #text > budget then
			local cut = budget
			while cut > 0 do
				local b = text:byte(cut + 1)
				if not b or b < 0x80 or b >= 0xC0 then
					break
				end
				cut = cut - 1
			end
			text = text:sub(1, cut)
			if self.on_limit then
				self.on_limit()
			end
		end
	end
	local i = self.cursor
	self.value = splice(self.value, i, i, text)
	self.cursor = i + #text
	self:_emit_change()
end

function TI:select_all()
	if #self.value == 0 then
		return
	end
	self.anchor = 1
	self.cursor = #self.value + 1
end

function TI:clear()
	self.value = ""
	self.cursor = 1
	self.anchor = nil
	self.scroll_x = 0
	self.scroll_line = 0
	self:_emit_change()
end

function TI:copy()
	local a, b = self:sel_range()
	if not a then
		return false
	end
	Clipboard.copy(self.value:sub(a, b - 1))
	if self.notify then
		self.notify(I.t("Copied"), { style = "success" })
	end
	return true
end

function TI:cut()
	local a, b = self:sel_range()
	if not a then
		return false
	end
	Clipboard.copy(self.value:sub(a, b - 1))
	self:_delete_selection()
	if self.notify then
		self.notify(I.t("Cut to clipboard"), { style = "success" })
	end
	return true
end

-- async clipboard paste: spawn a background subshell that writes the
-- clipboard to a tmpfile and drops a DONE marker when finished; the harvest
-- happens in poll_paste (driven from tick) so the main loop never blocks
function TI:paste()
	if self._paste_pending then
		return true
	end
	local b = Clipboard.backend()
	local cmd
	if b == "wayland" then
		cmd = "wl-paste --no-newline"
	elseif b == "xclip" then
		cmd = "xclip -selection clipboard -o"
	elseif b == "xsel" then
		cmd = "xsel -b -o"
	else
		return false
	end
	local tmp = os.tmpname()
	os.remove(tmp)
	os.execute(string.format(
		"( %s > '%s' 2>/dev/null; echo done > '%s.done' ) &", cmd, tmp, tmp))
	self._paste_tmp = tmp
	self._paste_pending = true
	return true
end

-- harvest a pending paste; returns true when text was inserted
function TI:poll_paste()
	if not self._paste_pending or not self._paste_tmp then
		return false
	end
	local df = io.open(self._paste_tmp .. ".done", "r")
	if not df then
		return false
	end
	df:close()
	local tmp = self._paste_tmp
	self._paste_pending = false
	self._paste_tmp = nil
	os.remove(tmp .. ".done")
	local f = io.open(tmp, "rb")
	local content
	if f then
		content = f:read("*a")
		f:close()
	end
	os.remove(tmp)
	if not content or content == "" then
		if self.focused and self.notify then
			self.notify(I.t("Clipboard empty"), { style = "plain" })
		end
		return false
	end
	if not self.focused then
		return false
	end
	-- single-line input: strip trailing newline, fold interior newlines,
	-- cap to a sane size without splitting UTF-8 codepoints
	content = content:gsub("[\r\n]+$", ""):gsub("[\r\n]+", " ")
	content = utf8_safe_cut(content, PASTE_MAX)
	if content == "" then
		return false
	end
	self:_insert(content)
	if self.notify then
		self.notify(I.t("Pasted"), { style = "success" })
	end
	return true
end

local XK_Left = 0xff51
local XK_Right = 0xff53
local XK_Up = 0xff52
local XK_Down = 0xff54
local XK_Home = 0xff50
local XK_End = 0xff57
local XK_BackSpace = 0xff08
local XK_Delete = 0xffff
local XK_Return = 0xff0d
local XK_KP_Enter = 0xff8d
local XK_Escape = 0xff1b
local XK_a = 0x61
local XK_c = 0x63
local XK_u = 0x75
local XK_v = 0x76
local XK_w = 0x77
local XK_x = 0x78
local XK_y = 0x79
local XK_z = 0x7a

function TI:on_key(sym, ctrl, shift, text)
	if ctrl then
		if sym == XK_a then
			self:select_all()
			self._toolbar = true
			return true
		elseif sym == XK_c then
			self:copy()
			return true
		elseif sym == XK_x then
			self:cut()
			return true
		elseif sym == XK_v then
			self:paste()
			return true
		elseif sym == XK_u then
			self:clear()
			return true
		elseif sym == XK_w then
			if self:has_selection() then
				self:_delete_selection()
			else
				local a = prev_word(self.value, self.cursor)
				if a < self.cursor then
					self.value = splice(self.value, a, self.cursor)
					self.cursor = a
					self:_emit_change()
				end
			end
			return true
		elseif sym == XK_y then
			return true
		elseif sym == XK_z then
			return true
		end
	end

	if sym == XK_Left then
		local ni = ctrl and prev_word(self.value, self.cursor) or utf8_prev(self.value, self.cursor)
		if shift then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		self.cursor = ni
		self.goal_x = nil
		self._cur_row = nil
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_Right then
		local ni = ctrl and next_word(self.value, self.cursor) or utf8_next(self.value, self.cursor)
		if shift then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		self.cursor = ni
		self.goal_x = nil
		self._cur_row = nil
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_Home then
		if shift then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		if self.wrap and not ctrl then
			local r = self:_rowcol_of(self.cursor, self._cur_row)
			self.cursor = self:_layout()[r].s
			self._cur_row = r
		else
			self._cur_row = nil
			self.cursor = 1
		end
		self.goal_x = nil
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_End then
		if shift then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		if self.wrap and not ctrl then
			local lines = self:_layout()
			local r = self:_rowcol_of(self.cursor, self._cur_row)
			self.cursor = lines[r].e
			self._cur_row = r
		else
			self._cur_row = nil
			self.cursor = #self.value + 1
		end
		self.goal_x = nil
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_Up or sym == XK_Down then
		if not self.wrap then
			return false
		end
		local lines = self:_layout()
		local nl = #lines
		if nl <= 1 then
			return false -- single visual row: let the host use Up/Down
		end
		local row = self:_rowcol_of(self.cursor, self._cur_row)
		if not self.goal_x then
			self.goal_x = select(2, self:_rowcol_of(self.cursor, self._cur_row))
		end
		local tr = sym == XK_Up and row - 1 or row + 1
		if tr < 1 or tr > nl then
			return false -- first/last visual row: host may navigate
		end
		if shift then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		self.cursor = self:_pos_in_row(tr, self.goal_x)
		self._cur_row = tr
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_BackSpace then
		if self:has_selection() then
			self:_delete_selection()
		else
			local a = ctrl and prev_word(self.value, self.cursor) or utf8_prev(self.value, self.cursor)
			if a < self.cursor then
				self.value = splice(self.value, a, self.cursor)
				self.cursor = a
				self:_emit_change()
			end
		end
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_Delete then
		if self:has_selection() then
			self:_delete_selection()
		else
			local b = ctrl and next_word(self.value, self.cursor) or utf8_next(self.value, self.cursor)
			if b > self.cursor then
				self.value = splice(self.value, self.cursor, b)
				self:_emit_change()
			end
		end
		self:_ensure_cursor_visible()
		return true
	elseif sym == XK_Return or sym == XK_KP_Enter then
		if self.on_submit then
			self.on_submit(self.value)
		end
		return true
	elseif sym == XK_Escape then
		if self.on_cancel then
			self.on_cancel()
		end
		return true
	end

	if text and #text > 0 then
		local first = text:byte(1)
		if first and first >= 0x20 then
			self:_insert(text)
			return true
		end
	end

	return false
end

function TI:_update_click_count(mx, my)
	local now = os.clock() * 1000
	if
		self._click_count > 0
		and now - self._last_click_t < 400
		and math.abs(mx - self._last_click_x) < 4
		and math.abs(my - self._last_click_y) < 4
	then
		self._click_count = self._click_count + 1
		if self._click_count > 3 then
			self._click_count = 1
		end
	else
		self._click_count = 1
	end
	self._last_click_t = now
	self._last_click_x = mx
	self._last_click_y = my
end

function TI:on_mouse_press(mx, my, shift_held)
	-- floating toolbar (drawn above/below the input, outside its rect)
	if self._toolbar and self._tb then
		local act = self:_toolbar_hit(mx, my)
		if act then
			self:_toolbar_action(act)
			return true
		end
	end
	-- draggable handles win over repositioning the cursor
	local h = self:_handle_hit(mx, my)
	if h then
		self._handle_drag = h
		self.dragging = false
		self._press_ms = 0
		self._lp_fired = true
		return true
	end
	if not self:contains(mx, my) then
		return false
	end
	self:focus()
	if self.clear_btn and #self.value > 0 and mx >= self.x + self.w - 24 then
		self:clear()
		self.blink_on = true
		self.blink_t = 0
		return true
	end
	self:_update_click_count(mx, my)
	-- a plain press dismisses the toolbar / restarts long-press tracking
	self._toolbar = false
	self._tb = nil
	self._press_ms = 0
	self._press_moved = false
	self._lp_fired = false
	self._press_mx, self._press_my = mx, my
	local pos = self.wrap and self:_pos_at(mx, my) or self:_pos_of(mx)
	self.goal_x = nil
	self._cur_row = nil
	if self._click_count == 2 then
		local a = prev_word(self.value, pos)
		local b = next_word(self.value, pos)
		if a == b then
			a = pos
			b = pos
		end
		self.anchor = a
		self.cursor = b
		self._toolbar = true
	elseif self._click_count >= 3 then
		self:select_all()
		self._toolbar = true
	else
		if shift_held then
			if not self.anchor then
				self.anchor = self.cursor
			end
		else
			self.anchor = nil
			self._toolbar = false
		end
		self.cursor = pos
	end
	self.dragging = true
	self.drag_origin = pos
	self.blink_on = true
	self.blink_t = 0
	return true
end

function TI:on_mouse_move(mx, my)
	if self._handle_drag then
		local pos = self.wrap and self:_pos_at(mx, my) or self:_pos_of(mx)
		if self._handle_drag == "cur" then
			self.anchor = nil
			self.cursor = pos
		elseif self._handle_drag == "a" then
			self.anchor = pos
		else
			self.cursor = pos
		end
		self.goal_x = nil
		self._cur_row = nil
		return true
	end
	if not self.dragging then
		return false
	end
	if
		math.abs(mx - self._press_mx) > 4 or math.abs(my - self._press_my) > 4
	then
		self._press_moved = true
	end
	local pos = self.wrap and self:_pos_at(mx, my) or self:_pos_of(mx)
	if not self.anchor then
		self.anchor = self.drag_origin
	end
	self.cursor = pos
	return true
end

function TI:on_mouse_release()
	if self._handle_drag then
		self._handle_drag = nil
		self._toolbar = self:has_selection()
		return true
	end
	if self.dragging then
		self.dragging = false
		-- android: the toolbar pops up once a drag produced a selection
		if self:has_selection() then
			self._toolbar = true
		end
		return true
	end
	return false
end

-- ── android-style editing affordances ──

function TI:_select_word_at(mx, my)
	local pos = self.wrap and self:_pos_at(mx, my) or self:_pos_of(mx)
	local a = prev_word(self.value, pos)
	local b = next_word(self.value, pos)
	if a == b then
		a, b = pos, pos
	end
	self.anchor = a
	self.cursor = b
	self.blink_on = true
	self.blink_t = 0
end

-- handle hit rects are recorded by the last draw; "a"/"b" are the two
-- selection ends, "cur" the plain cursor handle
function TI:_handle_hit(mx, my)
	if not self.focused then
		return nil
	end
	local function inrect(r)
		return r and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
	end
	if inrect(self._sel_a) then
		return "a"
	end
	if inrect(self._sel_b) then
		return "b"
	end
	if not self:has_selection() and inrect(self._cur_handle) then
		return "cur"
	end
	return nil
end

function TI:_toolbar_hit(mx, my)
	local tb = self._tb
	if not tb then
		return nil
	end
	if mx < tb.x or mx >= tb.x + tb.w or my < tb.y or my >= tb.y + tb.h then
		return nil
	end
	for _, b in ipairs(tb.btns) do
		if mx >= b.x and mx < b.x + b.w then
			return b.act
		end
	end
	return nil
end

function TI:_toolbar_action(act)
	if act == "copy" then
		self:copy() -- toast happens inside copy()
	elseif act == "cut" then
		self:cut()
	elseif act == "paste" then
		self:paste() -- "Pasted" toast lands when the async harvest inserts
	elseif act == "all" then
		self:select_all()
	elseif act == "left" then
		local a = self:sel_range()
		self.anchor = nil
		self._toolbar = false
		self.cursor = a and a or math.max(1, utf8_prev(self.value, self.cursor))
	elseif act == "right" then
		local a, b = self:sel_range()
		self.anchor = nil
		self._toolbar = false
		self.cursor = b and b
			or math.min(#self.value + 1, utf8_next(self.value, self.cursor))
	end
	self.blink_on = true
	self.blink_t = 0
end

-- handle anchor point for byte position p: (pixel x, row-bottom y), y nil
-- when the row is scrolled out of view. end_x, when given, re-derives x
-- from another byte position on the same visual row (places the selection
-- end handle a char forward at a wrap boundary)
function TI:_handle_pos(p, end_x)
	local lh = self.font_lh
	local lines = self:_layout()
	local prefix = self._prefix_w
	local row, x = self:_rowcol_of(p)
	local vis = math.min(#lines, self.max_lines)
	if vis < 1 then
		vis = 1
	end
	local vi = row - 1 - self.scroll_line
	if vi < 0 or vi > vis - 1 then
		return nil
	end
	if end_x then
		local ln = lines[row]
		x = (prefix[end_x] or 0) - (prefix[ln.s] or 0)
		if x < 0 then
			x = 0
		end
		if x > (ln.w or 0) then
			x = ln.w or 0
		end
	end
	local y = self.y + math.floor(((self._base_h or self.h) - lh) / 2) + vi * lh + lh
	return self.text_x + x, y
end

-- teardrop-style handle below the anchor point; returns the hit rect
function TI:_draw_handle(s, theme, x, ybottom)
	local col = theme.cursor or theme.primary
	s:rect(x, ybottom + 2, 2, 9, col)
	s:rrect(x - 7, ybottom + 9, 14, 14, 7, theme.surface)
	s:rrect(x - 6, ybottom + 10, 12, 12, 6, col)
	return { x = x - 10, y = ybottom + 7, w = 20, h = 18 }
end

function TI:_draw_handles(s, theme)
	self._sel_a, self._sel_b, self._cur_handle = nil, nil, nil
	if not self.focused then
		return
	end
	local a, b = self:sel_range()
	if a then
		local xa, ya = self:_handle_pos(a)
		local xb, yb = self:_handle_pos(b - 1, b)
		if ya then
			self._sel_a = self:_draw_handle(s, theme, xa, ya)
		end
		if yb then
			self._sel_b = self:_draw_handle(s, theme, xb, yb)
		end
	else
		local x, y = self:_handle_pos(self.cursor)
		if y then
			self._cur_handle = self:_draw_handle(s, theme, x, y)
		end
	end
end

function TI:_draw_toolbar(s, theme)
	if not self._toolbar or not self.focused then
		self._tb = nil
		return
	end
	local tb_h = 34
	local pad = 8
	local aw = 26
	local lh = self.font_lh
	local col = theme.on_surface or theme.on_var
	local bg = theme.bg_focus or theme.surface_hi
	local items = {
		{ I.t("Select all"), "all" },
		{ I.t("Copy"), "copy" },
		{ I.t("Cut"), "cut" },
		{ I.t("Paste"), "paste" },
	}
	local btns = {}
	local total = pad + aw + 6 + aw + pad
	for _, it in ipairs(items) do
		local w = select(1, self.ctx.get_text_size(it[1])) + 20
		btns[#btns + 1] = { label = it[1], act = it[2], w = w }
		total = total + w
	end
	local tx = self.x + math.floor((self.w - total) / 2)
	if tx < 2 then
		tx = 2
	end
	local ty = self.y - tb_h - 8
	if ty < 2 then
		ty = self.y + self.h + 8
	end
	s:rrect(tx, ty, total, tb_h, 16, bg)
	local cy = ty + math.floor(tb_h / 2)
	local cx = tx + pad
	-- ◀ ▶ cursor nudge buttons (primitive triangles: fonts miss the glyphs)
	for i, dir in ipairs({ "left", "right" }) do
		local acx = cx + math.floor(aw / 2)
		for k = 0, 4 do
			if dir == "right" then
				s:rect(acx - 3 + k, cy - k, 2, 2 * k + 1, col)
			else
				s:rect(acx + 2 - k, cy - k, 2, 2 * k + 1, col)
			end
		end
		btns[#btns + 1] = { act = dir, x = cx, w = aw }
		cx = cx + aw + (i == 1 and 6 or 0)
	end
	s:rect(cx, ty + 8, 1, tb_h - 16, theme.outline)
	cx = cx + pad
	local ty_text = ty + math.floor((tb_h - lh) / 2)
	for _, b in ipairs(btns) do
		if b.label then
			b.x = cx
			s:text(cx + 10, ty_text, b.label, col)
			cx = cx + b.w
		end
	end
	self._tb = { x = tx, y = ty, w = total, h = tb_h, btns = btns }
end

-- shared chrome: background, focus outline, leading icon
function TI:_draw_frame(s, theme)
	local bg = self.focused and (theme.bg_focus or theme.surface_hi) or (theme.bg_input or theme.surface)
	local r = theme.radius or math.floor(self.h / 2)

	if self.focused and theme.outline_focus then
		s:rrect(self.x, self.y, self.w, self.h, r, theme.outline_focus)
		s:rrect(self.x + 1, self.y + 1, self.w - 2, self.h - 2, math.max(r - 1, 2), bg)
	else
		s:rrect(self.x, self.y, self.w, self.h, r, bg)
	end

	if self.icon then
		local icol = theme.icon or theme.on_var or theme.outline
		local ix = self.x + 10
		local iy = self.y + math.floor((self.h - 12) / 2)
		s:rrect(ix, iy, 9, 9, 4, icol)
		s:rrect(ix + 1, iy + 1, 7, 7, 3, bg)
		s:rect(ix + 7, iy + 7, 2, 2, icol)
		s:rect(ix + 9, iy + 9, 2, 2, icol)
	end
end

-- shared trailing clear (×) button
function TI:_draw_clear(s, theme)
	if self.clear_btn and #self.value > 0 then
		local xcol = theme.on_var or theme.outline
		local bx = self.x + self.w - 16
		local by = self.y + math.floor((self.h - 7) / 2)
		for i = 0, 5 do
			s:rect(bx + i, by + i, 2, 2, xcol)
			s:rect(bx + 6 - i, by + i, 2, 2, xcol)
		end
	end
end

-- legacy single-row path (opts.wrap == false): clipped, horizontally
-- scrolling — behaviour unchanged from before multi-line support
function TI:_draw_single(s, theme)
	local lh = self.font_lh
	local text_y = self.y + math.floor((self.h - lh) / 2)

	self:_draw_frame(s, theme)

	local a, b = self:sel_range()
	if a then
		local x1 = self:_x_of(a)
		local x2 = self:_x_of(b)
		local cx1 = math.max(x1, self.text_x)
		local cx2 = math.min(x2, self.text_x + self.text_w)
		if cx2 > cx1 then
			s:rrect(cx1, text_y - 2, cx2 - cx1, lh + 4, theme.sel_radius or 3, theme.sel_bg or theme.primary)
		end
	end

	if #self.value == 0 and self.placeholder then
		s:text(self.text_x, text_y, self.placeholder, theme.on_var or theme.outline)
	else
		local n = #self.value
		local start_i = 1
		local end_i = n + 1
		if n > 0 then
			start_i = self:_pos_of(self.text_x)
			end_i = self:_pos_of(self.text_x + self.text_w)
			if end_i <= start_i then
				end_i = start_i + 1
			end
		end
		local visible = self.value:sub(start_i, end_i - 1)
		local draw_x = self:_x_of(start_i)
		if draw_x < self.text_x then
			draw_x = self.text_x
		end
		if #visible > 0 then
			s:text(draw_x, text_y, visible, theme.on_surface)
		end
	end

	self:_draw_clear(s, theme)

	if self.focused and self.blink_on and not a then
		local cx = self:_x_of(self.cursor)
		if cx >= self.text_x - 1 and cx <= self.text_x + self.text_w + 1 then
			s:rect(cx, text_y - 2, 2, lh + 4, theme.cursor or theme.primary)
		end
	end

	-- IME composition preview (zwp_text_input_v3 preedit_string)
	if self.focused and self.preedit and #self.preedit > 0 then
		local px = self:_x_of(self.cursor)
		local col = theme.hint or theme.on_var or theme.outline
		if px >= self.text_x - 1 and px <= self.text_x + self.text_w + 1 then
			s:text(px, text_y, self.preedit, col)
			local pw = select(1, self.ctx.get_text_size(self.preedit))
			s:rect(px, text_y + lh + 1, pw, 1, col)
		end
	end
end

-- multi-row path: draw one visual row per line, vertically scrolled to
-- keep the cursor in view; selection and cursor rendered per row
function TI:_draw_wrap(s, theme)
	local lh = self.font_lh
	self:_sync_h()
	local lines = self:_layout()
	local rows = #lines
	if rows < 1 then
		rows = 1
	end
	local base_h = self._base_h or self.h
	local text_y = self.y + math.floor((base_h - lh) / 2)
	local scroll = self.scroll_line
	local vis = math.min(rows, self.max_lines)
	if vis < 1 then
		vis = 1
	end
	local prefix = self._prefix_w

	self:_draw_frame(s, theme)

	local a, b = self:sel_range()
	if a then
		local sel_bg = theme.sel_bg or theme.primary
		local sel_r = theme.sel_radius or 3
		for vi = 0, vis - 1 do
			local ln = lines[scroll + vi + 1]
			if not ln then
				break
			end
			local sa = a > ln.s and a or ln.s
			local sb = b < ln.e and b or ln.e
			if sb > sa then
				local x1 = (prefix[sa] or 0) - (prefix[ln.s] or 0)
				local x2 = (prefix[sb] or 0) - (prefix[ln.s] or 0)
				if x1 < 0 then
					x1 = 0
				end
				if x2 > (ln.w or 0) then
					x2 = ln.w or 0
				end
				if x2 > x1 then
					s:rrect(self.text_x + x1, text_y + vi * lh - 2, x2 - x1, lh + 4, sel_r, sel_bg)
				end
			end
		end
	end

	if #self.value == 0 and self.placeholder then
		s:text(self.text_x, text_y, self.placeholder, theme.on_var or theme.outline)
	else
		for vi = 0, vis - 1 do
			local ln = lines[scroll + vi + 1]
			if not ln then
				break
			end
			local content = self.value:sub(ln.s, ln.e - 1)
			if ln.hard and content:byte(#content) == 0x0a then
				content = content:sub(1, #content - 1)
			end
			if #content > 0 then
				s:text(self.text_x, text_y + vi * lh, content, theme.on_surface)
			end
		end
	end

	self:_draw_clear(s, theme)

	if self.focused and self.blink_on and not a then
		local row, cx = self:_rowcol_of(self.cursor, self._cur_row)
		local vi = row - 1 - scroll
		if vi >= 0 and vi < vis then
			s:rect(self.text_x + cx, text_y + vi * lh - 2, 2, lh + 4, theme.cursor or theme.primary)
		end
	end

	-- IME composition preview (zwp_text_input_v3 preedit_string), drawn
	-- inline at the cursor and wrapped within the input width so CJK
	-- composition stays visible in multi-row inputs
	if self.focused and self.preedit and #self.preedit > 0 then
		local col = theme.hint or theme.on_var or theme.outline
		local row, cx = self:_rowcol_of(self.cursor, self._cur_row)
		local vi = row - 1 - scroll
		if vi < 0 then
			vi = 0
		end
		if vi > vis - 1 then
			vi = vis - 1
		end
		local pe = self.preedit
		local i = 1
		local cur_x = cx
		local guard = 0
		while i <= #pe and guard < 8 and vi < vis do
			guard = guard + 1
			local j = i
			local w = 0
			while j <= #pe do
				local ni = utf8_next(pe, j)
				local cw = select(1, self.ctx.get_text_size(pe:sub(j, ni - 1)))
				if cur_x + w + cw > self.text_w and j > i then
					break
				end
				w = w + cw
				j = ni
			end
			if j == i then
				-- first char alone does not fit: wrap to the next row
				if cur_x > 0 and vi + 1 < vis then
					cur_x = 0
					vi = vi + 1
				else
					break
				end
			else
				local seg = pe:sub(i, j - 1)
				s:text(self.text_x + cur_x, text_y + vi * lh, seg, col)
				s:rect(self.text_x + cur_x, text_y + vi * lh + lh + 1, w, 1, col)
				i = j
				cur_x = 0
				vi = vi + 1
			end
		end
	end
end

function TI:draw(s, theme)
	if self._dirty then
		self:_rebuild_cache()
	end
	theme = theme or self.ctx.theme
	if self.wrap then
		self:_draw_wrap(s, theme)
	else
		self:_draw_single(s, theme)
	end
	self:_draw_handles(s, theme)
	self:_draw_toolbar(s, theme)
end

function TI:tick(dt_ms)
	-- harvest any pending async clipboard paste (panel drives this each cycle)
	local changed = self:poll_paste()
	if not self.focused then
		self.blink_on = true
		return changed
	end
	self.blink_t = self.blink_t + dt_ms
	if self.blink_t >= self.blink_ms then
		self.blink_t = 0
		self.blink_on = not self.blink_on
	end
	-- android long-press: hold still ~450ms to select the word under the
	-- finger and pop up the floating edit toolbar
	if self.dragging and not self._lp_fired and not self._press_moved then
		self._press_ms = self._press_ms + dt_ms
		if self._press_ms >= 450 then
			self._lp_fired = true
			self:_select_word_at(self._press_mx, self._press_my)
			if self:has_selection() then
				self._toolbar = true
			end
		end
	end
	return changed
end

return M
