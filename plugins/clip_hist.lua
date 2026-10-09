local M = {}
local Panel = require("core.panel")
local Clipboard = require("core.clipboard")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("clip_hist")
local keybind_hint = Util.keybind_hint

local POLL_MS = 2000
local MAX_ENTRY_BYTES = 65536

-- MIUIX-style geometry: rounded card rows, unified side padding,
-- scrollbar lane reserved at the right edge
local PAD, SB_W = 20, 6
local ROW_GAP = 8 -- gap between row cards
local CARD_R = 14 -- row card corner radius

local function row_h(lh)
	return math.max(46, lh + 28)
end

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
	local n = M.filtered and #M.filtered or 0
	local m = {
		LH = lh,
		PAD = PAD,
		W = 560,
		APPBAR = lh + 26,
		IN_H = lh + 20,
		SEARCH_H = 14 + (lh + 20) + 12,
		ROW_H = row_h(lh),
		ROW_GAP = ROW_GAP,
		FOOTER_H = lh + 30,
	}
	m.view_y = m.APPBAR + m.SEARCH_H
	if user_size then
		m.W = math.max(400, user_size.w)
		m.H = math.max(240, user_size.h)
	else
		-- natural height follows the (roomy) card rows, capped at 85% of
		-- the screen; overflow scrolls inside the view
		local content = math.max(1, n) * (m.ROW_H + ROW_GAP)
		m.H = math.max(m.view_y + m.ROW_H + m.FOOTER_H,
			math.min(ctx.scr_h * 0.85, m.view_y + content + m.FOOTER_H))
	end
	m.VROWS = math.max(1, math.floor((m.H - m.view_y - m.FOOTER_H + ROW_GAP) / (m.ROW_H + ROW_GAP)))
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH

	-- self-heal on resize: model follows the live surface so the view band,
	-- visible row count and footer always match the real panel
	m.W, m.H = p.w, p.h
	local in_extra = p.input and p.input:extra_h() or 0
	m.view_y = m.APPBAR + m.SEARCH_H + in_extra
	m.view_h = math.max(m.ROW_H, m.H - m.view_y - m.FOOTER_H)
	m.VROWS = math.max(1, math.floor((m.view_h + m.ROW_GAP) / (m.ROW_H + m.ROW_GAP)))
	local W, H = m.W, m.H
	local n = #M.filtered
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end

	local CR = W - PAD - SB_W -- card right edge
	local card_w = CR - PAD
	local DEL_W = 28 -- per-row delete hit square
	local del_x = CR - 16 - DEL_W
	local time_w = tw("00:00")
	-- entry text leaves room for the timestamp and the delete button
	local row_text_max_w = del_x - 10 - time_w - 12 - (PAD + 16)

	-- scrollable content is painted FIRST; the fixed chrome (header, search
	-- band, footer) is painted on top further down, which clips every row
	-- to the view band without needing a scissor primitive
	local maxs = math.max(0, n - m.VROWS)
	M.scroll = math.max(0, math.min(maxs, M.scroll))
	for i = 1, m.VROWS do
		local li = M.scroll + i
		if li > n then
			break
		end
		local e = M.filtered[li]
		local ry = m.view_y + (i - 1) * (m.ROW_H + m.ROW_GAP)
		local hover = ui:hover(PAD, ry, card_w, m.ROW_H)
		p:rrect(PAD, ry, card_w, m.ROW_H, CARD_R, hover and T.surface_hover or T.surface)
		local ty = ry + math.floor((m.ROW_H - lh) / 2)
		local display = truncate_to_px(ctx, one_line(e.text), row_text_max_w)
		p:text(PAD + 16, ty, display, T.on_var)

		local tstr = os.date("%H:%M", e.t)
		p:text(del_x - 10 - tw(tstr), ty, tstr, T.hint)

		-- delete button: subtle × that gains a hover pill
		local del_y = ry + math.floor((m.ROW_H - DEL_W) / 2)
		if ui:hover(del_x, del_y, DEL_W, DEL_W) then
			p:rrect(del_x, del_y, DEL_W, DEL_W, 8, T.surface_hi)
		end
		p:text(del_x + math.floor((DEL_W - tw("×")) / 2), del_y + math.floor((DEL_W - lh) / 2),
			"×", T.on_var)
		if ui:clicked(del_x, del_y, DEL_W, DEL_W) then
			-- never mutate history mid-draw: queue for M.tick (pcall'd there)
			M.pending_delete = e
		elseif ui:clicked(PAD, ry, card_w, m.ROW_H) then
			M.pending_copy = e
		end
	end

	if n == 0 then
		local empty = M.query ~= "" and I.t("no matching entries")
			or I.t("clipboard is empty, go copy something")
		local ew = tw(empty)
		local ey = m.view_y + math.floor(math.max(0, m.view_h - lh) / 2)
		p:text(math.floor(W / 2 - ew / 2), ey, empty, T.hint)
	end

	-- scrollbar (right edge, inside padding)
	if maxs > 0 then
		local off = ui:scrollbar("scr", W - 14, m.view_y, SB_W, m.view_h, M.scroll, maxs)
		M.scroll = off
	end

	-- fixed chrome painted last so scrolled content can never overlap it

	-- search band: opaque fill over the scrolled rows, then the input
	p:rect(0, m.APPBAR, W, m.SEARCH_H + in_extra, p.bg)
	p.input:set_rect(PAD, m.APPBAR + 14, W - PAD * 2 - SB_W, m.IN_H)
	p.input:draw(p)

	-- header (draw_header paints its own opaque band)
	p:draw_header(I.t("Clipboard"), M.hint, PAD)

	-- footer: opaque band covers rows scrolled past the bottom; pill
	-- button laid out like a MIUI dialog (destructive action tonal)
	local fy = H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	local cnt = string.format("%d / %d", n, #M.history)
	p:text(PAD, mid_y, cnt, T.hint)
	local bw = 84
	local bh = lh + 14
	local bo = math.floor((m.FOOTER_H - bh) / 2)
	if ui:id_button("clip_clear", W - PAD - bw, fy + bo, bw, bh, I.t("clear"), { tonal = true }) then
		-- destructive: queued for M.tick, never run mid-draw
		M.pending_clear = true
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("Clip"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "clip_hist" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("Clip"), active and ctx.theme.primary or ctx.theme.on_surface)
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
	M.pending_copy = nil
	M.pending_delete = nil
	M.pending_clear = nil
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
			placeholder = I.t("filter history"),
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
	-- destructive UI actions queued by draw() run here, outside the draw
	-- pass, pcall-guarded so a failure can never take the bar down
	if M.pending_copy then
		local e = M.pending_copy
		M.pending_copy = nil
		pcall(M.copy_row, e)
	end
	if M.pending_delete then
		local e = M.pending_delete
		M.pending_delete = nil
		pcall(M.remove_entry, e)
	end
	if M.pending_clear then
		M.pending_clear = nil
		pcall(M.clear_all)
	end
	-- auto-fit when the visible entry count changes (cheap change guard;
	-- fit() itself no-ops when the size already matches or user resized)
	if #M.filtered ~= (M.fit_n or -1) then
		M.fit_n = #M.filtered
		M.panel:fit()
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
		M.ctx.notify(I.t("copied"), { style = "success" })
	else
		M.ctx.notify(I.t("copy failed"), { style = "error" })
	end
end

-- remove one entry from the history; runs from M.tick (queued by the row
-- delete button) so the list is never mutated mid-draw
function M.remove_entry(e)
	for i, it in ipairs(M.history) do
		if it == e then
			table.remove(M.history, i)
			M.apply_filter()
			M.ctx.notify(I.t("entry deleted"), { style = "success" })
			if M.panel.visible then
				M.panel:draw()
			end
			return
		end
	end
end

function M.clear_all()
	M.history = {}
	M.filtered = M.history
	M.scroll = 0
	M.ctx.notify(I.t("clipboard history cleared"), { style = "success" })
	M.panel:draw()
end

function M.shutdown()
	if M.ctx then
		M.ctx._clip_state = { history = M.history }
	end
	M.pending_copy = nil
	M.pending_delete = nil
	M.pending_clear = nil
	M.ctx = nil
end

return M
