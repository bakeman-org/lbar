local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("weather")

local REFRESH_SEC = 900
local CURL_TIMEOUT = 8
local POLL_MS = 1500
local REDRAW_MS = 5000

local FALLBACK_CITY = "New York"

-- MIUIX-style geometry (mirrors plugins/settings.lua)
local ROW_GAP, GROUP_GAP, CARD_R = 8, 28, 14

local function icon_for(desc)
	if not desc then
		return "·"
	end
	local d = desc:lower()
	if d:find("thunder") or d:find("storm") then
		return "storm"
	end
	if d:find("snow") or d:find("sleet") or d:find("ice") then
		return "snow"
	end
	if d:find("rain") or d:find("drizzle") or d:find("shower") then
		return "rain"
	end
	if d:find("fog") or d:find("mist") or d:find("haze") then
		return "fog"
	end
	if d:find("cloud") or d:find("overcast") then
		return "cloud"
	end
	if d:find("sun") or d:find("clear") then
		return "clear"
	end
	return "cloud"
end

local function extract_scalar(text, name)
	local v = text:match('"' .. name .. '"%s*:%s*"([^"]*)"')
	if v then
		return v
	end
	return text:match('"' .. name .. '"%s*:%s*([%-%d%.]+)')
end

local function extract_array_value(text, name)
	return text:match('"' .. name .. '"%s*:%s*%[%s*{%s*"value"%s*:%s*"([^"]*)"')
end

local function parse_weather(text)
	if not text or #text < 20 then
		return nil
	end
	if not text:find('"current_condition"', 1, true) then
		return nil
	end

	local w = {
		temp = tonumber(extract_scalar(text, "temp_C")) or 0,
		feels = tonumber(extract_scalar(text, "FeelsLikeC")) or 0,
		humidity = tonumber(extract_scalar(text, "humidity")) or 0,
		wind_kmph = tonumber(extract_scalar(text, "windspeedKmph")) or 0,
		wind_dir = extract_scalar(text, "winddir16Point"),
		desc = extract_array_value(text, "weatherDesc"),
		city = extract_array_value(text, "areaName"),
		region = extract_array_value(text, "region"),
		country = extract_array_value(text, "country"),
	}
	if not w.wind_dir then
		w.wind_dir = extract_array_value(text, "winddir16Point")
	end
	return w
end

local function state_path()
	return "/tmp/lbar-weather-auto.json"
end
local function city_path()
	return "/tmp/lbar-weather-city.txt"
end
local function script_path()
	return "/tmp/lbar-weather-fetch.sh"
end

local function file_mtime(p)
	return Util.file_mtime(p) or 0
end

