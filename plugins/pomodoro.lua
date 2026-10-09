local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("pomodoro")
local keybind_hint = Util.keybind_hint

local L_TITLE = "Pomodoro"
local L_FOCUS = "focus"
local L_BREAK = "break"
local L_START = "start"
local L_PAUSE = "pause"
local L_RESET = "reset"

local function fmt_ms(ms)
	local s = math.max(0, math.ceil(ms / 1000))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- toast feedback for user-triggered key actions (start / pause / reset)
local function toast(key)
	if M.ctx and M.ctx.notify then
		M.ctx.notify(I.t(key), { style = "info" })
	end
end

-- MIUIX-style geometry: hero card + segmented mode control on the panel
-- background, footer band with pill buttons; natural height follows the
-- content rows (capped at 85% of the screen)
local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		PAD = 20,
		CARD_R = 14,
		ROW_GAP = 8,
		APPBAR = lh + 26,
		HERO_H = lh + 46,
		PROG_H = 6,
		SEG_H = lh + 18,
		FOOTER_H = lh + 30,
		W = 380,
	}
	local H = m.APPBAR + 16 + m.HERO_H + m.ROW_GAP + m.SEG_H + m.ROW_GAP + 16 + m.FOOTER_H
	m.H = math.min(math.floor(ctx.scr_h * 0.85), H)
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH
	m.W, m.H = p.w, p.h
	local W, PAD = m.W, m.PAD
	local card_w = W - PAD * 2
	local tw = function(str)
		return ctx.text_width(str)
	end

	-- scrollable content is painted FIRST; the fixed chrome (footer, header)
	-- is painted on top further down, which clips it without a scissor

	-- hero card: big countdown + progress inside one rounded card
	local y = m.APPBAR + 16
	local is_focus = M.mode == "focus"
	local tcol = M.running and (is_focus and T.primary or T.good) or T.on_var
	p:rrect(PAD, y, card_w, m.HERO_H, m.CARD_R, T.surface)
	local tstr = fmt_ms(M.remaining)
	p:text(math.floor(W / 2 - tw(tstr) / 2), y + 12, tstr, tcol)
	local frac = 1 - math.max(0, M.remaining) / M.total
	local pw = card_w - 32
	local py = y + 12 + lh + 12
	p:rrect(PAD + 16, py, pw, m.PROG_H, 3, T.surface_hi)
	if frac > 0 then
		local fw = math.max(6, math.floor(pw * frac))
		p:rrect(PAD + 16, py, fw, m.PROG_H, 3, is_focus and T.primary or T.good)
	end
	y = y + m.HERO_H + m.ROW_GAP

	-- segmented mode control: shared MIUI segmented widget
	local sel = ui:segmented(PAD, y, card_w, m.SEG_H,
		{ I.t(L_FOCUS), I.t(L_BREAK) }, M.mode == "focus" and 1 or 2)
	if sel > 0 then
		M.set_mode(sel == 1 and "focus" or "break")
	end

	-- footer: opaque band covers content scrolled past the bottom; pill
	-- buttons laid out like a MIUI dialog (primary action filled)
	local fy = m.H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local dstr = I.t("completed %d", M.done)
	p:text(PAD, fy + math.floor((m.FOOTER_H - lh) / 2), dstr, T.hint)
	local bh = lh + 14
	local bo = fy + math.floor((m.FOOTER_H - bh) / 2)
	local bw = 96
	if ui:id_button("pomo_run", W - PAD - bw * 2 - 10, bo, bw, bh,
		M.running and I.t(L_PAUSE) or I.t(L_START), { filled = true }) then
		M.toggle_run()
	end
	if ui:id_button("pomo_reset", W - PAD - bw, bo, bw, bh, I.t(L_RESET),
		{ tonal = true, bg = T.surface_hi }) then
		M.reset_timer()
	end

	-- header LAST: opaque band covers anything painted under it
	p:draw_header(I.t(L_TITLE), M.hint, PAD)
end

function M.bar_label()
	if M.running then
		return I.t(M.mode == "focus" and L_FOCUS or L_BREAK) .. " " .. fmt_ms(M.remaining)
	end
	return I.t("pomo") .. " " .. fmt_ms(M.remaining)
end

function M.width(ctx)
	return ctx.text_width(M.bar_label()) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local T = ctx.theme
	local active = ctx.active_plugin_name == "pomodoro" and ctx.popup_visible
	local col = active and T.primary
		or (M.running and (M.mode == "focus" and T.primary or T.good) or T.on_var)
	s:text(x + 10, math.floor((h - lh) / 2), M.bar_label(), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "pomodoro", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	local S = ctx._pomo_state or {}
	local cfg = ctx.config.pomodoro or {}
	M.work_ms = (cfg.work_min or 25) * 60000
	M.break_ms = (cfg.break_min or 5) * 60000
	M.mode = S.mode or "focus"
	M.running = S.running or false
	M.done = S.done or 0
	M.total = M.mode == "focus" and M.work_ms or M.break_ms
	M.remaining = S.remaining or M.total
	if M.remaining > M.total then
		M.remaining = M.total
	end
	M.last_sec = -1
	M.hint = keybind_hint(ctx, "toggle_pomodoro")

	local panel = Panel.new(ctx, {
		name = "pomodoro",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("pomodoro", panel)
	log("ready: focus=%dmin break=%dmin", math.floor(M.work_ms / 60000), math.floor(M.break_ms / 60000))
end

function M.tick(ctx, dt)
	if not M.panel then
		return
	end
	if M.running then
		M.remaining = M.remaining - dt
		if M.remaining <= 0 then
			M.finish()
			return
		end
		local sec = math.ceil(M.remaining / 1000)
		if sec ~= M.last_sec then
			M.last_sec = sec
			ctx.bar.needs_redraw = true
			if M.panel.visible then
				M.panel:draw()
			end
		end
	end
end

function M.finish()
	M.running = false
	if M.mode == "focus" then
		M.done = M.done + 1
		M.mode = "break"
		M.ctx.notify(I.t("pomodoro #%d done, take a break", M.done), { style = "success" })
	else
		M.mode = "focus"
		M.ctx.notify(I.t("break over, next pomodoro"), { style = "info" })
	end
	M.total = M.mode == "focus" and M.work_ms or M.break_ms
	M.remaining = M.total
	M.last_sec = -1
	if M.panel.visible then
		M.panel:draw()
	end
end

function M.set_mode(m)
	if M.mode == m then
		return
	end
	M.mode = m
	M.running = false
	M.total = m == "focus" and M.work_ms or M.break_ms
	M.remaining = M.total
	M.last_sec = -1
	M.panel:draw()
end

function M.toggle_run()
	M.running = not M.running
	M.last_sec = -1
	M.panel:draw()
	toast(M.running and "timer started" or "timer paused")
end

function M.reset_timer()
	M.running = false
	M.remaining = M.total
	M.last_sec = -1
	M.panel:draw()
	toast("timer reset")
end

function M.shutdown()
	if M.ctx then
		M.ctx._pomo_state = {
			mode = M.mode,
			running = M.running,
			done = M.done,
			remaining = M.remaining,
		}
	end
	M.ctx = nil
end

return M
