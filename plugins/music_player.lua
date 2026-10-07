local M = {}
local ffi = require("ffi")
local Panel = require("core.panel")
local Util = require("core.util")

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
local L_PREV = "prev"
local L_NEXT = "next"
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

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local PAD = 24
	local m = {
		LH = lh,
		PAD = PAD,
		COVER = 96,
		CTRL_H = lh + 28,
		APPBAR = lh + 26,
		SECT_H = lh + 16,
		ROW_H = lh + 22,
		BOTBAR = lh + 20,
	}
	m.W = math.min(ctx.scr_w - 80, 920)
	m.INFO_H = 20 + m.COVER + 16 + 6 + (lh + 4) + 12 + m.CTRL_H + 20

	local top_h = m.APPBAR + m.INFO_H + m.SECT_H
	local HMAX = math.min(ctx.scr_h - 120, 700)
	m.VROWS = math.max(3, math.floor((HMAX - top_h - m.BOTBAR) / m.ROW_H))
	if user_size then
		m.W = math.max(560, math.min(ctx.scr_w - 40, user_size.w))
		m.VROWS = math.max(3, math.floor((user_size.h - top_h - m.BOTBAR) / m.ROW_H))
	end
	m.H = top_h + m.VROWS * m.ROW_H + m.BOTBAR

	local tw = function(s)
		return select(1, ctx.get_text_size(s))
	end
	local wmax = math.max(tw(L_PREV), tw(L_REW), tw(L_PLAY), tw(L_FF), tw(L_NEXT))
	m.BTN_W = wmax + 40
	m.BTN_GAP = 16
	return m
end

