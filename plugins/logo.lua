-- plugins/logo.lua — tux bar item; click opens the app info popup with a
-- theme switch (persists via actions.toggle_theme), reload and quit
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("logo")

local TUX = {
	"...bbbbb...",
	"..bbbbbbb..",
	"..bwbbwbb..",
	"..bwbbwbb..",
	".bbwwwwwbb.",
	".bbwwoowbb.",
	".bbwwwwwbb.",
	".bwwwwwwwb.",
	"bwwwwwwwwwb",
	"bwwwwwwwwwb",
	".bwwwwwwb..",
	"..oo...oo..",
}

local COL_B = 0x1a1a1a
local COL_W = 0xf5f5f5
local COL_O = 0xf2a33c

local TUX_COLS = 11
local TUX_ROWS = 12

local function draw_tux(s, x, y, px)
	for ry = 1, TUX_ROWS do
		local row = TUX[ry]
		for rx = 1, TUX_COLS do
			local ch = row:sub(rx, rx)
			local c
			if ch == "b" then
				c = COL_B
			elseif ch == "w" then
				c = COL_W
			elseif ch == "o" then
				c = COL_O
			end
			if c then
				s:rect(x + (rx - 1) * px, y + (ry - 1) * px, px, px, c)
			end
		end
	end
end

local function tux_px(h)
	return math.max(2, math.min(4, math.floor((h - 14) / TUX_ROWS)))
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 24 }
	m.W = 460
	m.HEADER_H = lh + 26
	m.ROW_H = lh + 12
	m.INFO_H = 6 * m.ROW_H
	m.BTN_Y = m.HEADER_H + 20 + m.INFO_H + 20
	m.BTN_H = lh + 20
	m.H = m.BTN_Y + m.BTN_H + 22
	return m
end

local function fmt_uptime(sec)
	if sec < 60 then
		return string.format("%ds", sec)
	end
	if sec < 3600 then
		return string.format("%dm %02ds", math.floor(sec / 60), sec % 60)
	end
	return string.format("%dh %02dm", math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	m.W, m.H = p.w, p.h
	local lh, PAD, W = m.lh, m.PAD, m.W

	p:draw_header(I.t("lbar"), nil, PAD)

	local rows = {
		{ I.t("backend"), tostring(ctx.backend_kind) },
		{ I.t("screen"), string.format("%dx%d", ctx.scr_w, ctx.scr_h) },
		{ I.t("engine"), tostring(jit and jit.version or _VERSION) },
		{ I.t("font"), string.format("%s px", tostring(ctx.config.font_size)) },
		{ I.t("plugins"), tostring(ctx.bar and #ctx.bar.plugins or 0) },
		{ I.t("uptime"), fmt_uptime(os.time() - (M.start or os.time())) },
	}
	local y = m.HEADER_H + 20
	for _, r in ipairs(rows) do
		p:text(PAD, y, r[1], T.hint)
		local vw = ctx.text_width(r[2])
		p:text(W - PAD - vw, y, r[2], T.on_surface)
		y = y + m.ROW_H
	end

	local by = m.BTN_Y
	local bw = math.floor((W - PAD * 2 - 24) / 3)
	if ui:id_button("logo_theme", PAD, by, bw, m.BTN_H, I.t("Theme"), { tonal = true }) then
		-- toggle_theme resyncs panel bg and redraws visible panels itself
		if ctx.actions.toggle_theme then
			ctx.actions.toggle_theme()
		end
	end
	if ui:id_button("logo_reload", PAD + bw + 12, by, bw, m.BTN_H, I.t("Reload"), { tonal = true }) then
		M.pending_action = ctx.actions.hot_reload
	end
	if ui:id_button("logo_quit", PAD + (bw + 12) * 2, by, bw, m.BTN_H, I.t("Quit"), { color = T.crit }) then
		M.pending_action = ctx.actions.quit
	end
end

function M.width(ctx)
	local px = tux_px((ctx.bar and ctx.bar.h) or 40)
	return TUX_COLS * px + 20
end

function M.draw(ctx, s, x, y, w, h)
	local px = tux_px(h)
	local active = ctx.active_plugin_name == "logo" and ctx.popup_visible
	if active then
		s:rrect(x - 6, 4, w + 12, h - 8, (h - 8) / 2, ctx.theme.secondary_ctr)
	end
	draw_tux(s, x + math.floor((w - TUX_COLS * px) / 2),
		math.floor((h - TUX_ROWS * px) / 2), px)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		-- android PopupWindow style: popup left edge pinned to the tux item
		Util.toggle_from_bar(ctx, "logo", gx, gw, "left")
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending_action = nil
	M.start = os.time()

	local panel = Panel.new(ctx, {
		name = "logo",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(m.W, us.w)
				m.H = math.max(m.H, us.h)
			end
			return m
		end,
		size_fn = function(c)
			local m = compute_layout(c, c.get_line_height())
			return m.W, m.H
		end,
		draw = do_draw,
		on_key = function(p, sym)
			if sym == 0xff1b then
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
			p:draw()
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("logo", panel)
	log("ready")
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

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.pending_action = nil
	M.ctx = nil
end

return M
