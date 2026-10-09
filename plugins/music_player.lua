local M = {}
local ffi = require("ffi")
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("music_player")

local function basename(p)
	return p:match("^.*/([^/]+)$") or p
end

local function strip_ext(s)
	return (s:gsub("%.[^%.]+$", ""))
end

local function fmt_time(s)
	if not s or s ~= s or s < 0 then
		return "--:--"
	end
	return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local truncate = Util.truncate

-- toast feedback for user-triggered key actions (auto-advance stays silent)
local function toast(key, ...)
	if M.ctx and M.ctx.notify then
		M.ctx.notify(I.t(key, ...), { style = "info" })
	end
end

local function notify_playing(it)
	if it then
		toast("now playing: %s", truncate(it.title, 32))
	end
end

-- play modes: seq advances and stops after the last track, loop wraps,
-- single repeats the current track, shuffle jumps to a random track
local MODES = { "seq", "loop", "single", "shuffle" }
local MODE_SET = { seq = true, loop = true, single = true, shuffle = true }
local MODE_LABEL = { seq = "sequential", loop = "loop", single = "single", shuffle = "shuffle" }
math.randomseed(os.time())

-- mode icons drawn with rect primitives (panel font lacks →/∞/①/⇄ glyphs);
-- each fits a 16px box with 2px strokes
local function draw_mode_icon(p, mode, x, y, T)
	local col = T.primary
	if mode == "seq" then
		-- right arrow: bar + stacked-rect head
		p:rect(x + 1, y + 7, 9, 2, col)
		p:rect(x + 10, y + 4, 2, 8, col)
		p:rect(x + 12, y + 6, 2, 4, col)
		p:rect(x + 14, y + 7, 2, 2, col)
	elseif mode == "loop" then
		-- broken ring with a clockwise arrowhead
		p:rect(x + 3, y + 2, 9, 2, col)
		p:rect(x + 3, y + 12, 10, 2, col)
		p:rect(x + 1, y + 4, 2, 8, col)
		p:rect(x + 13, y + 6, 2, 6, col)
		p:rect(x + 11, y + 4, 4, 2, col)
		p:rect(x + 12, y + 6, 2, 2, col)
	elseif mode == "single" then
		-- circled bar (①-like): ring + center vertical bar
		p:rect(x + 3, y + 1, 10, 2, col)
		p:rect(x + 3, y + 13, 10, 2, col)
		p:rect(x + 1, y + 3, 2, 10, col)
		p:rect(x + 13, y + 3, 2, 10, col)
		p:rect(x + 7, y + 5, 2, 6, col)
	else
		-- shuffle: two crossing stepped arrows with stacked-rect heads
		p:rect(x + 1, y + 11, 3, 2, col)
		p:rect(x + 4, y + 9, 3, 2, col)
		p:rect(x + 7, y + 7, 3, 2, col)
		p:rect(x + 10, y + 5, 3, 2, col)
		p:rect(x + 13, y + 3, 2, 2, col)
		p:rect(x + 12, y + 5, 4, 2, col)
		p:rect(x + 1, y + 5, 3, 2, col)
		p:rect(x + 4, y + 7, 3, 2, col)
		p:rect(x + 7, y + 9, 3, 2, col)
		p:rect(x + 10, y + 11, 3, 2, col)
		p:rect(x + 13, y + 13, 2, 2, col)
		p:rect(x + 12, y + 11, 4, 2, col)
	end
end

local function state_path()
	local home = os.getenv("HOME") or "/tmp"
	local base = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
	return base .. "/lbar/music.conf"
end

local function save_state()
	local path = M._state_path or state_path()
	local f = io.open(path, "w")
	if not f then
		local dir = path:match("^(.*/)[^/]+$")
		if dir then
			os.execute("mkdir -p '" .. dir .. "' 2>/dev/null")
		end
		f = io.open(path, "w")
		if not f then
			return
		end
	end
	local cur = (M.cur > 0) and M.playlist and M.playlist[M.cur] or nil
	f:write(string.format("volume = %d\n", M.volume or 80))
	f:write("track = " .. (cur and cur.path or "") .. "\n")
	f:write("mode = " .. (MODE_SET[M.mode] and M.mode or "seq") .. "\n")
	f:close()
