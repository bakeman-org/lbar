local M = {}
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("sysinfo")

local REFRESH_MS = 2000

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
		return string.format("%dd %dh %dm", d, h, m)
	end
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	return string.format("%dm", m)
end

local function gather(ctx)
	local rows = {}

	local host = read_first("/proc/sys/kernel/hostname") or "?"
	rows[#rows + 1] = { "host", host }

	local osrel = read_all("/etc/os-release") or ""
	local distro = osrel:match('PRETTY_NAME="([^"]+)"') or "Linux"
	rows[#rows + 1] = { "os", distro }

	local ver = read_first("/proc/version") or ""
	local kernel = ver:match("Linux version ([%w%.%-_]+)") or "?"
	rows[#rows + 1] = { "kernel", kernel }

	local desktop = os.getenv("XDG_CURRENT_DESKTOP") or os.getenv("DESKTOP_SESSION") or "--"
	rows[#rows + 1] = { "desktop", desktop }

	local shell = os.getenv("SHELL") or "?"
	shell = shell:match("([^/]+)$") or shell
	rows[#rows + 1] = { "shell", shell }

	rows[#rows + 1] = { "user", os.getenv("USER") or "?" }

	rows[#rows + 1] = { sep = true }

	local cpuinfo = read_all("/proc/cpuinfo") or ""
	local model = cpuinfo:match("model name%s*:%s*([^\n]+)") or "?"
	local mhz = cpuinfo:match("cpu MHz%s*:%s*([%d%.]+)")
	if mhz then
		model = model .. string.format(" @ %.2f GHz", tonumber(mhz) / 1000)
	end
	rows[#rows + 1] = { "cpu", model }

	local la = read_first("/proc/loadavg") or ""
	local l1, l5, l15 = la:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
	if l1 then
		rows[#rows + 1] = { "load", string.format("%s  %s  %s", l1, l5, l15) }
	end

	local mi = read_all("/proc/meminfo") or ""
	local function mem_kb(k)
		return tonumber(mi:match(k .. ":%s*(%d+)"))
	end
	local total_kb = mem_kb("MemTotal")
	local avail_kb = mem_kb("MemAvailable")
	if total_kb and avail_kb then
		local used_kb = total_kb - avail_kb
		local total_gib = total_kb / 1024 / 1024
		local used_gib = used_kb / 1024 / 1024
		local pct = math.floor(used_kb / total_kb * 100)
		rows[#rows + 1] = {
			"memory",
			string.format("%s / %s  (%d%%)", fmt_bytes(used_gib), fmt_bytes(total_gib), pct),
		}
	end

	local ut = read_first("/proc/uptime")
	local uptime_sec = ut and tonumber(ut:match("([%d%.]+)"))
	rows[#rows + 1] = { "uptime", fmt_uptime(uptime_sec) }

	rows[#rows + 1] = { "resolution", string.format("%dx%d", ctx.scr_w, ctx.scr_h) }

	return rows
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local sample = gather(ctx)
	local header_h = lh + 26
	local footer_h = lh + 16
	local row_h = lh + 6
	local label_w, val_w = 0, 0
	for _, r in ipairs(sample) do
		if not r.sep then
			local lw = select(1, ctx.get_text_size(r[1]))
			local vw = select(1, ctx.get_text_size(r[2]))
			if lw > label_w then
				label_w = lw
			end
			if vw > val_w then
				val_w = vw
			end
		end
	end
	local W = math.max(520, math.min(860, 22 + label_w + 36 + val_w + 26))
	local m = {
		LH = lh,
		PAD = 22,
		W = W,
		H = header_h + row_h * #sample + footer_h + 32,
	}
	if user_size then
		m.W = math.max(m.W, user_size.w)
		m.H = math.max(m.H, user_size.h)
	end
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local T = ctx.theme
	local lh, PAD = m.LH, m.PAD
	local W, H = m.W, m.H

	local header_h = p:draw_header("System Info", Util.keybind_hint(ctx, "toggle_sysinfo"), PAD)

	local label_w = 0
	for _, r in ipairs(M.rows) do
		if not r.sep then
			local w = select(1, ctx.get_text_size(r[1]))
			if w > label_w then
				label_w = w
			end
		end
	end
	label_w = label_w + 36
	local value_x = PAD + label_w

	local y = header_h + 14
	local row_h = lh + 6
	for _, r in ipairs(M.rows) do
		if r.sep then
			p:rect(PAD, y + math.floor(row_h / 2) - 1, W - PAD * 2, 1, T.outline)
			y = y + row_h
		else
			local tw = select(1, ctx.get_text_size(r[2]))
			local max_w = W - value_x - PAD
			local value = r[2]
			if tw > max_w then
				local cut = #value
				while cut > 0 do
					local sub = value:sub(1, cut)
					if select(1, ctx.get_text_size(sub .. "…")) <= max_w then
						value = sub .. "…"
						break
					end
					cut = cut - 1
				end
			end
			p:text(PAD, y, r[1], T.hint)
			p:text(value_x, y, value, T.on_surface)
			y = y + row_h
		end
	end

	local by = H - lh - 12
	p:rect(PAD, by - 8, W - PAD * 2, 1, T.outline)

	local src = "procfs"
	p:text(PAD, by, "live refresh · 2s", T.hint)
	local sw = select(1, ctx.get_text_size(src))
	p:text(W - PAD - sw, by, src, T.hint)
end

function M.width(ctx)
	return select(1, ctx.get_text_size("info")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "sysinfo" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "info", active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "sysinfo", gx, gw)
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
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
			end
		end,
		on_show = function()
			M.rows = gather(ctx)
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

	log("ready")
end

function M.tick(ctx, dt)
	if not M.ready or not M.panel then
		return
	end
	M.refresh_acc = M.refresh_acc + dt
	if M.refresh_acc >= REFRESH_MS then
		M.refresh_acc = 0
		M.rows = gather(ctx)
		if M.panel.visible then
			M.panel:draw()
		end
	end
end

function M.shutdown()
	M.ready = false
	M.ctx = nil
end

return M