local function read_file(p)
	local f = io.open(p, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function fetch_async(manual_city)
	local out = state_path()
	local cty = city_path()
	local scr = script_path()
	os.remove(out)

	local pre = ""
	if manual_city and manual_city ~= "" then
		pre = string.format("CITY=%s\n", "'" .. manual_city:gsub("'", "'\\''") .. "'")
	else
		pre = string.format(
			[[CITY=$(curl -sS --max-time 5 'http://ip-api.com/json/?fields=city' 2>/dev/null \
  | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
[ -z "$CITY" ] && CITY=%s
]],
			"'" .. FALLBACK_CITY .. "'"
		)
	end

	local body = pre
		.. string.format(
			[[CITY_URL=$(printf '%%s' "$CITY" | sed 's/ /+/g')
printf '%%s' "$CITY" > %s
curl -sS --max-time %d -A 'lbar-weather/1.0' \
  "https://wttr.in/$CITY_URL?format=j1" -o %s 2>/dev/null
]],
			"'" .. cty .. "'",
			CURL_TIMEOUT,
			"'" .. out .. "'"
		)

	local f = io.open(scr, "w")
	if not f then
		return
	end
	f:write("#!/bin/sh\n")
	f:write(body)
	f:close()
	os.execute("sh " .. scr .. " >/dev/null 2>&1 &")
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		PAD = 20,
		ROW_GAP = ROW_GAP,
		W = 360,
		HEADER_H = lh + 26,
		HERO_H = lh * 2 + 28,
		ROW_H = math.max(46, lh + 28),
		GROUP_H = lh + 8,
		FOOTER_H = lh + 22,
	}
	-- natural height from the fixed row count, capped at 85% of the screen
	local y = m.HEADER_H + 14
	m.hero_y = y
	y = y + m.HERO_H + m.ROW_GAP
	y = y + GROUP_GAP - m.ROW_GAP -- widen before the group title
	m.group_y = y
	y = y + m.GROUP_H + m.ROW_GAP
	m.row_y = {}
	for i = 1, 3 do
		m.row_y[i] = y
		y = y + m.ROW_H + m.ROW_GAP
	end
	m.H = math.max(m.HEADER_H + m.FOOTER_H + 40,
		math.min(ctx.scr_h * 0.85, y - m.ROW_GAP + 6 + m.FOOTER_H))
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function fmt_ago(t)
	if not t or t < 0 then
		return I.t("waiting data")
	end
	local s = os.time() - t
	if s < 60 then
		return I.t("just updated")
	end
	local m = math.floor(s / 60)
	if m < 60 then
		return I.t("updated %d min ago", m)
	end
	return I.t("updated %d h ago", math.floor(m / 60))
end

local function fmt_location(w)
	if not w or not w.city then
		return I.t("unknown location")
	end
	if w.region and w.region ~= "" and w.region ~= w.city then
		return w.city .. " · " .. w.region
	end
	return w.city
end

local function fmt_wind(w)
	if not w or not w.wind_kmph or w.wind_kmph == 0 then
		return "--"
	end
	local dir = w.wind_dir or "--"
	return string.format("%s %d", dir, math.floor(w.wind_kmph))
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	-- self-heal: model follows the live surface size (user resize)
	m.W, m.H = p.w, p.h
	local lh, PAD = m.LH, m.PAD
	local W = m.W
	local card_w = W - PAD * 2

	-- content layer painted FIRST; the footer band and the header below
	-- cover it opaquely, which clips without needing a scissor

	-- hero card: temperature + icon on top, description + location below
	p:rrect(PAD, m.hero_y, card_w, m.HERO_H, CARD_R, T.surface)
	if M.data then
		local wd = M.data
		local temp = (M.units == "f") and string.format("%d°F", math.floor(wd.temp * 9 / 5 + 32))
			or string.format("%d°C", math.floor(wd.temp))
		p:text(PAD + 16, m.hero_y + 14, temp, T.on_surface)
		local icon = I.t(icon_for(wd.desc))
		local iw = select(1, ctx.get_text_size(icon))
		p:text(W - PAD - 16 - iw, m.hero_y + 14, icon, T.primary_hi)
		local y2 = m.hero_y + 14 + lh + 8
		p:text(PAD + 16, y2, wd.desc or "--", T.on_var)
		local loc_str = fmt_location(wd)
		local lw = select(1, ctx.get_text_size(loc_str))
		local dw = select(1, ctx.get_text_size(wd.desc or "--"))
		if lw <= card_w - 32 - dw - 16 then
			p:text(W - PAD - 16 - lw, y2, loc_str, T.hint)
		end
	else
		p:text(PAD + 16, m.hero_y + 14, M.error or I.t("fetching…"), T.hint)
		local hint = M.manual_city and I.t("manual city: %s", M.manual_city)
			or I.t("auto-locate, first fetch ~1-2s")
		p:text(PAD + 16, m.hero_y + 14 + lh + 8, hint, T.hint)
	end

	-- group title (small hint-coloured text) + detail card rows
	p:text(PAD + 6, m.group_y + 6, I.t("details"), T.hint)
	local wd = M.data
	local cells = {
		{ I.t("feels"), wd and string.format("%d°", math.floor(wd.feels)) or "--" },
		{ I.t("humidity"), wd and string.format("%d%%", math.floor(wd.humidity)) or "--" },
		{ I.t("wind"), fmt_wind(wd) },
	}
	for i, c in ipairs(cells) do
		local y = m.row_y[i]
		p:rrect(PAD, y, card_w, m.ROW_H, CARD_R, T.surface)
		local ty = y + math.floor((m.ROW_H - lh) / 2)
		p:text(PAD + 16, ty, c[1], T.on_var)
		local vw = select(1, ctx.get_text_size(c[2]))
		p:text(W - PAD - 16 - vw, ty, c[2], T.hint)
	end

	-- footer: opaque band + hairline separator (status left, source right)
	local fy = m.H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	local status = M.data and fmt_ago(M.last_update_t) or M.error or I.t("waiting data")
	p:text(PAD, mid_y, status, T.hint)
	local src = "wttr.in"
	local sw = select(1, ctx.get_text_size(src))
	p:text(W - PAD - sw, mid_y, src, T.hint)

	-- header painted LAST: its opaque band clips the content above it
	p:draw_header(I.t("Weather"), Util.keybind_hint(ctx, "toggle_weather"), PAD)
end

function M.bar_label()
	if not M.data then
		return I.t("wttr…")
	end
	if M.units == "f" then
		return string.format("%d°F", math.floor(M.data.temp * 9 / 5 + 32))
	end
	return string.format("%d°C", math.floor(M.data.temp))
end

function M.width(ctx)
	return select(1, ctx.get_text_size(M.bar_label())) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local T = ctx.theme
	local active = ctx.active_plugin_name == "weather" and ctx.popup_visible
	local col = active and T.primary or (M.data and T.on_surface or T.on_var)
	s:text(x + 10, math.floor((h - lh) / 2), M.bar_label(), col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "weather", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true

	local wcfg = ctx.config.weather or {}
	M.units = wcfg.units or "c"
	M.refresh_sec = wcfg.refresh_sec or REFRESH_SEC
	M.manual_city = wcfg.manual_city

	M.data = nil
	M.error = nil
	M.last_mtime = 0
	M.last_fetch_t = -1e9
	M.last_update_t = -1e9
	M.pending_notify = false
	M.need_redraw = true
	M.poll_accum = 0
	M.redraw_accum = REDRAW_MS

	local panel = Panel.new(ctx, {
		name = "weather",
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
		on_show = function()
			M:refresh(true, true)
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("weather", panel)

	M:refresh(true, false)
	log("ready (manual=%s)", tostring(M.manual_city) or "auto")
end

function M:refresh(force, notify)
	local now = os.time()
	if not force and (now - self.last_fetch_t) < self.refresh_sec then
		return
	end
	self.last_fetch_t = now
	if notify then
		self.pending_notify = true
	end
	fetch_async(self.manual_city)
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	local p = M.panel
	M.poll_accum = M.poll_accum + dt
	M.redraw_accum = M.redraw_accum + dt

	if M.poll_accum >= POLL_MS then
		M.poll_accum = 0
		local sp = state_path()
		local mt = file_mtime(sp)
		if mt > 0 and mt ~= M.last_mtime then
			local txt = read_file(sp)
			local w = parse_weather(txt)
			if w then
				M.data = w
				M.last_mtime = mt
				M.error = nil
				M.last_update_t = os.time()
				M.need_redraw = true
				ctx.bar.needs_redraw = true

				if M.pending_notify then
					M.pending_notify = false
					local where = w.city or "?"
					local t_str = (M.units == "f") and string.format("%.0f°F", w.temp * 9 / 5 + 32)
						or string.format("%.0f°C", w.temp)
					M.ctx.notify(string.format("%s  %s  %s", where, t_str, w.desc or ""), {
						style = "success",
						duration = 2500,
					})
				end
			else
				M.error = I.t("parse failed")
				M.need_redraw = true

				if M.pending_notify then
					M.pending_notify = false
					M.ctx.notify(I.t("weather fetch failed"), { style = "error", duration = 3000 })
				end
			end
		end
	end

	M:refresh(false, false)

	if p.visible and (M.need_redraw or M.redraw_accum >= REDRAW_MS) then
		p:draw()
		M.need_redraw = false
		M.redraw_accum = 0
	end
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
