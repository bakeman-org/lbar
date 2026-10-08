-- plugins/sysinfo.lua — fastfetch-style system info, macOS grouped-list look:
-- neutral tokens, label left / value right, inset hairline dividers.
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

-- rows: { k = label_key, v = value } or { sep = true }
local function gather(ctx)
	local rows = {}
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

	rows[#rows + 1] = { k = "OS", v = distro }
	rows[#rows + 1] = { k = "Kernel", v = kernel }
	rows[#rows + 1] = { k = "DE/WM", v = de }
	rows[#rows + 1] = { k = "Shell", v = shell }
	rows[#rows + 1] = { k = "Locale", v = os.getenv("LANG") or "--" }
	rows[#rows + 1] = { k = "Uptime", v = fmt_uptime(uptime_sec) }
	if P.pkgs and P.pkgs ~= "" and P.pkgs ~= "?" then
		rows[#rows + 1] = { k = "Packages", v = P.pkgs }
	end
	rows[#rows + 1] = { k = "Resolution", v = string.format("%dx%d", ctx.scr_w, ctx.scr_h) }
	if P.ip and P.ip ~= "" then
		rows[#rows + 1] = { k = "Local IP", v = P.ip }
	end

	rows[#rows + 1] = { sep = true }

	rows[#rows + 1] = { k = "Processor", v = model }
	if P.gpu and P.gpu ~= "" then
		rows[#rows + 1] = { k = "GPU", v = P.gpu }
	end
	rows[#rows + 1] = { k = "Memory", v = mem }
	if P.disk and P.disk ~= "" then
		rows[#rows + 1] = { k = "Disk", v = P.disk .. "  /" }
	end

	return rows
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local sample = gather(ctx)
	local header_h = lh + 26
	local footer_h = lh + 24
	local title_h = lh * 2 + 14
	local row_h = lh + 8
	local label_w, val_w = 0, 0
	for _, r in ipairs(sample) do
		if not r.sep then
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
	local W = math.max(560, math.min(880,
		22 + label_w + 40 + val_w + 26, 22 + title_w + 60))
	local H = header_h + 14 + title_h + row_h * #sample + footer_h + 12
	if user_size then
		W = math.max(W, user_size.w)
		H = math.max(H, user_size.h)
	end
	return { LH = lh, PAD = 22, W = W, H = H, ROW_H = row_h }
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

	local header_h = p:draw_header(I.t("System Info"), Util.keybind_hint(ctx, "toggle_sysinfo"), PAD)

	local host = os.getenv("USER") or "?"
	local hostname = read_first("/proc/sys/kernel/hostname") or "?"
	local osrel = read_all("/etc/os-release") or ""
	local distro = osrel:match('PRETTY_NAME="([^"]+)"') or "Linux"

	-- macOS-style title: accent dot + user@host, distro subtitle
	local y = header_h + 14
	p:rrect(PAD, y + math.floor((lh - 10) / 2), 10, 10, 5, T.primary)
	p:text(PAD + 20, y, host .. "@" .. hostname, T.on_var)
	y = y + lh + 4
	p:text(PAD + 20, y, distro, T.hint)
	y = y + lh + 10

	local row_h = m.ROW_H
	local rows = M.rows or gather(ctx)
	for i, r in ipairs(rows) do
		if r.sep then
			y = y + 6
			p:rect(PAD, y + math.floor(row_h / 2) - 1, W - PAD * 2, 1, T.outline)
			y = y + row_h + 2
		else
			-- inset hairline between rows in the same group
			local next_sep = not rows[i + 1] or rows[i + 1].sep
			if not next_sep then
				p:rect(PAD, y + row_h - 1, W - PAD * 2, 1, T.outline)
			end
			local vw = select(1, ctx.get_text_size(r.v))
			local max_w = W - PAD * 2 - select(1, ctx.get_text_size(I.t(r.k))) - 40
			p:text(PAD, y + 3, I.t(r.k), T.hint)
			p:text(W - PAD - vw, y + 3, truncate(ctx, r.v, max_w), T.on_surface)
			y = y + row_h
		end
	end

	local by = H - lh - 12
	p:rect(PAD, by - 8, W - PAD * 2, 1, T.outline)
	p:text(PAD, by, I.t("live refresh · 2s"), T.hint)
	local src = I.t(probe.done and "procfs + probe" or "procfs")
	p:text(W - PAD - select(1, ctx.get_text_size(src)), by, src, T.hint)
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
local function refit_if_changed()
	local p = M.panel
	if not p then
		return
	end
	local key = #M.rows .. "/" .. (probe.done and "p" or "-")
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
	M._fit_key = #M.rows .. "/" .. (probe.done and "p" or "-")

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
