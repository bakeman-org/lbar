local M = {}
local bit = require("bit")
local Panel = require("core.panel")
local Util = require("core.util")
local I = require("core.i18n")

local log = Util.logger("launcher")
local truncate = Util.truncate

local XK_Up = 0xff52
local XK_Down = 0xff54
local XK_e = 0x0065
local XK_E = 0x0045
local MOD1_MASK = 0x0008

-- MIUIX-style geometry: rounded card rows, unified side padding,
-- scrollbar lane reserved at the right edge
local PAD, SB_W = 20, 6
local ROW_GAP = 8 -- gap between row cards
local CARD_R = 14 -- row card corner radius

local function row_h(lh)
	return math.max(46, lh + 28)
end

-- rough char budget for a pixel width (commands are mostly ASCII)
local function fit_chars(ctx, avail)
	local cw = ctx.text_width("n")
	return math.max(2, math.floor(avail / math.max(4, cw)))
end

-- dmenu_path (~3000 entries) is loaded as a background job; sync loading at
-- init or on every show made the bar stutter and panels slow to open
local function load_dmenu_async(ctx)
	if M.job or not ctx then
		return
	end
	local tmp = string.format("/tmp/lbar-dmenu-%d-%d", os.time(), math.random(10000))
	os.execute(string.format("(dmenu_path 2>/dev/null; echo DONE) > %s 2>&1 &", "'" .. tmp .. "'"))
	M.job = { path = tmp, acc = 0, total = 0 }
end

