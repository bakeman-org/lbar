local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("menu")

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

local function draw_tux(p, x, y, px)
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
				p:rect(x + (rx - 1) * px, y + (ry - 1) * px, px, px, c)
			end
		end
	end
end

local function tux_px(h)
	return math.max(2, math.min(4, math.floor((h - 14) / TUX_ROWS)))
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {}
	m.LH = lh
	m.PAD = 24
	m.W = 460
	m.HEAD_H = lh + 26
	m.INFO_Y = m.HEAD_H + 20
	m.ROW_H = lh + 10
	m.INFO_H = 6 * m.ROW_H
	m.BTN_Y = m.INFO_Y + m.INFO_H + 20
	m.BTN_H = lh + 20
	m.H = m.BTN_Y + m.BTN_H + 22
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
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
	local T = ctx.theme
	local ui = p.ui
	local lh, PAD, W = m.LH, m.PAD, m.W

	local px = math.max(2, math.min(4, math.floor((m.HEAD_H - 8) / TUX_ROWS)))
	local hy = math.floor((m.HEAD_H - lh) / 2)
	draw_tux(p, PAD, math.floor((m.HEAD_H - TUX_ROWS * px) / 2), px)
	p:text(PAD + TUX_COLS * px + 16, hy, "lbar", T.primary)
	local ver = "lua " .. tostring(_VERSION):match("[%d%.]+$")
	p:text(PAD + TUX_COLS * px + 16 + select(1, ctx.get_text_size("lbar")) + 14, hy, ver, T.on_var)
	p:header_close(m.HEAD_H)
	p:rect(0, m.HEAD_H - 1, W, 1, T.outline)

	local rows = {
		{ "backend", tostring(ctx.backend_kind) },
		{ "screen", string.format("%dx%d", ctx.scr_w, ctx.scr_h) },
		{ "engine", tostring(jit and jit.version or _VERSION) },
		{ "font", string.format("%s px", tostring(ctx.config.font_size)) },
		{ "plugins", tostring(ctx.bar and #ctx.bar.plugins or 0) },
		{ "uptime", fmt_uptime(os.time() - (M.start or os.time())) },
	}
	local y = m.INFO_Y
	for _, r in ipairs(rows) do
		p:text(PAD, y, r[1], T.hint)
		local vw = select(1, ctx.get_text_size(r[2]))
		p:text(W - PAD - vw, y, r[2], T.on_surface)
		y = y + m.ROW_H
	end

	local by = m.BTN_Y
	local bw = math.floor((W - PAD * 2 - 24) / 3)
	if ui:id_button("menu_theme", PAD, by, bw, m.BTN_H, "Theme", { tonal = true }) then
		if ctx.actions.toggle_theme then
			ctx.actions.toggle_theme()
		end
	end
	if ui:id_button("menu_reload", PAD + bw + 12, by, bw, m.BTN_H, "Reload", { tonal = true }) then
		if ctx.actions.hot_reload then
			ctx.actions.hot_reload()
		end
	end
	if ui:id_button("menu_quit", PAD + (bw + 12) * 2, by, bw, m.BTN_H, "Quit", { color = T.crit }) then
		if ctx.actions.quit then
			ctx.actions.quit()
		end
	end
end

function M.width(ctx)
	local px = tux_px((ctx.bar and ctx.bar.h) or 40)
	return TUX_COLS * px + 20
end

function M.draw(ctx, s, x, y, w, h)
	local px = tux_px(h)
	local active = ctx.active_plugin_name == "menu" and ctx.popup_visible
	if active then
		s:rrect(x - 6, 4, w + 12, h - 8, (h - 8) / 2, ctx.theme.secondary_ctr)
	end
	draw_tux(s, x + math.floor((w - TUX_COLS * px) / 2),
		math.floor((h - TUX_ROWS * px) / 2), px)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "menu", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.start = os.time()

	local panel = Panel.new(ctx, {
		name = "menu",
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
	ctx.register_panel("menu", panel)

	log("ready")
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	if M.panel.visible and M.panel.draw then
		M.panel:draw()
	end
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
