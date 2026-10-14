-- plugins/brightness.lua — screen brightness bar item + panel (brightnessctl)
-- wheel on the bar item adjusts brightness; click opens a slider panel
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("brightness")
local XK_ESCAPE = 0xff1b

-- os.execute returns the raw exit status (0 = success) or true depending on
-- the LuaJIT build; accept both so HAVE_BRIGHTNESS is correct everywhere
local HAVE_BRIGHTNESS = (function()
	local r = os.execute("command -v brightnessctl >/dev/null 2>&1")
	return r == true or r == 0
end)()
local bright = 0
local have_state = false
local last = 0
local pending_vol, pending_wait = nil, 0
local REFRESH_MS = 15000

local function bctl_out(args)
	local p = io.popen("brightnessctl " .. args .. " 2>/dev/null")
	if not p then
		return ""
	end
	local out = p:read("*a")
	p:close()
	return out or ""
end

local function refresh()
	if not HAVE_BRIGHTNESS then
		return
	end
	local cur = tonumber(bctl_out("get"))
	local max = tonumber(bctl_out("max"))
	if cur and max and max > 0 then
		bright = math.floor(cur / max * 100 + 0.5)
		have_state = true
	end
end

local function set_bright(v)
	v = math.max(1, math.min(100, math.floor(v + 0.5)))
	bright = v
	have_state = true
	os.execute(string.format("brightnessctl set %d%% >/dev/null 2>&1", v))
end

local function str()
	if not have_state then
		return I.t("BRI -")
	end
	return I.t("BRI %d%%", bright)
end

-- MIUIX-style geometry: card rows on the panel background, footer band
-- with pill buttons; natural height follows the content rows (capped at
-- 85% of the screen)
local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 20, CARD_R = 14, ROW_GAP = 8 }
	m.W = 380
	m.HEADER_H = lh + 26
	m.ROW_H = math.max(46, lh + 28)
	m.HERO_H = lh + 44
	m.FOOTER_H = lh + 30
	local H = m.HEADER_H + 16 + m.HERO_H + m.ROW_GAP + m.ROW_H + 16 + m.FOOTER_H
	m.H = math.min(math.floor(ctx.scr_h * 0.85), H)
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	m.W, m.H = p.w, p.h
	local lh, PAD, W = m.lh, m.PAD, m.W
	local card_w = W - PAD * 2

	-- scrollable content is painted FIRST; the fixed chrome (footer, header)
	-- is painted on top further down, which clips it without a scissor

	-- hero card: big percentage
	local y = m.HEADER_H + 16
	p:rrect(PAD, y, card_w, m.HERO_H, m.CARD_R, T.surface)
	local big = string.format("%d%%", bright)
	local big_w = ctx.text_width(big)
	p:text(math.floor((W - big_w) / 2), y + math.floor((m.HERO_H - lh) / 2), big, T.primary)
	y = y + m.HERO_H + m.ROW_GAP

	-- slider row card
	p:rrect(PAD, y, card_w, m.ROW_H, m.CARD_R, T.surface)
	local sw = card_w - 32
	local v, changed = ui:slider("bri_slider", PAD + 16, y + math.floor(m.ROW_H / 2), sw, bright, { min = 1, max = 100 })
	if changed then
		pending_vol = v
		pending_wait = 150
	end

	-- footer: opaque band covers rows scrolled past the bottom; pill
	-- buttons laid out like a MIUI dialog
	local fy = m.H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local bh = lh + 14
	local bo = fy + math.floor((m.FOOTER_H - bh) / 2)
	local bw = 72
	local bx = math.floor((W - (bw * 2 + 10)) / 2)
	if ui:id_button("bri_dn", bx, bo, bw, bh, "-5", { tonal = true, bg = T.surface_hi }) then
		pending_vol = nil
		set_bright(bright - 5)
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
	end
	if ui:id_button("bri_up", bx + bw + 10, bo, bw, bh, "+5", { tonal = true, bg = T.surface_hi }) then
		pending_vol = nil
		set_bright(bright + 5)
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
	end

	-- header LAST: opaque band covers anything painted under it
	p:draw_header(I.t("brightness"), Util.keybind_hint(ctx, "toggle_brightness"), PAD)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	if not HAVE_BRIGHTNESS then
		log("brightnessctl not found — plugin disabled")
		return
	end
	refresh()
	local panel = Panel.new(ctx, {
		name = "brightness",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(300, us.w)
				m.H = math.max(220, us.h)
			end
			return m
		end,
		size_fn = function(c)
			local m = compute_layout(c, c.get_line_height())
			return m.W, m.H
		end,
		draw = do_draw,
		on_key = function(p, sym)
			if sym == XK_ESCAPE then
				p:hide()
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
		on_show = function(p)
			refresh()
			p:draw()
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("brightness", panel)
	log("ready: %d%%", bright)
end

function M.width(ctx)
	if not HAVE_BRIGHTNESS or not have_state then
		return 0
	end
	return ctx.text_width(str()) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "brightness" and ctx.popup_visible
	local col = active and ctx.theme.primary or ctx.theme.on_surface
	s:text(x + 10, math.floor((h - lh) / 2), str(), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if not HAVE_BRIGHTNESS then
		return
	end
	if btn == 1 then
		Util.toggle_from_bar(ctx, "brightness", gx, gw)
	elseif btn == 4 or btn == 5 then
		pending_vol = nil
		set_bright(bright + (btn == 4 and 5 or -5))
		ctx.bar.needs_redraw = true
	end
end

function M.tick(ctx, dt)
	if not M.ready then
		return
	end
	-- coalesce slider drags into one brightnessctl call
	if pending_vol then
		pending_wait = pending_wait - dt
		if pending_wait <= 0 then
			local v = pending_vol
			pending_vol = nil
			set_bright(v)
			if M.panel and M.panel.visible then
				M.panel:draw()
			end
			if ctx.bar then
				ctx.bar.needs_redraw = true
			end
		end
	end
	last = last + dt
	if last >= REFRESH_MS then
		last = 0
		if not pending_vol then
			refresh()
			if M.panel and M.panel.visible then
				M.panel:draw()
			end
		end
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.ctx = nil
end

return M