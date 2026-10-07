local M = {}
local Panel = require("core.panel")
local Clipboard = require("core.clipboard")
local Util = require("core.util")

local log = Util.logger("clip_hist")
local keybind_hint = Util.keybind_hint

local POLL_MS = 2000
local MAX_ENTRY_BYTES = 65536

local L_TITLE = "Clipboard"
local L_CLEAR = "clear"
local L_EMPTY = "clipboard is empty, go copy something"
local L_NO_MATCH = "no matching entries"

local function truncate_to_px(ctx, text, max_w)
	if max_w <= 0 then
		return ""
	end
	if select(1, ctx.get_text_size(text)) <= max_w then
		return text
	end

	local hi = #text
	while hi > 1 do
		local b = text:byte(hi)
		if b and b >= 0x80 and b < 0xC0 then
			hi = hi - 1
		else
			break
		end
	end

	local lo, best = 1, 1
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		while mid > 1 do
			local b = text:byte(mid)
			if b and b >= 0x80 and b < 0xC0 then
				mid = mid - 1
			else
				break
			end
		end
		if mid < 1 then
			mid = 1
		end
		local sub = text:sub(1, mid) .. "…"
		if select(1, ctx.get_text_size(sub)) <= max_w then
			best = mid
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	return text:sub(1, best) .. "…"
end

local function one_line(text)
	return (text:gsub("[\r\n]+", " "))
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		W = 560,
		APPBAR = lh + 26,
		SEARCH_H = lh + 20,
		ROW_H = lh + 22,
		VROWS = 8,
	}
	if user_size then
		m.W = math.max(400, user_size.w)
		local used = m.APPBAR + 14 + m.SEARCH_H + 12 + 14
		m.VROWS = math.max(3, math.floor((user_size.h - used) / m.ROW_H))
	end
	m.H = m.APPBAR + 14 + m.SEARCH_H + 12 + m.VROWS * m.ROW_H + 14
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH
	local W, H = m.W, m.H
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end

	local ay = p:draw_header(L_TITLE, nil, 24)

	local r = p.rect_close
	local clear_w = 64
	local clear_x = r.x - 12 - clear_w
	local clear_y = math.floor((m.APPBAR - (28)) / 2) + 1
	if ui:id_button("clip_clear", clear_x, clear_y, clear_w, 26, L_CLEAR, { tonal = true }) then
		M.clear_all()
	end

	local hw = tw(M.hint)
	local hint_right = clear_x - 12
	local hint_x = hint_right - hw
	local min_x = 24 + tw(L_TITLE) + 12
	if hint_x >= min_x then
		p:text(hint_x, ay, M.hint, T.hint)
	end

	local sy = m.APPBAR + 14
	p.input:set_rect(24, sy, W - 48, m.SEARCH_H)
	p.input:draw(p)

	local list_y = sy + m.SEARCH_H + 12
	local n = #M.filtered

	p:rect(0, list_y, W, m.VROWS * m.ROW_H, T.bg)

	local row_text_x = 44
	local time_pad_r = 24
	local time_w = tw("00:00")
	local row_text_max_w = W - row_text_x - time_pad_r - time_w - 16

	for i = 1, m.VROWS do
		local li = M.scroll + i
		local ry = list_y + (i - 1) * m.ROW_H

		if li <= n then
			local e = M.filtered[li]
			local hover = ui:hover(0, ry, W, m.ROW_H)
			if hover then
				p:rect(0, ry, W, m.ROW_H, T.surface_hi)
			end

			p:rrect(24, ry + math.floor((m.ROW_H - 8) / 2), 8, 8, 4, T.primary)

			local ty = ry + math.floor((m.ROW_H - lh) / 2)
			local display = truncate_to_px(ctx, one_line(e.text), row_text_max_w)
			p:text(row_text_x, ty, display, T.on_var)

			local tstr = os.date("%H:%M", e.t)
			local tsw = tw(tstr)
			p:text(W - time_pad_r - tsw, ty, tstr, T.hint)

			if li < n then
				p:rect(24, ry + m.ROW_H - 1, W - 48, 1, T.outline)
			end

			if ui:clicked(0, ry, W, m.ROW_H) then
				M.copy_row(e)
			end
		end
	end

	if n == 0 then
		local empty = M.query ~= "" and L_NO_MATCH or L_EMPTY
		local ew = tw(empty)
		p:text(math.floor(W / 2 - ew / 2), list_y + math.floor(m.ROW_H * 0.6), empty, T.hint)
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size("clip")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "clip_hist" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "clip", active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "clip_hist", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	local S = ctx._clip_state or {}
	local cfg = ctx.config.clip_hist or {}
	M.max_items = cfg.max_items or 30
	M.history = S.history or {}
	M.last = nil
	M.acc = POLL_MS
	M.scroll = 0
	M.query = ""
	M.hint = keybind_hint(ctx, "toggle_clip_hist")
	M.filtered = M.history

	local panel = Panel.new(ctx, {
		name = "clip_hist",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = "filter history",
			on_change = function(v)
				M.query = v
				M.apply_filter()
			end,
			on_cancel = function()
				M.panel:hide()
			end,
		},
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				local mx_s = math.max(0, #M.filtered - p.m.VROWS)
				if btn == 4 then
					M.scroll = math.max(0, M.scroll - 2)
				else
					M.scroll = math.min(mx_s, M.scroll + 2)
				end
				p:draw()
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("clip_hist", panel)
	log("ready: %d items, backend=%s", #M.history, Clipboard.backend())
end

function M.tick(ctx, dt)
	if not M.panel then
		return
	end
	M.acc = M.acc + dt
	if M.acc >= POLL_MS then
		M.acc = 0
		M.poll()
	end
end

function M.poll()
	local content = Clipboard.paste()
	if not content or content == "" or content == M.last then
		return
	end
	if #content > MAX_ENTRY_BYTES then
		return
	end
	M.last = content
	for i, e in ipairs(M.history) do
		if e.text == content then
			table.remove(M.history, i)
			break
		end
	end
	table.insert(M.history, 1, { text = content, t = os.time() })
	while #M.history > M.max_items do
		table.remove(M.history)
	end
	M.apply_filter()
	if M.panel.visible then
		M.panel:draw()
	end
end

function M.apply_filter()
	if M.query == "" then
		M.filtered = M.history
	else
		local ql = M.query:lower()
		local out = {}
		for _, e in ipairs(M.history) do
			if e.text:lower():find(ql, 1, true) then
				out[#out + 1] = e
			end
		end
		M.filtered = out
	end
	local mx_s = math.max(0, #M.filtered - M.panel.m.VROWS)
	if M.scroll > mx_s then
		M.scroll = mx_s
	end
end

function M.copy_row(e)
	if Clipboard.copy(e.text) then
		M.last = e.text
		M.ctx.notify("copied", { style = "success" })
	else
		M.ctx.notify("copy failed", { style = "error" })
	end
end

function M.clear_all()
	M.history = {}
	M.filtered = M.history
	M.scroll = 0
	M.ctx.notify("clipboard history cleared", { style = "plain" })
	M.panel:draw()
end

function M.shutdown()
	if M.ctx then
		M.ctx._clip_state = { history = M.history }
	end
	M.ctx = nil
end

return M
