-- plugins/power.lua — session power menu: lock / logout / sleep / reboot /
-- poweroff with confirm footer (confirm opt can skip it)
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("power")
local XK_ESCAPE = 0xff1b

local ITEMS = { "lock", "logout", "sleep", "reboot", "poweroff" }
local LABELS = {
	lock = "lock",
	logout = "logout",
	sleep = "sleep",
	reboot = "reboot",
	poweroff = "shut down",
}

local function logout_cmd()
	if os.getenv("NIRI_SOCKET") then
		return "niri msg action quit"
	end
	if os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
		return "hyprctl dispatch exit"
	end
	if os.getenv("SWAYSOCK") then
		return "swaymsg exit"
	end
	return nil
end

local function run(ctx, key)
	local c = ctx.config.power or {}
	if key == "lock" then
		os.execute((c.lock_cmd or "swaylock -f") .. " >/dev/null 2>&1 &")
		return
	elseif key == "logout" then
		local cmd = c.logout_cmd or logout_cmd()
		if not cmd then
			ctx.notify(I.t("logout: unsupported session"), { style = "error" })
			return
		end
		os.execute(cmd)
	elseif key == "sleep" then
		os.execute("systemctl suspend")
	elseif key == "reboot" then
		os.execute("systemctl reboot")
	elseif key == "poweroff" then
		os.execute("systemctl poweroff")
	end
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 24 }
	m.W = 440
	m.HEADER_H = lh + 26
	m.BTN_H = lh + 24
	m.GAP = 12
	m.FOOTER_H = lh + 18
	local items = (ctx.config.power and ctx.config.power.items) or ITEMS
	m.items = {}
	for _, key in ipairs(items) do
		if LABELS[key] then
			m.items[#m.items + 1] = key
		end
	end
	local cols = 3
	m.cols = cols
	m.rows = math.ceil(#m.items / cols)
	m.BTN_W = math.floor((m.W - m.PAD * 2 - (cols - 1) * m.GAP) / cols)
	m.H = m.HEADER_H + 16 + m.rows * (m.BTN_H + m.GAP) + m.FOOTER_H + 8
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	m.W, m.H = p.w, p.h
	m.BTN_W = math.floor((m.W - m.PAD * 2 - (m.cols - 1) * m.GAP) / m.cols)
	local lh, PAD, W = m.lh, m.PAD, m.W

	p:draw_header(I.t("power"), Util.keybind_hint(ctx, "toggle_power"), PAD)

	local y = m.HEADER_H + 16
	for i, key in ipairs(m.items) do
		local col = (i - 1) % m.cols
		local row = math.floor((i - 1) / m.cols)
		local bx = PAD + col * (m.BTN_W + m.GAP)
		local by = y + row * (m.BTN_H + m.GAP)
		local is_crit = (key == "poweroff" or key == "reboot")
		if ui:id_button("pw_" .. key, bx, by, m.BTN_W, m.BTN_H, I.t(LABELS[key]),
			{ tonal = true, color = is_crit and T.crit or nil }) then
			local c = ctx.config.power or {}
			if key == "lock" or c.confirm == false then
				run(ctx, key)
			else
				M.pending = key
			end
		end
	end

	local fy = m.H - m.FOOTER_H
	p:rect(PAD - 8, fy - 6, W - (PAD - 8) * 2, 1, T.outline)
	if M.pending then
		local q = I.t("confirm: %s?", I.t(LABELS[M.pending]))
		p:text(PAD, fy + 4, q, T.crit)
		local bw = 76
		local bh = lh + 8
		local byy = fy + 2
		if ui:id_button("pw_cancel", W - PAD - bw * 2 - 10, byy, bw, bh, I.t("cancel"), { tonal = true }) then
			M.pending = nil
		end
		if ui:id_button("pw_confirm", W - PAD - bw, byy, bw, bh, I.t("confirm"), { filled = true, color = T.crit }) then
			local key = M.pending
			M.pending = nil
			run(ctx, key)
		end
	else
		p:text(PAD, fy + 4, I.t("lock runs at once · others ask first"), T.hint)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.pending = nil
	local panel = Panel.new(ctx, {
		name = "power",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(320, us.w)
				m.BTN_W = math.floor((m.W - m.PAD * 2 - (m.cols - 1) * m.GAP) / m.cols)
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
				if M.pending then
					M.pending = nil
				else
					p:hide()
				end
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
		on_show = function()
			M.pending = nil
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("power", panel)
	log("ready")
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("power"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "power" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("power"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "power", gx, gw)
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.ctx = nil
end

return M