function M.merge_dmenu()
	local j = M.job
	if not j then
		return
	end
	local f = io.open(j.path, "r")
	if not f then
		return false
	end
	local content = f:read("*a")
	f:close()
	if not content:find("DONE", 1, true) then
		return false
	end
	os.remove(j.path)
	M.job = nil
	local cfg = M.ctx.config.launcher or {}
	if cfg.use_dmenu_path == false then
		return true
	end
	local seen = {}
	for _, e in ipairs(M.entries) do
		seen[e.name] = true
	end
	local added = 0
	for line in (content .. "\n"):gmatch("([^\n]*)\n") do
		local s = line:match("^%s*(.-)%s*$")
		if s ~= "" and s ~= "DONE" and not seen[s] then
			seen[s] = true
			M.entries[#M.entries + 1] = { name = s, cmd = s }
			added = added + 1
		end
	end
	if added > 0 then
		log("dmenu_path: +%d entries", added)
		M.apply_filter()
		if M.panel and M.panel.visible then
			M.panel:draw()
		end
	end
	return true
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

	M.entries = entries
	M.filtered = entries
	M.sel = #entries > 0 and 1 or 0
	M.scroll = 0
end

local function build_model(ctx, user_size)
	local lh = ctx.get_line_height()
	local n = M.filtered and #M.filtered or 0
	local m = {
		LH = lh,
		PAD = PAD,
		W = 520,
		APPBAR = lh + 26,
		IN_H = lh + 24,
		SEARCH_H = 14 + (lh + 24) + 12,
		ROW_H = row_h(lh),
		ROW_GAP = ROW_GAP,
		FOOTER_H = lh + 30,
	}
	m.view_y = m.APPBAR + m.SEARCH_H
	if user_size then
		m.W = math.max(360, user_size.w)
		m.H = math.max(240, user_size.h)
	else
		-- natural height follows the (roomy) card rows, capped at 85% of
		-- the screen; overflow scrolls inside the view
		local content = math.max(1, n) * (m.ROW_H + ROW_GAP)
		m.H = math.max(m.view_y + m.ROW_H + m.FOOTER_H,
			math.min(ctx.scr_h * 0.85, m.view_y + content + m.FOOTER_H))
	end
	m.VROWS = math.max(1, math.floor((m.H - m.view_y - m.FOOTER_H + ROW_GAP) / (m.ROW_H + ROW_GAP)))
	return m
end

local function do_draw(p)
	local m = p.m
	local ctx = p.ctx
	local ui = p.ui
	local T = ctx.theme
	local lh = m.LH

	-- self-heal on resize: model follows the live surface so the view band,
	-- visible row count and footer always match the real panel
	m.W, m.H = p.w, p.h
	local in_extra = p.input and p.input:extra_h() or 0
	m.view_y = m.APPBAR + m.SEARCH_H + in_extra
	m.view_h = math.max(m.ROW_H, m.H - m.view_y - m.FOOTER_H)
	m.VROWS = math.max(1, math.floor((m.view_h + m.ROW_GAP) / (m.ROW_H + m.ROW_GAP)))
	local W, H = m.W, m.H
	local n = #M.filtered

	local CR = W - PAD - SB_W -- card right edge
	local card_w = CR - PAD

	-- scrollable content is painted FIRST; the fixed chrome (header, search
	-- band, footer) is painted on top further down, which clips every row
	-- to the view band without needing a scissor primitive
	local maxs = math.max(0, n - m.VROWS)
	M.scroll = math.max(0, math.min(maxs, M.scroll))
	for i = 1, m.VROWS do
		local li = M.scroll + i
		if li > n then
			break
		end
		local e = M.filtered[li]
		local ry = m.view_y + (i - 1) * (m.ROW_H + m.ROW_GAP)
		local sel = li == M.sel
		local hover = ui:hover(PAD, ry, card_w, m.ROW_H)
		p:rrect(PAD, ry, card_w, m.ROW_H, CARD_R,
			sel and T.surface_hi or (hover and T.surface_hover or T.surface))
		local ty = ry + math.floor((m.ROW_H - lh) / 2)
		p:rrect(PAD + 16, ry + math.floor((m.ROW_H - 8) / 2), 8, 8, 4, sel and T.primary or T.outline)
		local name = truncate(e.name, 24)
		p:text(PAD + 36, ty, name, sel and T.on_surface or T.on_var)
		-- command right-aligned, truncated to the space next to the name
		local cmd = e.cmd
		local avail = CR - 16 - (PAD + 36 + ctx.text_width(name) + 12)
		if ctx.text_width(cmd) > avail then
			cmd = truncate(cmd, fit_chars(ctx, math.max(40, avail)))
		end
		p:text(CR - 16 - ctx.text_width(cmd), ty, cmd, T.hint)
		if ui:clicked(PAD, ry, card_w, m.ROW_H) then
			-- never launch mid-draw: queue for M.tick (pcall'd there)
			M.pending_launch = e
		end
	end

	if n == 0 then
		local empty = M.query ~= "" and I.t("no matching apps, press Enter to run as command")
			or I.t("configure apps in config.lua launcher.entries")
		local ew = ctx.text_width(empty)
		local ey = m.view_y + math.floor(math.max(0, m.view_h - lh) / 2)
		p:text(math.floor(W / 2 - ew / 2), ey, empty, T.hint)
	end

	-- scrollbar (right edge, inside padding)
	if maxs > 0 then
		local off = ui:scrollbar("scr", W - 14, m.view_y, SB_W, m.view_h, M.scroll, maxs)
		M.scroll = off
	end

	-- fixed chrome painted last so scrolled content can never overlap it

	-- search band: opaque fill over the scrolled rows, then the input
	p:rect(0, m.APPBAR, W, m.SEARCH_H + in_extra, p.bg)
	p.input:set_rect(PAD, m.APPBAR + 14, W - PAD * 2 - SB_W, m.IN_H)
	p.input:draw(p)

	-- header (draw_header paints its own opaque band)
	p:draw_header(I.t("Apps"), Util.keybind_hint(ctx, "toggle_launcher"), PAD)

	-- footer: opaque band covers rows scrolled past the bottom; pill
	-- button laid out like a MIUI dialog (primary action filled)
	local fy = H - m.FOOTER_H
	p:rect(0, fy, W, m.FOOTER_H, p.bg)
	p:rect(PAD, fy, W - PAD * 2, 1, T.outline)
	local mid_y = fy + math.floor((m.FOOTER_H - lh) / 2)
	local cnt = M.query ~= "" and string.format("%d / %d", n, #M.entries) or tostring(n)
	p:text(PAD, mid_y, cnt, T.hint)
	local bw = 72
	local bh = lh + 14
	local bo = math.floor((m.FOOTER_H - bh) / 2)
	if ui:id_button("ft_close", W - PAD - bw, fy + bo, bw, bh, I.t("close"), { filled = true }) then
		-- never hide a panel mid-draw: defer like settings does
		M.pending_action = function()
			p:hide()
		end
	end
end

function M.width(ctx)
	return select(1, ctx.get_text_size(I.t("Apps"))) + 20
end

function M.draw(ctx, s, x, y, w, h)
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "launcher" and ctx.popup_visible
	s:text(x + 10, math.floor((h - lh) / 2), I.t("Apps"), active and ctx.theme.primary or ctx.theme.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "launcher", gx, gw)
	end
end

function M.init(ctx)
	M.ctx = ctx
	M.query = ""
	M.pending_launch = nil
	M.pending_action = nil
	M.reload_entries()
	if (ctx.config.launcher or {}).use_dmenu_path ~= false then
		load_dmenu_async(ctx)
	end

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
			-- entries are cached; never block the open with a dmenu_path reload
			M.query = ""
			if p.input then
				p.input:set_value("")
			end
			M.sel = #M.filtered > 0 and 1 or 0
			M.scroll = 0
			if #M.entries == 0 and not M.job
				and (ctx.config.launcher or {}).use_dmenu_path ~= false then
				load_dmenu_async(ctx)
			end
		end,
		input = {
			placeholder = I.t("search apps…"),
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
	M.ctx.notify(I.t("ran: %s", truncate(q, 40)), { style = "info" })
	M.panel:hide()
end

function M.tick(ctx, dt)
	if M.job then
		local j = M.job
		j.total = (j.total or 0) + dt
		j.acc = (j.acc or 0) + dt
		if j.acc >= 300 then
			j.acc = 0
			if M.merge_dmenu() and ctx.bar then
				ctx.bar.needs_redraw = true
			end
		end
		if M.job and M.job.total > 15000 then
			os.remove(M.job.path)
			M.job = nil
			log("dmenu_path timeout")
		end
	end
	-- UI actions queued by draw() run here, outside the draw pass,
	-- pcall-guarded so a failure can never take the bar down
	if M.pending_launch then
		local e = M.pending_launch
		M.pending_launch = nil
		pcall(M.launch, e)
	end
	if M.pending_action then
		local fn = M.pending_action
		M.pending_action = nil
		pcall(fn)
	end
	-- auto-fit when the filtered result count changes (cheap change guard;
	-- fit() itself no-ops when the size already matches or user resized)
	if M.panel and #M.filtered ~= (M.fit_n or -1) then
		M.fit_n = #M.filtered
		M.panel:fit()
	end
end

function M.shutdown()
	M.pending_launch = nil
	M.pending_action = nil
	M.ctx = nil
end

return M