end

local function load_state()
	local f = io.open(M._state_path or state_path(), "r")
	if not f then
		return nil
	end
	local st = {}
	for line in f:lines() do
		local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if k then
			st[k] = v
		end
	end
	f:close()
	return st
end

local function scan(dir, AUD)
	if not dir or dir == "" then
		return {}
	end
	local n = AUD.audio_scan_dir(dir)
	if n <= 0 then
		return {}
	end
	local list = {}
	for i = 0, n - 1 do
		local p = AUD.audio_scan_get(i)
		if p ~= nil then
			local path = ffi.string(p)
			list[#list + 1] = {
				idx = #list + 1,
				path = path,
				title = strip_ext(basename(path)),
				duration = nil,
			}
		end
	end
	return list
end

local L_MUSIC = "music"
local L_PREV = "prev track"
local L_NEXT = "next track"
local L_REW = "-10s"
local L_FF = "+10s"
local L_PLAY = "play"
local L_PAUSE = "pause"
local L_QUEUE = "queue"
local L_VOL = "vol"
local S_READY = "ready"
local S_PLAYING = "playing"
local S_PAUSED = "paused"
local S_STOPPED = "stopped"
local S_NO_TRK = "no track selected"

local SEEK_STEP = 10

-- MIUIX-style geometry: rounded card rows, unified side padding,
-- hint-coloured group titles. natural height follows the queue row count
-- (capped at 85% of the screen); overflow scrolls inside the view
local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		PAD = 20,
		CARD_R = 14,
		ROW_GAP = 8,
		COVER = 96,
		PROG_H = 6,
		CTRL_H = lh + 28,
		APPBAR = lh + 26,
		SECT_H = lh + 24,
		ROW_H = math.max(46, lh + 28),
		BOTBAR = lh + 24,
	}
	m.W = math.min(ctx.scr_w - 80, 920)
	m.CARD_H = 16 + m.COVER + 14 + m.PROG_H + 4 + lh + 16
	m.INFO_H = 12 + m.CARD_H + 12 + m.CTRL_H

	local top_h = m.APPBAR + m.INFO_H + m.SECT_H
	local HMAX = math.floor(ctx.scr_h * 0.85)
	local pitch = m.ROW_H + m.ROW_GAP
	local n = M.playlist and #M.playlist or 0
	m.VROWS = math.max(3, math.min(n, math.floor((HMAX - top_h - m.BOTBAR + m.ROW_GAP) / pitch)))
	if user_size then
		m.W = math.max(560, math.min(ctx.scr_w - 40, user_size.w))
		m.VROWS = math.max(3, math.floor((user_size.h - top_h - m.BOTBAR + m.ROW_GAP) / pitch))
	end
	m.H = top_h + m.VROWS * pitch - m.ROW_GAP + m.BOTBAR

	local tw = function(s)
		return ctx.text_width(s)
	end
	local wmax = math.max(tw(I.t(L_PREV)), tw(I.t(L_REW)), tw(I.t(L_PLAY)), tw(I.t(L_PAUSE)), tw(I.t(L_FF)), tw(I.t(L_NEXT)))
	m.BTN_W = wmax + 40
	m.BTN_GAP = 16
	return m
end

