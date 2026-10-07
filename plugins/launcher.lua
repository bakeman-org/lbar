local M = {}
local bit = require("bit")
local Panel = require("core.panel")
local Util = require("core.util")

local log = Util.logger("launcher")
local truncate = Util.truncate

local XK_Up = 0xff52
local XK_Down = 0xff54
local XK_e = 0x0065
local XK_E = 0x0045
local MOD1_MASK = 0x0008

local function load_dmenu_path()
	local out = {}
	local p = io.popen("dmenu_path 2>/dev/null")
	if not p then
		return out
	end
	for line in p:lines() do
		local s = line:match("^%s*(.-)%s*$")
		if s ~= "" then
			out[#out + 1] = s
		end
	end
	p:close()
	return out
end

function M.reload_entries()
	local cfg = M.ctx.config.launcher or {}
	local entries, seen = {}, {}

	for _, e in ipairs(cfg.entries or {}) do
		if e.cmd and e.cmd ~= "" then
			local name = e.name or e.cmd
			entries[#entries + 1] = { name = name, cmd = e.cmd }
			seen[name] = true
		end
	end

	if cfg.use_dmenu_path ~= false then
		for _, cmd in ipairs(load_dmenu_path()) do
			if not seen[cmd] then
				entries[#entries + 1] = { name = cmd, cmd = cmd }
				seen[cmd] = true
			end
		end
	end

	M.entries = entries
	M.filtered = entries
	M.sel = #entries > 0 and 1 or 0
	M.scroll = 0
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local m = {
		LH = lh,
		PAD = 20,
		W = 520,
		APPBAR = lh + 26,
		SEARCH_H = lh + 20,
		ROW_H = lh + 20,
		VROWS = 8,
	}
	if user_size then
		m.W = math.max(360, user_size.w)
		local used = m.APPBAR + 14 + m.SEARCH_H + 12 + 14
		m.VROWS = math.max(3, math.floor((user_size.h - used) / m.ROW_H))
	end
	m.H = m.APPBAR + 14 + m.SEARCH_H + 12 + m.VROWS * m.ROW_H + 14
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH
	local W, H = m.W, m.H

	p:draw_header("Apps", Util.keybind_hint(ctx, "toggle_launcher"), m.PAD)

	local sy = m.APPBAR + 14
	local in_w = W - m.PAD * 2 - 28 - 12
	p.input:set_rect(m.PAD, sy, in_w, m.SEARCH_H)
	p.input:draw(p)

	local list_y = sy + m.SEARCH_H + 12
	local n = #M.filtered
	for i = 1, m.VROWS do
		local li = M.scroll + i
		if li > n then
			break
		end
		local e = M.filtered[li]
		local ry = list_y + (i - 1) * m.ROW_H
		local sel = li == M.sel
		local hover = ui:hover(0, ry, W, m.ROW_H)
		local row_bg = sel and T.surface_hi or (hover and T.surface_hi or T.bg)
		p:rect(8, ry, W - 16, m.ROW_H, row_bg)
		if sel then
			p:rrect(14, ry + 6, 4, m.ROW_H - 12, 2, T.primary)
		end
		p:rrect(28, ry + math.floor((m.ROW_H - 8) / 2), 8, 8, 4, sel and T.primary or T.outline)
		local ty = ry + math.floor((m.ROW_H - lh) / 2)
		p:text(48, ty, truncate(e.name, 24), sel and T.on_surface or T.on_var)
		local cw = select(1, ctx.get_text_size(e.cmd))
		if cw > W - 48 - 24 - 200 then
			p:text(W - 24 - math.min(cw, 260), ty, truncate(e.cmd, 34), T.hint)
		else
			p:text(W - 24 - cw, ty, e.cmd, T.hint)
		end
		if ui:clicked(0, ry, W, m.ROW_H) then
			M.sel = li
			M.launch(e)
		end
	end

	if n == 0 then
		local empty = M.query ~= "" and "no matching apps, press Enter to run as command"
			or "configure apps in config.lua launcher.entries"
		p:text(math.floor(W / 2 - select(1, ctx.get_text_size(empty)) / 2), list_y + 40, empty, T.hint)
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size("apps")) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "launcher" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), "apps", active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "launcher", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.query = ""
	M.reload_entries()

	local panel = Panel.new(ctx, {
		name = "launcher",
		pos = "top",
		anim = "slide_down",
		radius = 16,
		bg = ctx.theme.bg,
		model_fn = build_model,
		size_fn = function(c)
			local m = build_model(c)
			return m.W, m.H
		end,
		draw = do_draw,
		on_show = function(p)
			M.reload_entries()
			M.query = ""
			if p.input then
				p.input:set_value("")
			end
			M.sel = #M.filtered > 0 and 1 or 0
			M.scroll = 0
		end,
		input = {
			placeholder = "search apps, or type a command and press Enter",
			on_change = function(v)
				M.query = v
				M.apply_filter()
			end,
			on_submit = function(v)
				M.submit(v)
			end,
			on_cancel = function()
				M.panel:hide()
			end,
		},
		on_key = function(p, sym, text, ctrl, shift, state)
			local alt = state and bit.band(state, MOD1_MASK) ~= 0
			if ctrl and alt and (sym == XK_e or sym == XK_E) then
				p:hide()
				return true
			end
			if sym == XK_Up then
				M.move_sel(-1)
				return true
			elseif sym == XK_Down then
				M.move_sel(1)
				return true
			end
			return false
		end,
		on_press = function(p, mx, my, btn)
			if btn == 1 and p:header_hit(mx, my) then
				p:hide()
				return
			end
			if btn == 4 or btn == 5 then
				M.move_sel(btn == 4 and -1 or 1)
			end
		end,
	})
	if not panel then
		log("panel create failed")
		return
	end
	panel.m = build_model(ctx)
	M.panel = panel
	ctx.register_panel("launcher", panel)
	log("ready: %d entries", #M.entries)
end

function M.move_sel(d)
	local n = #M.filtered
	if n == 0 then
		M.sel = 0
		return
	end
	M.sel = M.sel + d
	if M.sel < 1 then
		M.sel = 1
	end
	if M.sel > n then
		M.sel = n
	end
	if M.sel < M.scroll + 1 then
		M.scroll = M.sel - 1
	end
	if M.sel > M.scroll + M.panel.m.VROWS then
		M.scroll = M.sel - M.panel.m.VROWS
	end
	local mx_s = math.max(0, n - M.panel.m.VROWS)
	if M.scroll > mx_s then
		M.scroll = mx_s
	end
	if M.scroll < 0 then
		M.scroll = 0
	end
	M.panel:draw()
end

function M.apply_filter()
	if M.query == "" then
		M.filtered = M.entries
	else
		local ql = M.query:lower()
		local out = {}
		for _, e in ipairs(M.entries) do
			if e.name:lower():find(ql, 1, true) or e.cmd:lower():find(ql, 1, true) then
				out[#out + 1] = e
			end
		end
		M.filtered = out
	end
	M.sel = #M.filtered > 0 and 1 or 0
	M.scroll = 0
end

function M.run(cmd)
	local esc = cmd:gsub("'", "'\\''")
	os.execute(string.format("nohup sh -c '%s' >/dev/null 2>&1 &", esc))
end

function M.launch(e)
	M.run(e.cmd)
	M.ctx.notify(e.name, { style = "success" })
	M.panel:hide()
end

function M.submit(v)
	if M.sel >= 1 and M.filtered[M.sel] then
		M.launch(M.filtered[M.sel])
		return
	end
	local q = (v or ""):match("^%s*(.-)%s*$")
	if q == "" then
		return
	end
	for _, e in ipairs(M.entries) do
		if e.name == q or e.cmd == q then
			M.launch(e)
			return
		end
	end
	M.run(q)
	M.ctx.notify("ran: " .. truncate(q, 40), { style = "info" })
	M.panel:hide()
end

function M.shutdown()
	M.ctx = nil
end

return M
