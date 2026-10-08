-- plugins/volume.lua — audio volume bar item + panel (pactl / PulseAudio & PipeWire)
-- wheel on the bar item adjusts volume; click opens a slider panel
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("volume")
local XK_ESCAPE = 0xff1b

-- os.execute returns the raw exit status (0 = success) or true depending on
-- the LuaJIT build; accept both so HAVE_PACTL is correct everywhere
local HAVE_PACTL = (function()
	local r = os.execute("command -v pactl >/dev/null 2>&1")
	return r == true or r == 0
end)()
local vol, mute = 0, false
local have_state = false
local last = 0
local pending_vol, pending_wait = nil, 0
local REFRESH_MS = 15000

local function pactl_out(args)
	local p = io.popen("pactl " .. args .. " 2>/dev/null")
	if not p then
		return ""
	end
	local out = p:read("*a")
	p:close()
	return out or ""
end

local function refresh()
	if not HAVE_PACTL then
		return
	end
	local out = pactl_out("get-sink-volume @DEFAULT_SINK@")
	local v = tonumber(out:match("(%d+)%%"))
	if v then
		vol = v
		have_state = true
	end
	local m = pactl_out("get-sink-mute @DEFAULT_SINK@")
	if m:match("Mute:%s*(%w+)") then
		mute = m:match("Mute:%s*(%w+)") == "yes"
	end
end

local function set_vol(v)
	v = math.max(0, math.min(100, math.floor(v + 0.5)))
	vol = v
	have_state = true
	os.execute(string.format("pactl set-sink-volume @DEFAULT_SINK@ %d%% >/dev/null 2>&1", v))
end

local function toggle_mute(ctx)
	os.execute("pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1")
	refresh()
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

local function str()
	if not have_state then
		return I.t("VOL -")
	end
	return mute and I.t("MUTE") or I.t("VOL %d%%", vol)
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 20 }
	m.W = 380
	m.HEADER_H = lh + 26
	m.H = m.HEADER_H + (lh + 30) * 2 + 60 + 20
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	m.W, m.H = p.w, p.h
	local lh, PAD, W = m.lh, m.PAD, m.W

	p:draw_header(I.t("volume"), Util.keybind_hint(ctx, "toggle_volume"), PAD)

	local y = m.HEADER_H + 18
	local big = string.format("%d%%", vol)
	local big_w = select(1, ctx.get_text_size(big))
	local big_col = mute and T.crit or T.primary
	p:text(math.floor((W - big_w) / 2), y, big, big_col)
	y = y + lh + 14

	local sw = W - PAD * 2
	local v, changed = ui:slider("vol_slider", PAD, y, sw, vol, { min = 0, max = 100 })
	if changed then
		pending_vol = v
		pending_wait = 150
	end
	y = y + 34

	if ui:id_button("vol_dn", PAD, y, 54, lh + 12, "-", { tonal = true }) then
		pending_vol = nil
		set_vol(vol - 5)
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
	end
	if ui:id_button("vol_up", PAD + 64, y, 54, lh + 12, "+", { tonal = true }) then
		pending_vol = nil
		set_vol(vol + 5)
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
	end
	local _, mchanged = ui:toggle("vol_mute", W - PAD - 100, y + 4, 44, 22, not mute)
	if mchanged then
		toggle_mute(ctx)
	end
	local mstr = mute and I.t("muted") or I.t("mute")
	p:text(W - PAD - select(1, ctx.get_text_size(mstr)), y + 2, mstr, T.on_var)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	if not HAVE_PACTL then
		log("pactl not found — plugin disabled")
		return
	end
	refresh()
	local panel = Panel.new(ctx, {
		name = "volume",
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
	ctx.register_panel("volume", panel)
	log("ready: %d%%%s", vol, mute and " muted" or "")
end

function M.width(ctx)
	if not HAVE_PACTL or not have_state then
		return 0
	end
	return select(1, ctx.get_text_size(str())) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "volume" and ctx.popup_visible
	local col = mute and ctx.theme.crit or (active and ctx.theme.primary or ctx.theme.on_surface)
	s:text(x + 10, math.floor((h - lh) / 2), str(), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if not HAVE_PACTL then
		return
	end
	if btn == 1 then
		Util.toggle_from_bar(ctx, "volume", gx, gw)
	elseif btn == 4 or btn == 5 then
		pending_vol = nil
		set_vol(vol + (btn == 4 and 5 or -5))
		ctx.bar.needs_redraw = true
	end
end

function M.tick(ctx, dt)
	if not M.ready then
		return
	end
	-- coalesce slider drags into one pactl call
	if pending_vol then
		pending_wait = pending_wait - dt
		if pending_wait <= 0 then
			local v = pending_vol
			pending_vol = nil
			set_vol(v)
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
