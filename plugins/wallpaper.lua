-- plugins/wallpaper.lua — wallpaper picker panel
-- setter auto-detect: swww (wayland, daemon auto-started) > swaybg (sway)
-- > hyprpaper (hyprland) > feh > nitrogen > xwallpaper (X11 / i3),
-- or force via config.wallpaper.set_cmd with $f placeholder

-- TODO: notice this tool require hyprpaper running when using hyprland

local M = {}
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("wallpaper")
local XK_ESCAPE = 0xff1b

local opts = {}

local DEFAULT_DIRS = { "~/Pictures", "~/Pictures/wallpapers", "~/Pictures/Wallpapers", "~/wallpapers" }

local function shq(s)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function expand(p)
	if p:sub(1, 1) == "~" then
		p = (os.getenv("HOME") or "") .. p:sub(2)
	end
	return p
end

local function load_opts(ctx)
	local c = ctx.config.wallpaper or {}
	opts = {
		dir = c.dir or DEFAULT_DIRS,
		depth = tonumber(c.depth) or 3,
		set_cmd = c.set_cmd,
		max_items = tonumber(c.max_items) or 300,
	}
end

local function command_exists(c)
	local p = io.popen("command -v " .. c .. " 2>/dev/null")
	local r = p and p:read("*l")
	if p then
		p:close()
	end
	return r ~= nil and r ~= ""
end

local function proc_running(name)
	local p = io.popen("pgrep -x " .. name .. " 2>/dev/null")
	local r = p and p:read("*l")
	if p then
		p:close()
	end
	return r ~= nil
end

local function detect_tool(ctx)
	if opts.set_cmd then
		return "cmd"
	end
	if M._tool then
		return M._tool
	end
	local wayland = (os.getenv("WAYLAND_DISPLAY") or os.getenv("NIRI_SOCKET")
		or os.getenv("SWAYSOCK") or os.getenv("HYPRLAND_INSTANCE_SIGNATURE")) ~= nil
	local t
	if proc_running("swww-daemon") then
		t = "swww"
	elseif os.getenv("SWAYSOCK") and command_exists("swaybg") then
		t = "swaybg"
	elseif os.getenv("HYPRLAND_INSTANCE_SIGNATURE") and command_exists("hyprctl") then
		t = "hyprpaper"
	elseif wayland and command_exists("swww") then
		t = "swww"
	elseif command_exists("feh") then
		t = "feh"
	elseif command_exists("nitrogen") then
		t = "nitrogen"
	elseif command_exists("xwallpaper") then
		t = "xwallpaper"
	elseif command_exists("swaybg") then
		t = "swaybg"
	elseif command_exists("hyprctl") then
		t = "hyprpaper"
	end
	M._tool = t
	if t then
		log("wallpaper tool: %s", t)
	else
		log("no wallpaper tool found (swww/feh/nitrogen/xwallpaper/swaybg/hyprpaper)")
	end
	return t
end

