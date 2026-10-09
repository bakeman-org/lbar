-- plugins/sysinfo.lua — fastfetch-style system info, MIUIX card-group look:
-- rounded surface cards per group, hint-coloured group titles, labels in
-- on_var / right-aligned values in hint, inset hairline row dividers.
-- Sync data from procfs; slow probes (gpu/pkg/disk/ip/arch) run as a
-- background shell job polled from tick (never block the main loop).
local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("sysinfo")

local REFRESH_MS = 2000
local PROBE_FILE = "/tmp/lbar-sysinfo-probe"
local PROBE_TIMEOUT_MS = 6000

-- MIUIX-style geometry: rounded card groups, unified side padding, small
-- hint-coloured group titles with wide group separation
local PAD = 20
local CARD_R = 14
local ROW_GAP = 8 -- gap after a group card
local GROUP_GAP = 28 -- gap between a card and the next group title
local TOP_PAD = 14 -- breathing room under the header

local probe = { tried = false, done = false, acc = 0, data = {} }

local function read_first(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*l")
	f:close()
	return s
end

local function read_all(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function fmt_bytes(gib)
	if gib >= 1024 then
		return string.format("%.1f TiB", gib / 1024)
	end
	return string.format("%.1f GiB", gib)
end

local function fmt_uptime(sec)
	if not sec then
		return "--"
	end
	local d = math.floor(sec / 86400)
	local h = math.floor((sec % 86400) / 3600)
	local m = math.floor((sec % 3600) / 60)
	if d > 0 then
		return I.t("%dd %dh %dm", d, h, m)
	end
	if h > 0 then
		return I.t("%dh %dm", h, m)
	end
	return I.t("%dm", m)
end

local function start_probe()
	if probe.tried then
		return
	end
	probe.tried = true
	probe.done = false
	probe.acc = 0
	probe.data = {}
	os.remove(PROBE_FILE)
	local script = [[
(
printf 'arch=%s\n' "$(uname -m)"
printf 'ip=%s\n' "$(hostname -I 2>/dev/null | awk '{print $1}')"
printf 'gpu=%s\n' "$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' | head -n1 | sed 's/^[0-9a-fA-F:.]* //; s/^[^:]*: *//')"
printf 'pkgs=%s\n' "$(if command -v dpkg >/dev/null 2>&1; then echo "$(dpkg -l 2>/dev/null | grep -c '^ii') (dpkg)"; elif command -v pacman >/dev/null 2>&1; then echo "$(pacman -Q 2>/dev/null | wc -l) (pacman)"; elif command -v rpm >/dev/null 2>&1; then echo "$(rpm -qa 2>/dev/null | wc -l) (rpm)"; else echo '?'; fi)"
printf 'disk=%s\n' "$(df -h / 2>/dev/null | tail -n1 | awk '{print $3" / "$2}')"
echo DONE
) > ]] .. PROBE_FILE .. [[ 2>&1 &
]]
	os.execute(script)
end

local function poll_probe()
	local f = io.open(PROBE_FILE, "r")
	if not f then
		return
	end
	local s = f:read("*a")
	f:close()
	if not s:find("DONE", 1, true) then
		return
	end
	os.remove(PROBE_FILE)
	local d = {}
	for k, v in s:gmatch("([%w_]+)=([^\n]*)") do
		d[k] = v
	end
	probe.data = d
	probe.done = true
end

-- groups: { { title = <i18n key>, rows = { { k = label_key, v = value } } } }
local function gather(ctx)
	local sys, hw = {}, {}
	local P = probe.data

	local osrel = read_all("/etc/os-release") or ""
	local distro = osrel:match('PRETTY_NAME="([^"]+)"') or "Linux"
	if P.arch and P.arch ~= "" then
		distro = distro .. "  " .. P.arch
	end

	local ver = read_first("/proc/version") or ""
	local kernel = ver:match("Linux version ([%w%.%-_]+)") or "?"

	local desktop = os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("DESKTOP_SESSION")
	local sess = os.getenv("XDG_SESSION_TYPE")
	local de = desktop and (sess and (desktop .. "  (" .. sess .. ")") or desktop) or (sess or "--")

	local shell = os.getenv("SHELL") or "?"
	shell = shell:match("([^/]+)$") or shell

	local ut = read_first("/proc/uptime")
	local uptime_sec = ut and tonumber(ut:match("([%d%.]+)"))

	local cpuinfo = read_all("/proc/cpuinfo") or ""
	local model = cpuinfo:match("model name%s*:%s*([^\n]+)") or "?"
	local cores = 0
	for _ in cpuinfo:gmatch("processor%s*:") do
		cores = cores + 1
	end
	local mhz = cpuinfo:match("cpu MHz%s*:%s*([%d%.]+)")
	if mhz then
		model = model .. string.format("  (%d) @ %.1fGHz", cores, tonumber(mhz) / 1000)
	elseif cores > 0 then
		model = model .. "  (" .. cores .. ")"
	end

	local mi = read_all("/proc/meminfo") or ""
	local function mem_kb(k)
		return tonumber(mi:match(k .. ":%s*(%d+)"))
	end
	local mem = "--"
	local total_kb = mem_kb("MemTotal")
	local avail_kb = mem_kb("MemAvailable")
	if total_kb and avail_kb then
		local used_gib = (total_kb - avail_kb) / 1024 / 1024
		local total_gib = total_kb / 1024 / 1024
		mem = string.format("%s / %s", fmt_bytes(used_gib), fmt_bytes(total_gib))
	end

	sys[#sys + 1] = { k = "OS", v = distro }
	sys[#sys + 1] = { k = "Kernel", v = kernel }
	sys[#sys + 1] = { k = "DE/WM", v = de }
	sys[#sys + 1] = { k = "Shell", v = shell }
	sys[#sys + 1] = { k = "Locale", v = os.getenv("LANG") or "--" }
	sys[#sys + 1] = { k = "Uptime", v = fmt_uptime(uptime_sec) }
	if P.pkgs and P.pkgs ~= "" and P.pkgs ~= "?" then
		sys[#sys + 1] = { k = "Packages", v = P.pkgs }
	end
	sys[#sys + 1] = { k = "Resolution", v = string.format("%dx%d", ctx.scr_w, ctx.scr_h) }
	if P.ip and P.ip ~= "" then
		sys[#sys + 1] = { k = "Local IP", v = P.ip }
	end

	hw[#hw + 1] = { k = "Processor", v = model }
	if P.gpu and P.gpu ~= "" then
		hw[#hw + 1] = { k = "GPU", v = P.gpu }
	end
	hw[#hw + 1] = { k = "Memory", v = mem }
	if P.disk and P.disk ~= "" then
		hw[#hw + 1] = { k = "Disk", v = P.disk .. "  /" }
	end

	return {
		{ title = "system", rows = sys },
		{ title = "hardware", rows = hw },
	}
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local groups = M.rows or gather(ctx)
	local header_h = lh + 26
	local footer_h = lh + 30
	local hero_h = lh * 2 + 28
	local title_h = lh + 8
	local row_h = math.max(40, lh + 24)
	local label_w, val_w = 0, 0
	local n_rows = 0
	for _, g in ipairs(groups) do
		for _, r in ipairs(g.rows) do
			n_rows = n_rows + 1
			local lw = select(1, ctx.get_text_size(I.t(r.k)))
			local vw = select(1, ctx.get_text_size(r.v))
			if lw > label_w then
				label_w = lw
			end
			if vw > val_w then
				val_w = vw
			end
		end
	end
	local host = (os.getenv("USER") or "?") .. "@" ..
		(read_first("/proc/sys/kernel/hostname") or "?")
	local title_w = select(1, ctx.get_text_size(host))
	-- label left (16 inset) + min gap + value right (16 inset)
	local W = math.max(560, math.min(880,
		PAD * 2 + 32 + label_w + 40 + val_w, PAD + 80 + title_w))
	local H = header_h + TOP_PAD + hero_h + footer_h
	for _, g in ipairs(groups) do
		H = H + GROUP_GAP + title_h + #g.rows * row_h + 12 + ROW_GAP
	end
	-- natural height from the content rows, capped at 85% of the screen
	-- (overflow rows are clipped behind the opaque footer band)
	H = math.min(H, math.floor(ctx.scr_h * 0.85))
	if user_size then
		W = math.max(W, user_size.w)
		H = math.max(H, user_size.h)
	end
	return {
		LH = lh, PAD = PAD, W = W, H = H,
		HEADER_H = header_h, FOOTER_H = footer_h,
		HERO_H = hero_h, TITLE_H = title_h, ROW_H = row_h,
		ROWS = n_rows,
	}
end

local function truncate(ctx, value, max_w)
	if select(1, ctx.get_text_size(value)) <= max_w then
		return value
	end
	local cut = #value
	while cut > 0 do
		local sub = value:sub(1, cut)
		if select(1, ctx.get_text_size(sub .. "…")) <= max_w then
			return sub .. "…"
		end
		cut = cut - 1
	end
	return "…"
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	local lh, PAD = m.LH, m.PAD
	-- self-heal on resize: follow the live surface so right/bottom edges and
	-- value truncation always match p.w/p.h
	m.W, m.H = p.w, p.h
	local W, H = m.W, m.H
	local card_w = W - PAD * 2
	local CR = PAD + card_w

	local groups = M.rows or gather(ctx)

	-- content is painted FIRST; the fixed chrome (footer, header) is painted
	-- on top further down, which clips overflowing rows without a scissor

	local y = m.HEADER_H + TOP_PAD

	local host = os.getenv("USER") or "?"
	local hostname = read_first("/proc/sys/kernel/hostname") or "?"
	local osrel = read_all("/etc/os-release") or ""
	local distro = osrel:match('PRETTY_NAME="([^"]+)"') or "Linux"

	-- hero: accent dot + user@host, distro subtitle
	p:rrect(PAD, y + math.floor((lh - 10) / 2), 10, 10, 5, T.primary)
	p:text(PAD + 20, y, host .. "@" .. hostname, T.on_var)
	y = y + lh + 4
	p:text(PAD + 20, y, distro, T.hint)
	y = y + lh + 10

	for gi, g in ipairs(groups) do
		if #g.rows > 0 then
			y = y + GROUP_GAP
			p:text(PAD + 6, y + m.TITLE_H - lh - 2, I.t(g.title), T.hint)
			y = y + m.TITLE_H
			local card_h = #g.rows * m.ROW_H + 12
			p:rrect(PAD, y, card_w, card_h, CARD_R, T.surface)
			local ry = y + 6
			for ri, r in ipairs(g.rows) do
				local ty = ry + math.floor((m.ROW_H - lh) / 2)
				local label = I.t(r.k)
				p:text(PAD + 16, ty, label, T.on_var)
				local max_w = CR - 16 - (PAD + 16 + select(1, ctx.get_text_size(label)) + 12)
				local v = truncate(ctx, r.v, max_w)
				local vw = select(1, ctx.get_text_size(v))
				p:text(CR - 16 - vw, ty, v, T.hint)
				-- inset hairline between rows in the same group card
				if ri < #g.rows then
					p:rect(PAD + 16, ry + m.ROW_H - 1, card_w - 32, 1, T.outline)
				end
				ry = ry + m.ROW_H
			end
			y = y + card_h + ROW_GAP
		end
	end

	-- fixed chrome painted last so content can never overlap it

	-- footer: opaque band with a 1px outline separator on top
	local fy = H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local by = fy + math.floor((m.FOOTER_H - lh) / 2)
	p:text(PAD, by, I.t("live refresh · 2s"), T.hint)
	local src = I.t(probe.done and "procfs + probe" or "procfs")
	p:text(W - PAD - select(1, ctx.get_text_size(src)), by, src, T.hint)

	-- header last: opaque fill also covers anything under the top edge
	p:draw_header(I.t("System Info"), Util.keybind_hint(ctx, "toggle_sysinfo"), PAD)
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("info"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "sysinfo" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("info"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysinfo", gx, gw)
	end
end

-- auto-fit: the natural size depends on the gathered rows (probe rows for
-- gpu/pkg/disk/ip appear asynchronously), so re-fit when the row count or
-- probe state changed; fit() itself no-ops when unchanged or user-resized
local function row_count()
	local n = 0
	for _, g in ipairs(M.rows or {}) do
		n = n + #g.rows
	end
	return n
end

local function refit_if_changed()
	local p = M.panel
	if not p then
		return
	end
	local key = row_count() .. "/" .. (probe.done and "p" or "-")
	if key ~= M._fit_key then
		M._fit_key = key
		p:fit()
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true

	local panel = Panel.new(ctx, {
		name = "sysinfo",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_show = function()
			M.rows = gather(ctx)
			if not probe.tried then
				start_probe()
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("sysinfo", panel)

	M.rows = gather(ctx)
	M.refresh_acc = 0
	M._fit_key = row_count() .. "/" .. (probe.done and "p" or "-")

	log("ready")
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	if probe.tried and not probe.done then
		probe.acc = probe.acc + dt
		poll_probe()
		if probe.done or probe.acc >= PROBE_TIMEOUT_MS then
			probe.done = true
			if M.panel.visible then
				M.rows = gather(ctx)
				M.panel:draw()
			end
		end
	end
	M.refresh_acc = M.refresh_acc + dt
	if M.refresh_acc >= REFRESH_MS then
		M.refresh_acc = 0
		M.rows = gather(ctx)
		if M.panel.visible then
			M.panel:draw()
		end
	end
	refit_if_changed()
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
