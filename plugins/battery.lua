-- plugins/battery.lua — battery bar item + merged session panel
-- (power menu folded in, MIUIX-style card rows: lock / logout / sleep /
-- reboot / poweroff). Panel opts: config.battery (falls back to
-- config.power): lock_cmd, logout_cmd, confirm, items
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")
local Hypr = require("core.wm.hyprland")

local log = Util.logger("battery")
local XK_ESCAPE = 0xff1b

local ITEMS = { "lock", "logout", "sleep", "reboot", "poweroff" }
local LABELS = {
	lock = "lock",
	logout = "logout",
	sleep = "sleep",
	reboot = "reboot",
	poweroff = "shut down",
}

-- toast shown when a session action is accepted (keys into core/i18n.lua)
local RUN_MSG = {
	lock = "locking…",
	logout = "logging out…",
	sleep = "suspending…",
	reboot = "rebooting…",
	poweroff = "powering off…",
}

local present = false
local bats = {}
local cap = 0
local charging = false
local last = 0
local REFRESH_MS = 2000

local function rd(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

local function probe_bats()
	local found = {}
	for i = 0, 5 do
		local name = string.format("BAT%d", i)
		if rd("/sys/class/power_supply/" .. name .. "/capacity") then
			found[#found + 1] = name
		end
	end
	for _, name in ipairs({ "BATT", "BATTERY", "BAT" }) do
		if rd("/sys/class/power_supply/" .. name .. "/capacity") then
			found[#found + 1] = name
		end
	end
	bats = found
	present = #found > 0
	if present then
		log("batteries: %s", table.concat(found, ","))
	end
end

local function refresh()
	if #bats == 0 then
		probe_bats()
		if not present then
			return
		end
	end
	local sum, n = 0, 0
	charging = false
	for _, name in ipairs(bats) do
		local c = rd("/sys/class/power_supply/" .. name .. "/capacity")
		if c then
			sum = sum + (tonumber(c) or 0)
			n = n + 1
		end
		local st = rd("/sys/class/power_supply/" .. name .. "/status") or ""
		if st == "Charging" or st == "Full" then
			charging = true
		end
	end
	if n > 0 then
		cap = math.floor(sum / n + 0.5)
		present = true
	else
		present = false
	end
end

local function opts(ctx)
	return ctx.config.battery or ctx.config.power or {}
end

local function logout_cmd()
	if os.getenv("NIRI_SOCKET") then
		return "niri msg action quit"
	end
	if os.getenv("HYPRLAND_INSTANCE_SIGNATURE") then
		-- lua config provider first (hyprctl dispatch breaks on it), classic second
		return Hypr.dispatch_cmd("hl.dispatch(hl.dsp.exit())", "exit")
	end
	if os.getenv("SWAYSOCK") then
		return "swaymsg exit"
	end
	return nil
end

-- run one session action; os.execute returns the raw exit code (0 = success)
-- and the outcome is toasted; never called from inside draw (deferred)
local function run(ctx, key)
	local c = opts(ctx)
	local rc
	if key == "lock" then
		log("lock using swaylock, make sure you install it")
		rc = os.execute((c.lock_cmd or "swaylock -f") .. " >/dev/null 2>&1 &")
	elseif key == "logout" then
		local cmd = c.logout_cmd or logout_cmd()
		if not cmd then
			ctx.notify(I.t("logout: unsupported session"), { style = "error" })
			return
		end
		rc = os.execute(cmd)
	elseif key == "sleep" then
		rc = os.execute("systemctl suspend")
	elseif key == "reboot" then
		rc = os.execute("systemctl reboot")
	elseif key == "poweroff" then
		rc = os.execute("systemctl poweroff")
	end
	if rc == 0 then
		ctx.notify(I.t(RUN_MSG[key]), { style = "info" })
	else
		ctx.notify(I.t("%s failed", I.t(LABELS[key])), { style = "error" })
	end
end

-- MIUIX-style geometry (mirrors plugins/settings.lua)
local PAD, ROW_GAP = 20, 8
local CARD_R = 14 -- row card corner radius
local GROUP_GAP = 28 -- gap between a card and the next group title

local function row_h(lh)
	return math.max(46, lh + 28)
end

local function group_h(lh)
	return lh + 8
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = PAD, ROW_H = row_h(lh), GROUP_H = group_h(lh) }
	m.W = 460
	m.HEADER_H = lh + 26
	m.STATUS_H = lh + 40
	m.FOOTER_H = lh + 24
	local items = opts(ctx).items or ITEMS
	m.items = {}
	for _, key in ipairs(items) do
		if LABELS[key] then
			m.items[#m.items + 1] = key
		end
	end
	-- natural height from the row count, capped at 85% of the screen
	local y = m.HEADER_H + 14
	m.status_y = y
	y = y + m.STATUS_H + ROW_GAP
	y = y + GROUP_GAP - ROW_GAP -- widen before the group title
	m.group_y = y
	y = y + m.GROUP_H + ROW_GAP
	m.item_y = {}
	for i = 1, #m.items do
		m.item_y[i] = y
		y = y + m.ROW_H + ROW_GAP
	end
	m.H = math.max(m.HEADER_H + m.FOOTER_H + 40,
		math.min(ctx.scr_h * 0.85, y - ROW_GAP + 6 + m.FOOTER_H))
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

	-- content layer painted FIRST; the footer band and the header below
	-- cover it opaquely, which clips the rows without needing a scissor

	-- status card: label + colored percentage, progress pill underneath
	local icon = charging and I.t("CHG") or I.t("BAT")
	local col = charging and T.primary
		or cap <= 10 and T.crit
		or cap <= 30 and T.warn
		or T.primary
	local str = string.format("%s %d%%", icon, cap)
	p:rrect(PAD, m.status_y, card_w, m.STATUS_H, CARD_R, T.surface)
	p:text(PAD + 16, m.status_y + 12, I.t("battery"), T.on_var)
	local vw = select(1, ctx.get_text_size(str))
	p:text(W - PAD - 16 - vw, m.status_y + 12, str, col)
	local pill_h = 8
	local py = m.status_y + 12 + lh + 9
	local pill_w = card_w - 32
	p:rrect(PAD + 16, py, pill_w, pill_h, pill_h / 2, T.surface_hover)
	local fw = math.max(pill_h, math.floor(pill_w * math.min(100, cap) / 100))
	if cap > 0 then
		p:rrect(PAD + 16, py, fw, pill_h, pill_h / 2, col)
	end

	-- group title (small hint-coloured text)
	p:text(PAD + 6, m.group_y + 6, I.t("power"), T.hint)

	-- session action card rows: label left, chevron right
	local chw = select(1, ctx.get_text_size("›"))
	for i, key in ipairs(m.items) do
		local y = m.item_y[i]
		local hovered = ui:hover(PAD, y, card_w, m.ROW_H)
		p:rrect(PAD, y, card_w, m.ROW_H, CARD_R, hovered and T.surface_hover or T.surface)
		local ty = y + math.floor((m.ROW_H - lh) / 2)
		local is_crit = key == "poweroff" or key == "reboot"
		p:text(PAD + 16, ty, I.t(LABELS[key]), is_crit and T.crit or T.on_var)
		p:text(W - PAD - 16 - chw, ty, "›", T.outline_var)
		if ui:clicked(PAD, y, card_w, m.ROW_H) then
			local c = opts(ctx)
			if key == "lock" or c.confirm == false then
				-- deferred: never run session commands from inside draw
				M.pending_action = function()
					run(ctx, key)
				end
			else
				M.pending = key
			end
		end
	end

	-- footer: opaque band over the content, hairline separator, pill buttons
	local fy = m.H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	if M.pending then
		local q = I.t("confirm: %s?", I.t(LABELS[M.pending]))
		p:text(PAD, mid_y, q, T.crit)
		local bw = 76
		local bh = lh + 14
		local byy = fy + math.floor((m.FOOTER_H - bh) / 2)
		if ui:id_button("bat_cancel", W - PAD - bw * 2 - 10, byy, bw, bh, I.t("cancel"),
			{ tonal = true, bg = T.surface_hi }) then
			M.pending = nil
		end
		if ui:id_button("bat_confirm", W - PAD - bw, byy, bw, bh, I.t("confirm"),
			{ filled = true, color = T.crit }) then
			local key = M.pending
			M.pending = nil
			M.pending_action = function()
				run(ctx, key)
			end
		end
	else
		p:text(PAD, mid_y, I.t("lock runs at once · others ask first"), T.hint)
	end

	-- header painted LAST: its opaque band clips any content painted high
	p:draw_header(I.t("battery"), Util.keybind_hint(ctx, "toggle_battery"), PAD)
end

function M.init(ctx)
	refresh()
	M.pending = nil
	M.pending_action = nil
	local panel = Panel.new(ctx, {
		name = "battery",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(320, us.w)
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
			refresh()
			M.pending = nil
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("battery", panel)
	log("ready")
end

function M.width(ctx)
	if not present then
		return 0
	end
	return 8 + select(1, ctx.get_text_size(I.t("BAT") .. " 100%"))
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
	if not present and #bats == 0 then
		last = last + dt
		if last < 30000 then
			return
		end
		last = 0
		refresh()
		return
	end
	last = last + dt
	if last < REFRESH_MS then
		return
	end
	last = 0
	refresh()
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

function M.draw(ctx, s, x, y, w, h)
	if not present then
		return
	end
	local lh = ctx.get_line_height()
	local col = charging and ctx.theme.accent
		or cap <= 10 and ctx.theme.crit
		or cap <= 30 and ctx.theme.warn
		or ctx.theme.fg
	local icon = charging and I.t("CHG") or cap <= 10 and "!!" or cap <= 30 and I.t("LOW") or I.t("BAT")
	s:text(x + 4, math.floor((h - lh) / 2), string.format("%s %3d%%", icon, cap), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "battery", gx, gw)
	end
end

function M.shutdown()
	M.panel = nil
	M.pending = nil
	M.pending_action = nil
end

return M