local function set_wall(ctx, path)
	local tool = detect_tool(ctx)
	if not tool then
		ctx.notify(I.t("no wallpaper tool found (swww/feh/nitrogen/...)"), { style = "error" })
		return
	end
	local ok, cmd
	if tool == "cmd" then
		cmd = opts.set_cmd:gsub("%$f", function()
			return shq(path)
		end)
	elseif tool == "swww" then
		if not proc_running("swww-daemon") then
			log("starting swww-daemon")
			os.execute("swww-daemon >/dev/null 2>&1 &")
			os.execute("sleep 0.4")
		end
		cmd = "swww img " .. shq(path)
	elseif tool == "swaybg" then
		-- swaybg must keep running; respawn it detached
		os.execute("pkill -x swaybg 2>/dev/null; swaybg -i " .. shq(path)
			.. " -m fill >/dev/null 2>&1 &")
		M.cur = path
		ctx.notify(I.t("wallpaper: %s", path:match("[^/]+$") or path), { style = "success" })
		if M.panel and M.panel.visible then
			M.panel:draw()
		end
		return
	elseif tool == "hyprpaper" then
		os.execute("hyprctl hyprpaper preload " .. shq(path) .. " >/dev/null 2>&1")
		ok = os.execute("hyprctl hyprpaper wallpaper " .. shq("," .. path) .. " >/dev/null 2>&1")
		if M.cur and M.cur ~= path then
			os.execute("hyprctl hyprpaper unload " .. shq(M.cur) .. " >/dev/null 2>&1")
		end
	elseif tool == "feh" then
		cmd = "feh --bg-fill " .. shq(path)
	elseif tool == "nitrogen" then
		cmd = "nitrogen --set-zoom-fill " .. shq(path)
	elseif tool == "xwallpaper" then
		cmd = "xwallpaper --zoom " .. shq(path)
	end
	if cmd then
		log("set: %s", cmd)
		ok = os.execute(cmd .. " >/dev/null 2>&1")
	end
	if ok then
		M.cur = path
		ctx.notify(I.t("wallpaper: %s", path:match("[^/]+$") or path), { style = "success" })
	else
		ctx.notify(I.t("set wallpaper failed (%s) — check lbar log", tool), { style = "error" })
	end
	if M.panel and M.panel.visible then
		M.panel:draw()
	end
end