local function layout(m)
	local lh = m.LH
	local PAD = m.PAD
	local card_y = m.APPBAR + 12
	local card_h = m.CARD_H
	local cover_x = PAD + 16
	local cover_y = card_y + 16
	local info_x = cover_x + m.COVER + 16
	local info_w = m.W - info_x - PAD - 16
	local sect_y = m.APPBAR + m.INFO_H
	local list_y = sect_y + m.SECT_H + (m._in_extra or 0)
	local bot_y = m.H - m.BOTBAR

	local prog_x = PAD + 16
	local prog_y = cover_y + m.COVER + 14
	local prog_w = m.W - PAD * 2 - 32
	local prog_h = m.PROG_H
	local time_y = prog_y + prog_h + 4
	local ctrl_y = card_y + card_h + 12
	local ctrl_h = m.CTRL_H
	local total_w = m.BTN_W * 6 + m.BTN_GAP * 5
	local btn_x0 = math.floor((m.W - total_w) / 2)
	local pitch = m.ROW_H + m.ROW_GAP

	return {
		card_y = card_y,
		card_h = card_h,
		cover_x = cover_x,
		cover_y = cover_y,
		cover_sz = m.COVER,
		info_x = info_x,
		info_w = info_w,
		sect_y = sect_y,
		sect_h = m.SECT_H,
		list_y = list_y,
		list_end = list_y + m.VROWS * pitch - m.ROW_GAP,
		bot_y = bot_y,
		bot_h = m.BOTBAR,
		prog_x = prog_x,
		prog_y = prog_y,
		prog_w = prog_w,
		prog_h = prog_h,
		time_y = time_y,
		ctrl_y = ctrl_y,
		ctrl_h = ctrl_h,
		btn_x0 = btn_x0,
		btn_w = m.BTN_W,
		btn_gap = m.BTN_GAP,
	}
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH
	-- self-heal on resize: follow the live surface, re-derive visible rows
	-- so the list/footer always match p.w/p.h (input growth shrinks VROWS)
	m.W, m.H = p.w, p.h
	m._in_extra = p.input and p.input:extra_h() or 0
	local pitch = m.ROW_H + m.ROW_GAP
	local band = m.H - (m.APPBAR + m.INFO_H + m.SECT_H) - m.BOTBAR - m._in_extra
	m.VROWS = math.max(3, math.floor((band + m.ROW_GAP) / pitch))
	local l = layout(m)
	local tw = function(str)
		return ctx.text_width(str)
	end
	local card_w = m.W - m.PAD * 2

	local cur = (M.cur > 0) and M.playlist[M.cur] or nil

	-- scrollable content is painted FIRST; the fixed chrome (section band,
	-- footer, header) is painted on top further down, which clips every row
	-- to the view band without needing a scissor primitive

	-- now playing card: cover tile, title, seek bar, times
	p:rrect(m.PAD, l.card_y, card_w, l.card_h, m.CARD_R, T.surface)
	p:rrect(l.cover_x, l.cover_y, l.cover_sz, l.cover_sz, 12, T.surface_hi)
	local g_ts = "♪"
	local gw = tw(g_ts)
	p:text(math.floor(l.cover_x + l.cover_sz / 2 - gw / 2), math.floor(l.cover_y + l.cover_sz / 2 - lh / 2), g_ts, T.primary)

	local title = cur and cur.title or I.t(S_NO_TRK)
	p:text(l.info_x, l.cover_y + 8, truncate(title, 48), T.on_surface)

	if M.dur > 0 then
		local new_pos, changed = ui:slider("mp_prog", l.prog_x, l.prog_y, l.prog_w, M.pos, {
			min = 0,
			max = M.dur,
			track = T.surface_hi,
			color = T.primary,
			handle = T.on_surface,
		})
		if changed then
			M.pos = new_pos
			M.ctx.AUD.audio_seek(M.pos)
		end
	else
		p:rrect(l.prog_x, l.prog_y, l.prog_w, m.PROG_H, 3, T.surface_hi)
	end

	p:text(l.prog_x, l.time_y, fmt_time(M.pos), T.on_var)
	local dur_str = fmt_time(M.dur)
	local dur_w = tw(dur_str)
	p:text(l.prog_x + l.prog_w - dur_w, l.time_y, dur_str, T.hint)

	-- transport row: pill buttons (play filled, the rest tonal)
	local btns = {
		{ "prev", I.t(L_PREV), false },
		{ "rew", I.t(L_REW), false },
		{ "play", (M.playing and not M.paused) and I.t(L_PAUSE) or I.t(L_PLAY), true },
		{ "ff", I.t(L_FF), false },
		{ "next", I.t(L_NEXT), false },
		{ "mode", "", false }, -- label unused: icon drawn with primitives below
	}
	for i, item in ipairs(btns) do
		local bx = l.btn_x0 + (i - 1) * (l.btn_w + l.btn_gap)
		local clicked = ui:id_button("mp_" .. item[1], bx, l.ctrl_y, l.btn_w, l.ctrl_h, item[2],
			item[3] and { filled = true } or { tonal = true, bg = T.surface_hi })
		if item[1] == "mode" then
			draw_mode_icon(p, M.mode,
				bx + math.floor((l.btn_w - 16) / 2), l.ctrl_y + math.floor((l.ctrl_h - 16) / 2), T)
		end
		if clicked then
			local k = item[1]
			if k == "prev" then
				M.prev()
			elseif k == "rew" then
				M.seek_rel(-SEEK_STEP)
			elseif k == "play" then
				M.toggle_pause()
			elseif k == "ff" then
				M.seek_rel(SEEK_STEP)
			elseif k == "next" then
				M.next()
			elseif k == "mode" then
				M.cycle_mode()
			end
		end
	end

	-- queue rows: rounded hoverable cards, selected track highlighted
	local mx_scroll = math.max(0, #M.filtered - m.VROWS)
	M.scroll = math.min(M.scroll, mx_scroll)
	M.scroll = math.max(0, M.scroll)
	for i = 1, m.VROWS do
		local li = M.scroll + i
		if li > #M.filtered then
			break
		end
		local it = M.filtered[li]
		local ry = l.list_y + (i - 1) * pitch
		local sel = (it.idx == M.cur)
		local hovered = ui:hover(m.PAD, ry, card_w, m.ROW_H)
		p:rrect(m.PAD, ry, card_w, m.ROW_H, m.CARD_R,
			sel and T.surface_hi or (hovered and T.surface_hover or T.surface))
		local bsz = 28
		local bcy = ry + math.floor((m.ROW_H - bsz) / 2)
		local badge_bg = sel and T.primary or T.surface_hi
		local badge_fg = sel and T.on_primary or T.on_var
		p:rrect(m.PAD + 12, bcy, bsz, bsz, 8, badge_bg)
		local num_str = string.format("%d", it.idx)
		local nw = tw(num_str)
		p:text(math.floor(m.PAD + 12 + bsz / 2 - nw / 2), math.floor(bcy + (bsz - lh) / 2), num_str, badge_fg)
		local tx = m.PAD + 12 + bsz + 14
		local ty = ry + math.floor((m.ROW_H - lh) / 2)
		p:text(tx, ty, truncate(it.title, 60), sel and T.on_surface or T.on_var)
		if it.duration then
			local ds = fmt_time(it.duration)
			local dw = tw(ds)
			p:text(m.PAD + card_w - 16 - dw, ty, ds, T.hint)
		end
		if ui:clicked(m.PAD, ry, card_w, m.ROW_H) then
			M.play_idx(it.idx)
			notify_playing(it)
		end
	end

	-- scrollbar (right edge, over the panel background)
	if mx_scroll > 0 then
		local track_h = m.VROWS * pitch - m.ROW_GAP
		local bh = math.max(32, math.floor(track_h * m.VROWS / #M.filtered))
		local by = l.list_y + math.floor((track_h - bh) * M.scroll / mx_scroll)
		p:rrect(m.W - 6, by, 4, bh, 2, T.outline)
	end

	-- section band painted after the rows so nothing can scroll over it:
	-- hint-coloured group title, track count and the search input
	p:rect(0, l.sect_y, m.W, l.sect_h + m._in_extra, p.bg)
	local sy = l.sect_y + math.floor((l.sect_h - lh) / 2)
	p:text(m.PAD + 6, sy, I.t(L_QUEUE), T.hint)
	local cnt = string.format("%d / %d", M.cur, #M.playlist)
	local cnt_w = tw(cnt)
	p:text(m.W - m.PAD - cnt_w, sy, cnt, T.hint)

	local sq_w = 260
	local sq_h = lh + 18
	local sq_x = m.W - m.PAD - cnt_w - 16 - sq_w
	local sq_y = l.sect_y + math.floor((l.sect_h - sq_h) / 2)
	p.input:set_rect(sq_x, sq_y, sq_w, sq_h)
	p.input:draw(p)

	-- footer: opaque band covers rows scrolled past the bottom
	p:rect(0, l.bot_y, m.W, l.bot_h, p.bg)
	p:rect(m.PAD, l.bot_y, m.W - m.PAD * 2, 1, T.outline)
	local bty = l.bot_y + math.floor((l.bot_h - lh) / 2)
	local status
	if M.cur == 0 then
		status = I.t(S_READY)
	elseif M.paused then
		status = I.t(S_PAUSED)
	elseif M.playing then
		status = I.t(S_PLAYING)
	else
		status = I.t(S_STOPPED)
	end
	local dot_col = (M.playing and not M.paused) and T.good or T.outline
	p:rrect(m.PAD, bty + math.floor(lh / 2) - 4, 8, 8, 4, dot_col)
	p:text(m.PAD + 20, bty, status, T.on_var)

	if M.search_query ~= "" then
		local hint = I.t("filter %d / %d", #M.filtered, #M.playlist)
		local hw = tw(hint)
		p:text(math.floor(m.W / 2 - hw / 2), bty, hint, T.hint)
	end

	local pct_str = string.format("%d%%", M.volume)
	local pct_w = tw(pct_str)
	local vol_w = 100
	local vol_x = m.W - m.PAD - pct_w - 12 - vol_w
	local vol_lbl_w = tw(I.t(L_VOL))
	p:text(vol_x - 12 - vol_lbl_w, bty, I.t(L_VOL), T.on_var)
	local new_vol, changed = ui:slider("mp_vol", vol_x, bty + math.floor(lh / 2) - 2, vol_w, M.volume, {
		min = 0,
		max = 100,
		track = T.surface_hi,
		color = T.good,
		handle = T.on_surface,
	})
	if changed then
		M.set_volume_pct(new_vol)
	end
	p:text(m.W - m.PAD - pct_w, bty, pct_str, T.on_var)

	-- header LAST: opaque band covers anything painted under it
	p:draw_header(I.t("music player"), Util.keybind_hint(ctx, "toggle_music_player"), m.PAD)
end

function M.bar_label()
	local cur = (M.cur > 0) and M.playlist and M.playlist[M.cur] or nil
	if not cur then
		return I.t("♪ music")
	end
	local mark = (M.playing and not M.paused) and "▶ " or "♪ "
	return mark .. truncate(cur.title, 26)
end

function M.width(ctx)
	return ctx.text_width(M.bar_label()) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local T = ctx.theme
	local active = ctx.active_plugin_name == "music_player" and ctx.popup_visible
	local col = active and T.primary
		or ((M.playing and not M.paused) and T.on_surface or T.on_var)
	s:text(x + 10, math.floor((h - lh) / 2), M.bar_label(), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "music_player", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = false
	M._state_path = ctx.config.music_state_file or state_path()
	if not ctx.AUD then
		log("audio lib missing")
		return
	end
	if ctx.AUD.audio_init() ~= 0 then
		log("audio init failed")
		return
	end
	M.ready = true

	local S = ctx._music_state
	if not S then
		S = load_state()
	end
	S = S or {}
	M.volume = tonumber(S.volume) or 80
	M.scroll = tonumber(S.scroll) or 0
	M.cur = tonumber(S.cur) or 0
	M.mode = MODE_SET[S.mode] and S.mode or "seq"
	ctx.AUD.audio_set_volume(M.volume)

	local panel = Panel.new(ctx, {
		name = "music_player",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = I.t("ctrl+f search"),
			on_change = function(v)
				M.search_query = v
				M.apply_filter()
			end,
			on_submit = function()
				M.panel:blur_input()
			end,
			on_cancel = function()
				M.panel:hide()
			end,
		},
		on_key = function(p, sym, text, ctrl, shift, state)
			if ctrl and sym == 0x66 then
				p.input:focus()
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				local l = layout(p.m)
				if my >= l.list_y and my < l.list_end then
					if btn == 4 then
						M.scroll = math.max(0, M.scroll - 1)
					else
						local mx_scroll = math.max(0, #M.filtered - p.m.VROWS)
						M.scroll = math.min(mx_scroll, M.scroll + 1)
					end
					p:draw()
				end
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("music_player", panel)

	M.playlist = scan(ctx.config.audio_panel_dir, ctx.AUD)
	M._fit_tracks = #M.playlist
	-- size_fn depends on the queue row count: refit from the first tick
	M.need_fit = true
	M._state_track = (S.track and S.track ~= "") and S.track or nil
	M._rescan = (#M.playlist == 0)
	if S.track and S.track ~= "" then
		for i, it in ipairs(M.playlist) do
			if it.path == S.track then
				M.cur = i
				break
			end
		end
	end
	M.filtered = M.playlist
	M.playing = false
	M.paused = false
	M.pos = 0
	M.dur = 0
	M.redraw = false
	M.poll = 0
	M.probe = 1
	M.search_query = ""
	M.need_fit = true

	log("ready: %d tracks", #M.playlist)
end

function M:apply_filter()
	local q = M.search_query
	if not q or q == "" then
		M.filtered = M.playlist
	else
		local ql = q:lower()
		local out = {}
		for _, it in ipairs(M.playlist) do
			if it.title:lower():find(ql, 1, true) then
				out[#out + 1] = it
			end
		end
		M.filtered = out
	end
	local mx = math.max(0, #M.filtered - M.panel.m.VROWS)
	M.scroll = math.min(M.scroll, mx)
	M.scroll = math.max(0, M.scroll)
end

function M.toggle()
	if not M.ready then
		M.ctx.notify(I.t("audio unavailable"), { style = "error" })
		return
	end
	M.panel:toggle()
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	local A = M.ctx.AUD
	local p = M.panel
	-- content-driven size changes (queue length) refit from tick — never
	-- from draw; fit() no-ops if the natural size is unchanged
	if M.need_fit then
		M.need_fit = false
		p:fit()
	end
	if A.audio_finished() == 1 and M.playing and M.cur > 0 then
		M.on_track_end()
	end
	M.poll = M.poll + dt
	if M.poll >= 200 then
		M.poll = 0
		-- initial scan found nothing: retry while empty (dir may only become
		-- readable later); when tracks land, restore the recorded track but
		-- never autoplay — next play press handles it
		if M._rescan and #M.playlist == 0 then
			local list = scan(M.ctx.config.audio_panel_dir, A)
			if #list > 0 then
				M._rescan = false
				M.playlist = list
				M.apply_filter()
				local want = M._state_track
				if want then
					for j, it in ipairs(list) do
						if it.path == want then
							M.cur = j
							break
						end
					end
				end
				M.redraw = true
			end
		end
		-- auto-fit when a content-driven size input changed (playlist size is
		-- the only data-dependent term in size_fn)
		if M._fit_tracks ~= #M.playlist then
			M._fit_tracks = #M.playlist
			M.need_fit = true
		end
		local pl = A.audio_is_playing() ~= 0
		local pa = A.audio_is_paused() ~= 0
		local po = A.audio_get_position()
		local du = A.audio_get_duration()
		if pl ~= M.playing or pa ~= M.paused or po ~= M.pos or du ~= M.dur then
			M.playing, M.paused, M.pos, M.dur = pl, pa, po, du
			M.redraw = true
			ctx.bar.needs_redraw = true
		end
	end
	if M.probe <= #M.playlist then
		local it = M.playlist[M.probe]
		if not it.duration then
			local d = A.audio_probe_duration(it.path)
			if d and d > 0 and d < 3600 then
				it.duration = d
			end
			M.redraw = true
		end
		M.probe = M.probe + 1
	end
	if M.redraw and p.visible then
		p:draw()
		M.redraw = false
	end
end

function M.play_idx(i)
	if i < 1 or i > #M.playlist then
		return
	end
	M.cur = i
	if M.ctx.AUD.audio_play(M.playlist[i].path) == 0 then
		-- audio_play started the stream synchronously: mirror it so the
		-- play/pause icon and status reflect reality on the next draw
		M.playing, M.paused, M.pos, M.dur = true, false, 0, 0
		if M.ctx.bar then
			M.ctx.bar.needs_redraw = true
		end
	end
	M.redraw = true
	save_state()
end

function M.toggle_pause()
	local A = M.ctx.AUD
	if M.cur == 0 then
		local want = M._state_track
		if want and want ~= "" then
			for j, it in ipairs(M.playlist) do
				if it.path == want then
					M.play_idx(j)
					toast("playback started")
					return
				end
			end
		end
		if #M.playlist > 0 then
			M.play_idx(1)
			toast("playback started")
		else
			M.ctx.notify(I.t("scanning…"), { style = "info" })
		end
		return
	end
	-- restored/selected track but no stream ever started: audio_toggle_pause
	-- no-ops on an unloaded music, so begin playback instead
	if A.audio_is_playing() == 0 and A.audio_is_paused() == 0 then
		M.play_idx(M.cur)
		toast("playback started")
		return
	end
	local was_playing = M.playing and not M.paused
	A.audio_toggle_pause()
	M.redraw = true
	toast(was_playing and "paused" or "playback started")
end

function M.next()
	if #M.playlist == 0 then
		return
	end
	M.play_idx(M.cur % #M.playlist + 1)
	notify_playing(M.playlist[M.cur])
end

function M.prev()
	if #M.playlist == 0 then
		return
	end
	local p = M.cur - 1
	if p < 1 then
		p = #M.playlist
	end
	M.play_idx(p)
	notify_playing(M.playlist[p])
end

function M.set_mode(m)
	if not MODE_SET[m] or m == M.mode then
		return
	end
	M.mode = m
	M.redraw = true
	if M.ctx and M.ctx.notify then
		M.ctx.notify(I.t("play mode: %s", I.t(MODE_LABEL[m])), { style = "info" })
	end
	save_state()
end

function M.cycle_mode()
	for i, m in ipairs(MODES) do
		if m == M.mode then
			M.set_mode(MODES[i % #MODES + 1])
			return
		end
	end
	M.set_mode("seq")
end

-- auto-advance on engine finish; audio_finished() is one-shot (the engine
-- clears playing on read and audio_play re-arms it), so no double-trigger;
-- seq stops at queue end without autoplaying anything new
function M.on_track_end()
	if M.cur == 0 or #M.playlist == 0 then
		return
	end
	local n = #M.playlist
	if M.mode == "single" then
		M.play_idx(M.cur)
		return
	end
	if M.mode == "shuffle" then
		if n <= 1 then
			M.play_idx(M.cur)
			return
		end
		local j = M.cur
		while j == M.cur do
			j = math.random(n)
		end
		M.play_idx(j)
		return
	end
	if M.mode == "seq" and M.cur >= n then
		M.playing, M.paused = false, false
		M.redraw = true
		if M.ctx.bar then
			M.ctx.bar.needs_redraw = true
		end
		return
	end
	M.play_idx(M.cur % n + 1)
end

function M.seek_rel(delta)
	if M.dur <= 0 then
		return
	end
	local t = math.max(0, math.min(M.dur, M.pos + delta))
	M.pos = t
	M.ctx.AUD.audio_seek(t)
	M.redraw = true
end

function M.set_volume_pct(v)
	M.volume = math.max(0, math.min(100, math.floor(v)))
	M.ctx.AUD.audio_set_volume(M.volume)
	M.redraw = true
	save_state()
end

function M.shutdown()
	save_state()
	if M.ctx then
		M.ctx._music_state = {
			volume = M.volume,
			scroll = M.scroll,
			cur = M.cur,
			mode = M.mode,
		}
	end
	M.ctx = nil
	M.ready = false
	M.need_fit = false
end

return M
