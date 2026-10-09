-- plugins/wifi.lua — network panel via nmcli: status, networks, connect
-- (password input), disconnect, wifi radio on/off
-- All nmcli calls run as background jobs (results polled in tick) so panel
-- opens are instant and the UI never blocks
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("wifi")
local XK_ESCAPE = 0xff1b

local opts = {}

local function shq(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function load_opts(ctx)
	local c = ctx.config.wifi or {}
	opts = {
		iface = c.interface or "auto",
		refresh_sec = tonumber(c.refresh_sec) or 8,
	}
end

-- nmcli -g escapes ':' inside values as '\:'
local function split_esc(line)
	local fields = {}
	local cur = {}
	local i = 1
	while i <= #line do
		local c = line:sub(i, i)
		if c == "\\" and i < #line then
			cur[#cur + 1] = line:sub(i + 1, i + 1)
			i = i + 2
		elseif c == ":" then
			fields[#fields + 1] = table.concat(cur)
			cur = {}
			i = i + 1
		else
			cur[#cur + 1] = c
			i = i + 1
		end
	end
	fields[#fields + 1] = table.concat(cur)
	return fields
end

local function update_str()
	local str
	if not M.radio then
		str = I.t("wifi ×")
	elseif M.ssid then
		local nm = M.ssid
		if #nm > 16 then
			nm = nm:sub(1, 15) .. "…"
		end
		str = string.format("%s %d%%", nm, M.signal or 0)
	else
		str = I.t("wifi -")
	end
	M._str = str
end

local function clamp_scroll()
	local m = M.panel and M.panel.m
	local rows = m and m.VROWS or 8
	local maxs = math.max(0, #M.nets - rows)
	if M.scroll > maxs then
		M.scroll = maxs
	end
	if M.scroll < 0 then
		M.scroll = 0
	end
end

-- parse output of the background scan job (marker-delimited sections)
local function apply_scan(content)
	local section = nil
	local radio, iface, ip = nil, nil, nil
	local cur_ssid, cur_sig
	local list, seen = {}, {}
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		if line == "DONE" then
			break
		elseif line == "R" or line == "I" or line == "C" or line == "P" or line == "L" then
			section = line
		elseif section == "R" then
			radio = line:find("enabled", 1, true) ~= nil
		elseif section == "I" then
			iface = line ~= "" and line or nil
		elseif section == "P" then
			ip = line:match("([%d%.]+/%d+)") or ip
		elseif section == "C" then
			local f = split_esc(line)
			if f[1] == "*" then
				cur_ssid = (f[3] ~= "" and f[3] ~= "--") and f[3] or nil
				cur_sig = tonumber(f[2])
			end
		elseif section == "L" then
			local f = split_esc(line)
			local ssid = f[3]
			if ssid ~= "" and ssid ~= "--" then
				local sig = tonumber(f[2]) or 0
				local sec = (f[4] ~= "" and f[4] ~= "--") and f[4] or nil
				local active = f[1] == "*"
				local e = seen[ssid]
				if e then
					if sig > e.signal then
						e.signal, e.sec, e.active = sig, sec, active
					end
				else
					e = { ssid = ssid, signal = sig, sec = sec, active = active }
					seen[ssid] = e
					list[#list + 1] = e
				end
			end
		end
	end
	M.radio = radio == true
	M.iface = M.radio and iface or nil
	M.ssid, M.signal, M.ip = cur_ssid, cur_sig, ip
	table.sort(list, function(a, b)
		if a.active ~= b.active then
			return a.active
		end
		return a.signal > b.signal
	end)
	M.nets = list
	update_str()
	clamp_scroll()
	log("scan: %d networks", #list)
end

-- background job: dump status + network list to a temp file, never block UI
local function async_refresh(ctx, rescan)
	if M.job then
		return
	end
	local tmp = string.format("/tmp/lbar-wifi-scan-%d-%d", os.time(), math.random(10000))
	local ifsel
	if opts.iface ~= "auto" then
		ifsel = "IF=" .. shq(opts.iface)
	else
		ifsel = table.concat({
			"IF=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" && $3 ~ /connected/ {print $1; exit}')",
			"[ -n \"$IF\" ] || IF=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" {print $1; exit}')",
		}, "\n")
	end
	local pre = rescan and "nmcli device wifi rescan >/dev/null 2>&1\nsleep 1.5\n" or ""
	local script = table.concat({
		"(",
		pre,
		ifsel,
		"echo R",
		"nmcli radio wifi",
		"echo I",
		"echo \"$IF\"",
		"if [ -n \"$IF\" ]; then",
		"echo C",
		"nmcli -g IN-USE,SIGNAL,SSID device wifi list ifname \"$IF\"",
		"echo P",
		"nmcli -g IP4.ADDRESS device show \"$IF\"",
		"echo L",
		"nmcli -g IN-USE,SIGNAL,SSID,SECURITY device wifi list ifname \"$IF\"",
		"fi",
		"echo DONE",
		string.format(") > %s 2>&1 &", shq(tmp)),
	}, "\n")
	os.execute(script)
	M.job = { path = tmp, acc = 0, total = 0 }
	M.scanning = true
	if M.panel and M.panel.visible then
		M.panel:draw()
	end
end

-- fast status poll (bar ssid/signal): same cached wifi-list query as the
-- scan's C section, NO rescan — keeps the bar fresh at ~2s while the full
-- network list rescan stays on opts.refresh_sec
local function status_async()
	if M.sjob then
		return
	end
	local tmp = string.format("/tmp/lbar-wifi-st-%d-%d", os.time(), math.random(10000))
	local ifsel
	if opts.iface ~= "auto" then
		ifsel = "IF=" .. shq(opts.iface)
	else
		ifsel = table.concat({
			"IF=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" && $3 ~ /connected/ {print $1; exit}')",
			"[ -n \"$IF\" ] || IF=$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null | awk -F: '$2==\"wifi\" {print $1; exit}')",
		}, "\n")
	end
	local script = table.concat({
		"(",
		ifsel,
		"echo R",
		"nmcli radio wifi",
		"echo I",
		"echo \"$IF\"",
		"if [ -n \"$IF\" ]; then",
		"echo C",
		"nmcli -g IN-USE,SIGNAL,SSID device wifi list ifname \"$IF\"",
		"fi",
		"echo DONE",
		string.format(") > %s 2>&1 &", shq(tmp)),
	}, "\n")
	os.execute(script)
	M.sjob = { path = tmp, acc = 0, total = 0 }
end

-- parse status job output (R/I/C sections only) and refresh the bar string
local function apply_status(ctx, content)
	local radio, iface, cur_ssid, cur_sig
	local section
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		if line == "DONE" then
			break
		elseif line == "R" or line == "I" or line == "C" then
			section = line
		elseif section == "R" then
			radio = line:find("enabled", 1, true) ~= nil
		elseif section == "I" then
			iface = line ~= "" and line or nil
		elseif section == "C" then
			local f = split_esc(line)
			if f[1] == "*" then
				cur_ssid = (f[3] ~= "" and f[3] ~= "--") and f[3] or nil
				cur_sig = tonumber(f[2])
			end
		end
	end
	M.radio = radio == true
	M.iface = M.radio and iface or nil
	M.ssid, M.signal = cur_ssid, cur_sig
	local old = M._str
	update_str()
	if M._str ~= old and ctx.bar then
		ctx.bar.needs_redraw = true	-- redraw only when displayed text changed
	end
end

-- connect runs in the background (nmcli can block 5-20s); result is polled
-- from a temp file in tick so the UI never freezes
local function connect_async(ctx, net, pw)
	local cmd = "nmcli device wifi connect " .. shq(net.ssid)
	if M.iface then
		cmd = cmd .. " ifname " .. M.iface
	end
	if pw and pw ~= "" then
		cmd = cmd .. " password " .. shq(pw)
	end
	local tmp = string.format("/tmp/lbar-wifi-%d-%d", os.time(), math.random(10000))
	os.execute(string.format("(%s >/dev/null 2>&1; echo $? > %s) &", cmd, shq(tmp)))
	M.conn_check = { path = tmp, ssid = net.ssid, wait = 600, total = 0 }
	ctx.notify(I.t("connecting to %s…", net.ssid), { style = "info" })
end

local function toggle_radio(ctx)
	os.execute("nmcli radio wifi " .. (M.radio and "off" or "on") .. " >/dev/null 2>&1 &")
	M.radio = not M.radio
	update_str()
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
	async_refresh(ctx)
end

local function disconnect(ctx)
	if not M.iface then
		return
	end
	os.execute("nmcli device disconnect " .. shq(M.iface) .. " >/dev/null 2>&1")
	async_refresh(ctx)
	ctx.notify(I.t("disconnected"), { style = "info" })
end

-- vertical rhythm: 12px between sections, cards at radius 12, >= 16px
-- bottom margin below the footer row (fixed = everything above the list)
local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 20 }
	m.W = 480
	m.HEADER_H = lh + 26
	m.STATUS_H = lh * 2 + 20
	m.BTN_H = lh + 14
	m.SECT_H = lh + 12
	m.ROW_H = lh + 22
	m.FOOTER_H = lh + 40
	m.BOT_MARGIN = 16
	m.fixed = m.HEADER_H + 12 + m.STATUS_H + 12 + m.BTN_H + 12
		+ m.SECT_H + 12 + m.FOOTER_H + m.BOT_MARGIN
	local want_h = math.min(math.floor(ctx.scr_h * 0.7), 620)
	if want_h < 380 then
		want_h = 380
	end
	m.VROWS = math.max(3, math.floor((want_h - m.fixed) / m.ROW_H))
	m.H = m.fixed + m.VROWS * m.ROW_H
	m.rect_list = { x = 0, y = 0, w = 0, h = 0 }
	return m
end

-- signal strength mini-bar: fill scales with %, color tiers
-- (>=70 primary, >=40 warn, weak crit); dim track behind it
local function sig_pill(p, x, y, w, sig, T)
	sig = sig or 0
	local col = sig >= 70 and T.primary or sig >= 40 and T.warn or T.crit
	p:rrect(x, y, w, 5, 2, T.outline)
	p:rrect(x, y, math.max(3, math.floor(w * sig / 100)), 5, 2, col)
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	-- self-heal: model follows the live surface size (user resize) so list
	-- rows and the footer always match the real panel
	m.W, m.H = p.w, p.h
	-- the password input grows downward when text wraps; the footer card
	-- grows with it below (Panel:fit adds the same growth to the panel)
	local in_extra = p.input and p.input:extra_h() or 0
	m.VROWS = math.max(3, math.floor((m.H - m.fixed - in_extra) / m.ROW_H))
	local lh, PAD, W = m.lh, m.PAD, m.W

	p:draw_header(I.t("wifi"), Util.keybind_hint(ctx, "toggle_wifi"), PAD)

	-- connection card
	local cy = m.HEADER_H + 12
	p:rrect(PAD, cy, W - PAD * 2, m.STATUS_H, 12, T.surface)
	local sx = PAD + 16
	local sy = cy + 10
	if not M.radio then
		p:text(sx, sy, I.t("wifi disabled"), T.crit)
		p:text(sx, sy + lh + 4, I.t("enable wifi below"), T.hint)
	elseif M.ssid then
		p:text(sx, sy, M.ssid, T.on_surface)
		local meta = string.format("%s · %d%%%s", M.iface or "?", M.signal or 0, M.ip and (" · " .. M.ip) or "")
		p:text(sx, sy + lh + 4, meta, T.hint)
	else
		p:text(sx, sy, I.t("not connected"), T.on_var)
		p:text(sx, sy + lh + 4, M.iface and I.t("%s · no network", M.iface) or I.t("no wifi device"), T.hint)
	end
	if M.radio and M.ssid then
		sig_pill(p, W - PAD - 16 - 30, sy + math.floor((lh - 5) / 2), 30, M.signal or 0, T)
	end

	-- action buttons
	local by = cy + m.STATUS_H + 12
	local bw = math.floor((W - PAD * 2 - 20) / 3)
	local on_label = M.radio and I.t("wifi off") or I.t("wifi on")
	if ui:id_button("wf_toggle", PAD, by, bw, m.BTN_H, on_label, { tonal = true }) then
		toggle_radio(ctx)
	end
	if ui:id_button("wf_disc", PAD + bw + 10, by, bw, m.BTN_H, I.t("disconnect"), { tonal = true }) then
		disconnect(ctx)
	end
	if ui:id_button("wf_scan", PAD + (bw + 10) * 2, by, bw, m.BTN_H, I.t("rescan"), { tonal = true }) then
		async_refresh(ctx, true)
	end

	-- list section title
	local ty = by + m.BTN_H + 12
	p:text(PAD + 4, ty, I.t("wifi networks"), T.hint)
	if M.scanning then
		local s = I.t("scanning…")
		local sw = ctx.text_width(s)
		p:text(W - PAD - 4 - sw, ty, s, T.hint)
	end

	-- network list (radius-12 row cards; scrollbar lives outside the list)
	local ly = ty + m.SECT_H
	local list_w = W - PAD * 2 - 14
	m.rect_list.x = PAD
	m.rect_list.y = ly
	m.rect_list.w = list_w
	m.rect_list.h = m.VROWS * m.ROW_H
	clamp_scroll()
	if #M.nets == 0 then
		local msg = M.job and I.t("scanning…")
			or (M.radio and I.t("no networks — try rescan") or I.t("wifi disabled"))
		p:text(PAD + 12, ly + math.floor((m.ROW_H - lh) / 2), msg, T.hint)
	end
	for i = 0, m.VROWS - 1 do
		local idx = M.scroll + i + 1
		if idx > #M.nets then
			break
		end
		local net = M.nets[idx]
		local ry = ly + i * m.ROW_H
		local hovered = ui:hover(PAD, ry, list_w, m.ROW_H)
		local bg = (net.active or hovered) and T.surface_hi or T.surface
		p:rrect(PAD, ry + 3, list_w, m.ROW_H - 6, 12, bg)
		local text_y = ry + math.floor((m.ROW_H - lh) / 2)
		local pct_s = tostring(net.signal) .. "%"
		local pct_w = ctx.text_width(pct_s)
		local pct_x = PAD + list_w - 12 - pct_w
		local pill_x = pct_x - 10 - 28
		local lock_x = pill_x - 12
		local name_max = lock_x - (PAD + 12) - 12
		local name = net.ssid
		if ctx.text_width(name) > name_max then
			while #name > 4 and ctx.text_width(name .. "…") > name_max do
				name = name:sub(1, -2)
			end
			name = name .. "…"
		end
		p:text(PAD + 12, text_y, name, net.active and T.on_surface or T.on_var)
		if net.sec then
			p:text(lock_x, text_y, "*", T.hint)
		end
		sig_pill(p, pill_x, text_y + math.floor((lh - 5) / 2), 28, net.signal, T)
		p:text(pct_x, text_y, pct_s, T.hint)
	end
	if #M.nets > m.VROWS then
		local maxs = #M.nets - m.VROWS
		local off = ui:scrollbar("wf_sb", PAD + list_w + 4, ly, 6, m.rect_list.h, M.scroll, maxs)
		M.scroll = off
	end

	-- footer: password row inside a radius-12 card, >= 16px bottom margin
	local fy = m.H - m.BOT_MARGIN - m.FOOTER_H - in_extra
	if M.pending then
		p:rrect(PAD, fy, W - PAD * 2, m.FOOTER_H + in_extra, 12, T.surface)
		local inner_x = PAD + 12
		local btn_w = 56
		local iw = (W - PAD * 2 - 24) - btn_w * 2 - 16
		local row_h = lh + 24
		local row_y = fy + math.floor((m.FOOTER_H - row_h) / 2)
		p.input:set_rect(inner_x, row_y, iw, row_h)
		p.input:draw(p)
		if ui:id_button("wf_cancel", inner_x + iw + 8, row_y, btn_w, row_h, "esc", { tonal = true }) then
			M.pending = nil
			p.input:blur()
			p.input:set_value("")
		end
		if ui:id_button("wf_conn", inner_x + iw + 8 + btn_w + 8, row_y, btn_w, row_h, I.t("ok"), { filled = true }) then
			connect_async(ctx, M.pending, p.input.value)
			M.pending = nil
			p.input:blur()
			p.input:set_value("")
		end
	else
		p.input:set_rect(-9999, -9999, 400, 10)
		p:text(PAD, fy + math.floor((m.FOOTER_H - lh) / 2),
			I.t("click network to connect · secured asks password"), T.hint)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.nets = M.nets or {}
	M.scroll = 0
	M.pending = nil
	M._str = M._str or I.t("wifi -")
	M.radio = nil
	M.refresh_acc = 0
	M.status_acc = 2000	-- first fast status poll right away
	M.sjob = nil
	local panel = Panel.new(ctx, {
		name = "wifi",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(380, us.w)
				m.VROWS = math.max(3, math.floor((us.h - m.fixed) / m.ROW_H))
				m.H = m.fixed + m.VROWS * m.ROW_H
			end
			return m
		end,
		size_fn = function(c) -- auto-fit: height follows the scanned list length
			local m = compute_layout(c, c.get_line_height())
			local n = M.nets and #M.nets or 0
			if n > 0 and n < m.VROWS then
				m.VROWS = n
			end
			m.H = m.fixed + m.VROWS * m.ROW_H
			return m.W, m.H
		end,
		draw = do_draw,
		input = {
			placeholder = I.t("wifi password"),
			max_bytes = 128,
			on_change = function() end,
			on_submit = function(v)
				if M.pending then
					connect_async(M.ctx, M.pending, v)
					M.pending = nil
					if M.panel then
						M.panel.input:blur()
						M.panel.input:set_value("")
					end
				end
			end,
			on_cancel = function()
				if M.pending then
					M.pending = nil
					if M.panel then
						M.panel.input:blur()
						M.panel.input:set_value("")
					end
				else
					if M.panel then
						M.panel:hide()
					end
				end
			end,
		},
		on_key = function(p, sym)
			if sym == XK_ESCAPE and not M.pending then
				p:hide()
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 then
				M.scroll = M.scroll - 3
				clamp_scroll()
				p:draw()
				return
			end
			if btn == 5 then
				M.scroll = M.scroll + 3
				clamp_scroll()
				p:draw()
				return
			end
			local m = p.m
			if btn == 1 and not M.pending
				and mx >= m.rect_list.x and mx < m.rect_list.x + m.rect_list.w
				and my >= m.rect_list.y and my < m.rect_list.y + m.rect_list.h then
				local row = math.floor((my - m.rect_list.y) / m.ROW_H)
				local idx = M.scroll + row + 1
				if idx >= 1 and idx <= #M.nets then
					local net = M.nets[idx]
					if net.active then
						return
					elseif not net.sec then
						connect_async(ctx, net, nil)
					else
						M.pending = net
						p.input:focus()
					end
				end
			end
		end,
		on_show = function(p)
			M.pending = nil
			M.scroll = 0
			if p.input then
				p.input:set_value("")
			end
			-- instant open from cache; refresh in background
			async_refresh(ctx)
			p:draw()
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("wifi", panel)
	load_opts(ctx)
	log("ready")
end

function M.width(ctx)
	local str = M._str or I.t("wifi -")
	return select(1, ctx.get_text_size(str)) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "wifi" and ctx.popup_visible
	local str = M._str or I.t("wifi -")
	local col
	if not M.radio then
		col = active and ctx.theme.primary or ctx.theme.crit
	elseif M.ssid then
		local sig = M.signal or 0
		col = sig >= 70 and ctx.theme.good or sig >= 40 and ctx.theme.warn or ctx.theme.crit
	else
		col = ctx.theme.hint
	end
	s:text(x + 10, math.floor((h - lh) / 2), str, col)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "wifi", gx, gw)
	end
end

function M.tick(ctx, dt)
	if not M.ready then
		return
	end
	-- poll background scan job
	if M.job then
		local j = M.job
		j.total = j.total + dt
		j.acc = j.acc + dt
		if j.acc >= 400 then
			j.acc = 0
			local f = io.open(j.path, "r")
			if f then
				local content = f:read("*a")
				f:close()
				if content:find("DONE", 1, true) then
					os.remove(j.path)
					M.job = nil
					M.scanning = false
					local old = M._str
					apply_scan(content)
					if M.panel then
						M.panel:fit() -- auto-fit to list length
					end
					if M.panel and M.panel.visible then
						M.panel:draw()
					end
					if ctx.bar and M._str ~= old then
						ctx.bar.needs_redraw = true
					end
				end
			end
		end
		if M.job and M.job.total > 25000 then
			os.remove(j.path)
			M.job = nil
			M.scanning = false
			log("scan timeout")
		end
	end
	-- poll background connect result
	if M.conn_check then
		local cc = M.conn_check
		cc.total = cc.total + dt
		cc.wait = cc.wait - dt
		if cc.wait <= 0 then
			local f = io.open(cc.path, "r")
			if f then
				local rc = (f:read("*l") or ""):match("^%s*(.-)%s*$")
				f:close()
				os.remove(cc.path)
				M.conn_check = nil
				async_refresh(ctx)
				if rc == "0" then
					ctx.notify(I.t("connected: %s", cc.ssid), { style = "success" })
				else
					ctx.notify(I.t("connect failed: %s", cc.ssid), { style = "error" })
				end
			elseif cc.total > 45000 then
				os.remove(cc.path)
				M.conn_check = nil
				ctx.notify(I.t("connect timeout: %s", cc.ssid), { style = "error" })
			else
				cc.wait = 500
			end
		end
	end
	-- poll background status job (fast bar cadence, no rescan)
	if M.sjob then
		local sj = M.sjob
		sj.total = sj.total + dt
		sj.acc = sj.acc + dt
		if sj.acc >= 400 then
			sj.acc = 0
			local f = io.open(sj.path, "r")
			if f then
				local content = f:read("*a")
				f:close()
				if content:find("DONE", 1, true) then
					os.remove(sj.path)
					M.sjob = nil
					apply_status(ctx, content)
				end
			end
		end
		if M.sjob and M.sjob.total > 15000 then
			os.remove(sj.path)
			M.sjob = nil
			log("status timeout")
		end
	end
	-- status cadence: ~2s keeps the bar realtime; full rescan below keeps
	-- opts.refresh_sec
	M.status_acc = (M.status_acc or 0) + dt
	if M.status_acc >= 2000 then
		M.status_acc = 0
		status_async()
	end
	-- periodic refresh: async only, never blocks the main loop
	local interval = (M.panel and M.panel.visible) and opts.refresh_sec * 1000 or 60000
	M.refresh_acc = (M.refresh_acc or 0) + dt
	if M.refresh_acc >= interval then
		M.refresh_acc = 0
		if not M.job and not M.conn_check then
			async_refresh(ctx)
		end
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.ctx = nil
end

return M