local function layout(m)
	local lh = m.LH
	local PAD = m.PAD
	local app_h = m.APPBAR
	local info_y = app_h
	local sect_y = info_y + m.INFO_H
	local list_y = sect_y + m.SECT_H
	local bot_y = m.H - m.BOTBAR

	local cover_x = PAD
	local cover_y = info_y + 20
	local info_x = cover_x + m.COVER + 20
	local info_w = m.W - info_x - PAD

	local prog_x = PAD
	local prog_y = cover_y + m.COVER + 16
	local prog_w = m.W - PAD * 2
	local prog_h = 6
	local time_y = prog_y + prog_h + 4
	local ctrl_y = time_y + lh + 8
	local ctrl_h = m.CTRL_H
	local total_w = m.BTN_W * 5 + m.BTN_GAP * 4
	local btn_x0 = math.floor((m.W - total_w) / 2)

	return {
		app_h = app_h,
		info_y = info_y,
		sect_y = sect_y,
		sect_h = m.SECT_H,
		list_y = list_y,
		list_end = bot_y,
		bot_y = bot_y,
		bot_h = m.BOTBAR,
		cover_x = cover_x,
		cover_y = cover_y,
		cover_sz = m.COVER,
		info_x = info_x,
		info_w = info_w,
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
	local l = layout(m)
	local tw = function(str)
		return select(1, ctx.get_text_size(str))
	end

	p:draw_header(L_MUSIC, Util.keybind_hint(ctx, "toggle_music_player"), m.PAD)
	local cur = (M.cur > 0) and M.playlist[M.cur] or nil

	p:rrect(l.cover_x, l.cover_y, l.cover_sz, l.cover_sz, 20, T.surface_hi)
	local g_ts = "♪"
	local gw = tw(g_ts)
	p:text(math.floor(l.cover_x + l.cover_sz / 2 - gw / 2), math.floor(l.cover_y + l.cover_sz / 2 - lh / 2), g_ts, T.primary)

	local title = cur and cur.title or S_NO_TRK
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
		p:rrect(l.prog_x, l.prog_y, l.prog_w, 6, 3, T.surface_hi)
	end

	p:text(l.prog_x, l.time_y, fmt_time(M.pos), T.on_var)
	local dur_str = fmt_time(M.dur)
	local dur_w = tw(dur_str)
	p:text(l.prog_x + l.prog_w - dur_w, l.time_y, dur_str, T.on_var)

	local btns = {
		{ "prev", L_PREV, false },
		{ "rew", L_REW, false },
		{ "play", (M.playing and not M.paused) and L_PAUSE or L_PLAY, true },
		{ "ff", L_FF, false },
		{ "next", L_NEXT, false },
	}
	for i, item in ipairs(btns) do
		local bx = l.btn_x0 + (i - 1) * (l.btn_w + l.btn_gap)
		if ui:id_button("mp_" .. item[1], bx, l.ctrl_y, l.btn_w, l.ctrl_h, item[2], { filled = item[3] }) then
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
			end
		end
	end

	p:rect(0, l.sect_y, m.W, l.sect_h, T.bg)
	local sy = l.sect_y + math.floor((l.sect_h - lh) / 2)
	p:text(m.PAD, sy, L_QUEUE, T.primary)
	local cnt = string.format("%d / %d", M.cur, #M.playlist)
	local cnt_w = tw(cnt)
	p:text(m.W - m.PAD - cnt_w, sy, cnt, T.hint)

	local sq_w = 260
	local sq_h = lh + 4
	local sq_x = m.W - m.PAD - cnt_w - 16 - sq_w
	local sq_y = l.sect_y + math.floor((l.sect_h - sq_h) / 2)
	p.input:set_rect(sq_x, sq_y, sq_w, sq_h)
	p.input:draw(p)
	p:rect(0, l.sect_y + l.sect_h - 1, m.W, 1, T.outline)

	local mx_scroll = math.max(0, #M.filtered - m.VROWS)
	for i = 1, m.VROWS do
		local li = M.scroll + i
		if li > #M.filtered then
			break
		end
		local it = M.filtered[li]
		local ry = l.list_y + (i - 1) * m.ROW_H
		local sel = (it.idx == M.cur)
		local row_bg = sel and T.surface_hi or T.bg
		p:rect(0, ry, m.W, m.ROW_H, row_bg)
		if sel then
			p:rect(0, ry, 4, m.ROW_H, T.primary)
		end
		local bsz = 28
		local bcy = ry + math.floor((m.ROW_H - bsz) / 2)
		local badge_bg = sel and T.primary or T.surface_hi
		local badge_fg = sel and T.on_primary or T.on_var
		p:rrect(m.PAD, bcy, bsz, bsz, 8, badge_bg)
		local num_str = string.format("%d", it.idx)
		local nw = tw(num_str)
		p:text(math.floor(m.PAD + bsz / 2 - nw / 2), math.floor(bcy + (bsz - lh) / 2), num_str, badge_fg)
		local tx = m.PAD + bsz + 16
		local ty = ry + math.floor((m.ROW_H - lh) / 2)
		p:text(tx, ty, truncate(it.title, 60), sel and T.on_surface or T.on_var)
		if it.duration then
			local ds = fmt_time(it.duration)
			local dw = tw(ds)
			p:text(m.W - m.PAD - dw, ty, ds, T.hint)
		end
		if i < m.VROWS and li < #M.filtered then
			p:rect(m.PAD, ry + m.ROW_H - 1, m.W - m.PAD * 2, 1, T.outline)
		end
		if ui:clicked(0, ry, m.W, m.ROW_H) then
			M.play_idx(it.idx)
		end
	end

	if mx_scroll > 0 then
		local track_h = m.VROWS * m.ROW_H
		local bh = math.max(32, math.floor(track_h * m.VROWS / #M.filtered))
		local by = l.list_y + math.floor((track_h - bh) * M.scroll / mx_scroll)
		p:rrect(m.W - 6, by, 4, bh, 2, T.outline)
	end

	p:rect(0, l.bot_y, m.W, l.bot_h, T.surface)
	p:rect(0, l.bot_y, m.W, 1, T.outline)
	local bty = l.bot_y + math.floor((l.bot_h - lh) / 2)
	local status
	if M.cur == 0 then
		status = S_READY
	elseif M.paused then
		status = S_PAUSED
	elseif M.playing then
		status = S_PLAYING
	else
		status = S_STOPPED
	end
	local dot_col = (M.playing and not M.paused) and T.good or T.outline
	p:rrect(m.PAD, bty + math.floor(lh / 2) - 4, 8, 8, 4, dot_col)
	p:text(m.PAD + 20, bty, status, T.on_var)

	if M.search_query ~= "" then
		local hint = string.format("filter %d / %d", #M.filtered, #M.playlist)
		local hw = tw(hint)
		p:text(math.floor(m.W / 2 - hw / 2), bty, hint, T.hint)
	end

	local pct_str = string.format("%d%%", M.volume)
	local pct_w = tw(pct_str)
	local vol_w = 100
	local vol_x = m.W - m.PAD - pct_w - 12 - vol_w
	local vol_lbl_w = tw(L_VOL)
	p:text(vol_x - 12 - vol_lbl_w, bty, L_VOL, T.on_var)
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
end

function M.bar_label()
	local cur = (M.cur > 0) and M.playlist and M.playlist[M.cur] or nil
	if not cur then
		return "♪ music"
	end
	local mark = (M.playing and not M.paused) and "▶ " or "♪ "
	return mark .. truncate(cur.title, 26)
end

function M.width(ctx)
	return select(1, ctx.get_text_size(M.bar_label())) + 20
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
			placeholder = "ctrl+f search",
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
		M.ctx.notify("audio unavailable", { style = "error" })
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
	if A.audio_finished() == 1 and #M.playlist > 0 then
		M.next()
	end
	M.poll = M.poll + dt
	if M.poll >= 200 then
		M.poll = 0
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
	M.ctx.AUD.audio_play(M.playlist[i].path)
	M.redraw = true
	save_state()
end

function M.toggle_pause()
	if M.cur == 0 then
		if #M.playlist > 0 then
			M.play_idx(1)
		end
		return
	end
	M.ctx.AUD.audio_toggle_pause()
	M.redraw = true
end

function M.next()
	if #M.playlist == 0 then
		return
	end
	M.play_idx(M.cur % #M.playlist + 1)
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
		}
	end
	M.ctx = nil
	M.ready = false
end

return M
