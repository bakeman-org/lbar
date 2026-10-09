-- plugins/resize_window.lua — resize the focused window (i3 / hyprland) or
-- the active lbar panel; includes a MIUIX-style control panel (d-pad + reset)
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")
local Hypr = require("core.wm.hyprland")

local log = Util.logger("resize_window")
local XK_ESCAPE = 0xff1b

local DEFAULT_STEP = 30
local MIN_PANEL_W = 220
local MIN_PANEL_H = 100

-- MIUIX-style geometry (mirrors plugins/settings.lua)
local PAD, ROW_GAP, CARD_R, GROUP_GAP = 20, 8, 14, 28

local function row_h(lh)
	return math.max(46, lh + 28)
end

local function group_h(lh)
	return lh + 8
end

local function has_cmd(cmd)
	local f = io.popen("command -v " .. cmd .. " 2>/dev/null")
	if not f then
		return false
	end
	local r = f:read("*l")
	f:close()
	return r ~= nil and r ~= ""
end

local function pick_active_panel(ctx)
	local ap = ctx.active_panel
	if ap and ap.visible and ap.live_resize then
		return ap
	end
	for _, p in pairs(ctx._panels or {}) do
		if p.visible and p.live_resize then
			return p
		end
	end
	return nil
end

local function try_resize_panel(ctx, dx, dy)
	local p = pick_active_panel(ctx)
	if not p then
		return false
	end
	p._orig_geom = p._orig_geom or { w = p.w, h = p.h, x = p.sx, y = p.sy }
	local nw = math.max(MIN_PANEL_W, p.w + dx)
	local nh = math.max(MIN_PANEL_H, p.h + dy)
	p.user_size = { w = nw, h = nh }
	p:live_resize(nw, nh)
	return true
end

-- external window resize: same dispatch lines as before; os.execute returns
-- the raw exit code (0 = success) which is now surfaced to the caller
local function resize_external(dx, dy)
	if M.wm == "i3" then
		local axis = dx ~= 0 and "width" or "height"
		local op = (dx > 0 or dy > 0) and "grow" or "shrink"
		local amt = math.abs(dx + dy)
		return os.execute(string.format(
			"i3-msg 'resize %s %s %d px' >/dev/null 2>&1 &", op, axis, amt)) == 0
	elseif M.wm == "hyprland" then
		-- lua config provider first, classic parser as fallback
		return os.execute(string.format("(%s) &", Hypr.dispatch_cmd(
			string.format("hl.dispatch(hl.dsp.window.resize({ x = %d, y = %d }))", dx, dy),
			string.format("resizeactive %d %d", dx, dy)))) == 0
	end
	return false
end

-- operation wrapper: panel first (as before), then the external window;
-- adds toast feedback for the success / failure outcome
local function do_resize(ctx, dx, dy)
	local ok
	if try_resize_panel(ctx, dx, dy) then
		ok = true
	else
		ok = resize_external(dx, dy)
	end
	if ok then
		ctx.notify(I.t("window resized"), { style = "info", duration = 900 })
	else
		ctx.notify(I.t("no window to resize"), { style = "error" })
	end
end

-- reset the active panel to its original geometry (panel-only, logic
-- unchanged) with toast feedback
local function reset_active(ctx)
	local p = pick_active_panel(ctx)
	if not p then
		ctx.notify(I.t("no panel to reset"), { style = "error" })
		return
	end
	p.user_size = nil
	if p._orig_geom then
		local g = p._orig_geom
		p:live_resize(g.w, g.h)
		p:move_to(g.x, g.y)
	end
	ctx.notify(I.t("panel size reset"), { style = "success" })
end