-- scan runs as a background job (find can take a moment on big dirs);
-- results are polled from a temp file in tick so panel opens are instant
local function scan_async(ctx)
	if M.job then
		return
	end
	local dirs = opts.dir
	if type(dirs) == "string" then
		dirs = { dirs }
	end
	local exts = { "jpg", "jpeg", "png", "bmp", "webp", "gif" }
	local tests = {}
	for _, e in ipairs(exts) do
		tests[#tests + 1] = "-iname '*." .. e .. "'"
	end
	local tmp = string.format("/tmp/lbar-wall-%d-%d", os.time(), math.random(10000))
	local cmds = {}
	for _, d in ipairs(dirs) do
		cmds[#cmds + 1] = string.format(
			"find %s -maxdepth %d -type f \\( %s \\) 2>/dev/null | head -n %d",
			shq(expand(d)), opts.depth, table.concat(tests, " -o "), opts.max_items)
	end
	local script = string.format("(%s; echo DONE) > %s 2>&1 &", table.concat(cmds, "; "), shq(tmp))
	os.execute(script)
	M.job = { path = tmp, acc = 0, total = 0 }
	M.scanning = true
	log("scan started")
	if M.panel and M.panel.visible then
		M.panel:draw()
	end
end

local function clamp_scroll()
	local m = M.panel and M.panel.m
	local rows = m and m.VROWS or 10
	local maxs = math.max(0, #M.files - rows)
	if M.scroll > maxs then
		M.scroll = maxs
	end
	if M.scroll < 0 then
		M.scroll = 0
	end
end

local function apply_scan(content)
	local files = {}
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		if line == "DONE" then
			break
		elseif line ~= "" then
			files[#files + 1] = line
			if #files >= opts.max_items then
				break
			end
		end
	end
	M.files = files
	M.scanned = true
	clamp_scroll()
	log("found %d wallpapers", #files)
end

local function cycle(ctx, dir)
	if #M.files == 0 then
		return
	end
	local idx = 1
	for i, f in ipairs(M.files) do
		if f == M.cur then
			idx = i
			break
		end
	end
	idx = ((idx - 1 + dir) % #M.files) + 1
	set_wall(ctx, M.files[idx])
end

local function compute_layout(ctx, lh)
	local m = { lh = lh, PAD = 20 }
	m.W = 520
	m.HEADER_H = lh + 26
	m.BTN_H = lh + 12
	m.ROW_H = lh + 14
	m.FOOTER_H = lh + 14
	local want_h = math.min(math.floor(ctx.scr_h * 0.7), 640)
	if want_h < 360 then
		want_h = 360
	end
	m.VROWS = math.max(4, math.floor((want_h - m.HEADER_H - m.BTN_H - 24 - m.FOOTER_H) / m.ROW_H))
	m.H = m.HEADER_H + m.BTN_H + 24 + m.VROWS * m.ROW_H + m.FOOTER_H + 12
	m.rect_list = { x = 0, y = 0, w = 0, h = 0 }
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	-- self-heal: model follows the live surface size (user resize) so list
	-- rows and the footer always match the real panel
	m.W, m.H = p.w, p.h
	m.VROWS = math.max(4, math.floor(
		(m.H - m.HEADER_H - m.BTN_H - 24 - m.FOOTER_H - 12) / m.ROW_H))
	local lh, PAD, W = m.lh, m.PAD, m.W

	p:draw_header(I.t("wallpaper"), Util.keybind_hint(ctx, "toggle_wallpaper"), PAD)

	local y = m.HEADER_H + 12
	local bw = math.floor((W - PAD * 2 - 30) / 4)
	local bh = m.BTN_H
	local btns = { "prev", "next", "random", "refresh" }
	for i, name in ipairs(btns) do
		local bx = PAD + (i - 1) * (bw + 10)
		if ui:id_button("wp_" .. name, bx, y, bw, bh, I.t(name), { tonal = true }) then
			if name == "prev" then
				cycle(ctx, -1)
			elseif name == "next" then
				cycle(ctx, 1)
			elseif name == "random" then
				if #M.files > 0 then
					set_wall(ctx, M.files[math.random(#M.files)])
				end
			elseif name == "refresh" then
				M._tool = nil
				scan_async(ctx)
			end
		end
	end
	y = y + bh + 14

	local inner_w = W - PAD * 2 - 10
	m.rect_list.x = PAD
	m.rect_list.y = y
	m.rect_list.w = inner_w
	m.rect_list.h = m.VROWS * m.ROW_H
	clamp_scroll()
	if #M.files == 0 then
		local dirs = opts.dir
		if type(dirs) == "string" then
			dirs = { dirs }
		end
		if M.scanning then
			p:text(PAD + 8, y + 6, I.t("scanning…"), T.hint)
		else
			p:text(PAD + 8, y + 6, I.t("no images found in %s", table.concat(dirs, ", ")), T.hint)
			p:text(PAD + 8, y + 6 + lh + 4, I.t("set config.wallpaper.dir and hit refresh"), T.hint)
		end
	end
	for i = 0, m.VROWS - 1 do
		local idx = M.scroll + i + 1
		if idx > #M.files then
			break
		end
		local f = M.files[idx]
		local ry = y + i * m.ROW_H
		local name = f:match("[^/]+$") or f
		local is_cur = (f == M.cur)
		if ui:hover(PAD - 4, ry, inner_w + 8, m.ROW_H) or is_cur then
			p:rrect(PAD - 4, ry, inner_w + 8, m.ROW_H, 8, is_cur and T.secondary_ctr or T.surface_hover)
		end
		if is_cur then
			p:text(PAD + 4, ry + 5, "✓", T.primary)
		end
		local max_w = inner_w - 40
		if ctx.text_width(name) > max_w then
			while #name > 4 and ctx.text_width(name .. "…") > max_w do
				name = name:sub(1, -2)
			end
			name = name .. "…"
		end
		p:text(PAD + (is_cur and 26 or 4), ry + 5, name, is_cur and T.on_surface or T.on_var)
	end

	if #M.files > m.VROWS then
		local sbar_x = PAD + inner_w + 2
		local list_h = m.rect_list.h
		p:rect(sbar_x, y, 6, list_h, T.surface)
		local bar_h = math.max(30, math.floor(list_h * m.VROWS / #M.files))
		local maxs = #M.files - m.VROWS
		local bar_y = y + math.floor((list_h - bar_h) * M.scroll / maxs)
		p:rrect(sbar_x, bar_y, 6, bar_h, 3, T.outline)
	end

	local by = m.H - m.FOOTER_H + 2
	p:rect(PAD, by - 6, W - PAD * 2, 1, T.outline)
	local tool = M._tool or detect_tool(ctx) or I.t("none")
	local status
	if M.scanning then
		status = I.t("scanning…")
	else
		status = I.t("%d files · tool: %s · click to set", #M.files, tool)
	end
	p:text(PAD, by + 2, status, T.hint)
end

function M.init(ctx)
	M.ctx = ctx
	M.ready = true
	M.files = M.files or {}
	M.scroll = 0
	math.randomseed(os.time())
	local panel = Panel.new(ctx, {
		name = "wallpaper",
		radius = 16,
		bg = ctx.theme.bg,
		kbd = true,
		model_fn = function(c, us)
			local m = compute_layout(c, c.get_line_height())
			if us then
				m.W = math.max(380, us.w)
				m.VROWS = math.max(4, math.floor((us.h - m.HEADER_H - m.BTN_H - 24 - m.FOOTER_H - 12) / m.ROW_H))
				m.H = m.HEADER_H + m.BTN_H + 24 + m.VROWS * m.ROW_H + m.FOOTER_H + 12
			end
			return m
		end,
		size_fn = function(c) -- auto-fit: height follows the scanned list length
			local m = compute_layout(c, c.get_line_height())
			local n = M.files and #M.files or 0
			if n > 0 and n < m.VROWS then
				m.VROWS = n
				m.H = m.HEADER_H + m.BTN_H + 24 + m.VROWS * m.ROW_H + m.FOOTER_H + 12
			end
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
				return
			end
			if btn == 4 then
				M.scroll = M.scroll - 3
				clamp_scroll()
				return
			end
			if btn == 5 then
				M.scroll = M.scroll + 3
				clamp_scroll()
				return
			end
			local m = p.m
			if btn == 1 and mx >= m.rect_list.x and mx < m.rect_list.x + m.rect_list.w
				and my >= m.rect_list.y and my < m.rect_list.y + m.rect_list.h then
				local row = math.floor((my - m.rect_list.y) / m.ROW_H)
				local idx = M.scroll + row + 1
				if idx >= 1 and idx <= #M.files then
					set_wall(ctx, M.files[idx])
				end
			end
		end,
		on_show = function(p)
			-- instant open from cache; scan only if never scanned
			if not M.scanned then
				scan_async(ctx)
			end
			p:draw()
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = compute_layout(ctx, ctx.get_line_height())
	M.panel = panel
	ctx.register_panel("wallpaper", panel)
	load_opts(ctx)
	log("ready: dir=%s", tostring(type(opts.dir) == "table" and table.concat(opts.dir, ",") or opts.dir))
end

function M.width(ctx)
	return ctx.text_width(I.t("wall")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "wallpaper" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("wall"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "wallpaper", gx, gw)
	end
end

function M.tick(ctx, dt)
	if not M.ready or not M.job then
		return
	end
	local j = M.job
	j.total = j.total + dt
	j.acc = j.acc + dt
	if j.acc >= 300 then
		j.acc = 0
		local f = io.open(j.path, "r")
		if f then
			local content = f:read("*a")
			f:close()
			if content:find("DONE", 1, true) then
				os.remove(j.path)
				M.job = nil
				M.scanning = false
				apply_scan(content)
				if M.panel then
					M.panel:fit() -- auto-fit to list length
				end
				if M.panel and M.panel.visible then
					M.panel:draw()
				end
			end
		end
	end
	if M.job and M.job.total > 20000 then
		os.remove(j.path)
		M.job = nil
		M.scanning = false
		log("scan timeout")
		if M.panel and M.panel.visible then
			M.panel:draw()
		end
	end
end

function M.shutdown()
	M.ready = false
	M.panel = nil
	M.ctx = nil
end

return M