-- deferred: never run os.execute from inside draw
local function defer_resize(ctx, dx, dy)
	M.pending_action = function()
		do_resize(ctx, dx, dy)
	end
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = PAD, ROW_H = row_h(lh), GROUP_H = group_h(lh) }
	m.W = 340
	m.HEADER_H = lh + 26
	m.FOOTER_H = lh + 24
	m.BTN_H = math.max(46, lh + 24)
	-- natural height from the row count, capped at 85% of the screen
	local y = m.HEADER_H + 14
	m.group1_y = y
	y = y + m.GROUP_H + ROW_GAP
	m.pad1_y = y
	y = y + m.BTN_H + ROW_GAP
	m.pad2_y = y
	y = y + m.BTN_H + ROW_GAP
	y = y + GROUP_GAP - ROW_GAP -- widen before the next group title
	m.group2_y = y
	y = y + m.GROUP_H + ROW_GAP
	m.step_y = y
	y = y + m.ROW_H
	m.H = math.max(m.HEADER_H + m.FOOTER_H + 40,
		math.min(ctx.scr_h * 0.85, y + 6 + m.FOOTER_H))
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	-- self-heal on resize: the model follows the live surface size
	m.W, m.H = p.w, p.h
	local lh, PAD, W = m.lh, m.PAD, m.W
	local card_w = W - PAD * 2
	local btn_w = math.floor((card_w - 2 * ROW_GAP) / 3)
	local tonal = { tonal = true, bg = T.surface_hi }

	-- content layer painted FIRST; the footer band and the header below
	-- cover it opaquely, which clips without needing a scissor

	-- group title: small hint-coloured text
	p:text(PAD + 6, m.group1_y + 6, I.t("direction"), T.hint)

	-- d-pad: tonal pill buttons (← narrower · → wider · ↑ taller · ↓ shorter),
	-- deferred to M.tick on press
	if ui:id_button("rz_narrow", PAD, m.pad1_y, btn_w, m.BTN_H, "←", tonal) then
		defer_resize(ctx, -M.step, 0)
	end
	if ui:id_button("rz_tall", PAD + btn_w + ROW_GAP, m.pad1_y, btn_w, m.BTN_H, "↑", tonal) then
		defer_resize(ctx, 0, M.step)
	end
	if ui:id_button("rz_wide", PAD + (btn_w + ROW_GAP) * 2, m.pad1_y, btn_w, m.BTN_H, "→", tonal) then
		defer_resize(ctx, M.step, 0)
	end
	if ui:id_button("rz_short", PAD + btn_w + ROW_GAP, m.pad2_y, btn_w, m.BTN_H, "↓", tonal) then
		defer_resize(ctx, 0, -M.step)
	end

	p:text(PAD + 6, m.group2_y + 6, I.t("options"), T.hint)

	-- step info row: label left, value right-aligned
	p:rrect(PAD, m.step_y, card_w, m.ROW_H, CARD_R, T.surface)
	local ty = m.step_y + math.floor((m.ROW_H - lh) / 2)
	p:text(PAD + 16, ty, I.t("resize step px"), T.on_var)
	local vs = string.format("%d px", M.step)
	local vw = select(1, ctx.get_text_size(vs))
	p:text(W - PAD - 16 - vw, ty, vs, T.hint)

	-- footer: opaque band + hairline separator + hint text + reset pill
	local fy = m.H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	p:text(PAD, mid_y, I.t("resize: %d px per press", M.step), T.hint)
	local bw = 76
	local bh = lh + 14
	local byy = fy + math.floor((m.FOOTER_H - bh) / 2)
	if ui:id_button("rz_reset", W - PAD - bw, byy, bw, bh, I.t("reset"), { filled = true }) then
		M.pending_action = function()
			reset_active(ctx)
		end
	end

	-- header painted LAST: its opaque band clips the content above it
	p:draw_header(I.t("resize window"), Util.keybind_hint(ctx, "toggle_resize_window"), PAD)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending_action = nil

	local cfg = ctx.config.resize_window or {}
	M.step = math.max(4, tonumber(cfg.step) or DEFAULT_STEP)

	if has_cmd("i3-msg") then
		M.wm = "i3"
	elseif has_cmd("hyprctl") then
		M.wm = "hyprland"
	else
		M.wm = nil
		log("no i3-msg or hyprctl - external window resize unavailable")
	end

	ctx.actions["resize_win_wider"] = function()
		do_resize(ctx, M.step, 0)
	end
	ctx.actions["resize_win_narrower"] = function()
		do_resize(ctx, -M.step, 0)
	end
	ctx.actions["resize_win_taller"] = function()
		do_resize(ctx, 0, M.step)
	end
	ctx.actions["resize_win_shorter"] = function()
		do_resize(ctx, 0, -M.step)
	end

	ctx.actions["reset_active_window"] = function()
		-- deferred: resizing a panel mid-tick is safe, but keep one path
		M.pending_action = function()
			reset_active(ctx)
		end
	end

	local panel = Panel.new(ctx, {
		name = "resize_window",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(300, us.w)
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
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("resize_window", panel)

	log("ready: step=%d wm=%s", M.step, tostring(M.wm))
end

function M.tick(ctx, dt)
	if M.pending_action then
		local fn = M.pending_action
		M.pending_action = nil
		local ok, err = pcall(fn)
		if not ok then
			log("pending action error: %s", tostring(err))
		end
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("Resize"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "resize_window" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("Resize"),
		active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "resize_window", gx, gw)
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.pending_action = nil
	M.ctx = nil
end

return M
