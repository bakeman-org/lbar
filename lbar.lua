#!/usr/bin/env luajit
local SCRIPT_DIR = (arg[0] or "lbar.lua"):match("^(.*)/[^/]*$") or "."
if SCRIPT_DIR == "" then
	SCRIPT_DIR = "."
end
package.path = SCRIPT_DIR .. "/?.lua;" .. package.path
package.cpath = SCRIPT_DIR .. "/?.so;" .. package.cpath

local init = require("core.init")(SCRIPT_DIR)
local Bar = require("core.bar")
local PluginMgr = require("core.plugins")
local Util = require("core.util")
local ffi = init.ffi
local libc = init.libc
local L = init.L
local log = Util.logger("lbar")

-- ── config ──────────────────────────────────────────────
local CONFIG_PATH = (arg[1] and arg[1] ~= "") and arg[1] or (SCRIPT_DIR .. "/config.lua")

local function resolve_path(p)
	if not p or p == "" then
		return p
	end
	if p:sub(1, 1) == "~" then
		p = (os.getenv("HOME") or "") .. p:sub(2)
	end
	if p:sub(1, 1) == "/" then
		return p
	end
	return SCRIPT_DIR .. "/" .. p
end

local function normalize(cfg)
	cfg.font_path = resolve_path(cfg.font_path)
	cfg.fallback_font_paths = cfg.fallback_font_paths or {}
	for i, p in ipairs(cfg.fallback_font_paths) do
		cfg.fallback_font_paths[i] = resolve_path(p)
	end
	return cfg
end

local config = normalize(dofile(CONFIG_PATH))

-- ── backend ─────────────────────────────────────────────
local Lctx = L.lbar_open()
if Lctx == nil then
	error("lbar_open failed")
end
local kind = ffi.string(L.lbar_backend(Lctx))
log("backend: %s", kind)

-- ── FreeType ────────────────────────────────────────────
if L.xft_init() ~= 0 then
	error("FreeType init failed")
end

local function load_font(cfg)
	local fb = table.concat(cfg.fallback_font_paths or {}, "\n")
	return L.xft_load(cfg.font_path, cfg.font_size or 14, #fb > 0 and fb or nil)
end

local ft_ctx = load_font(config)
if ft_ctx == nil then
	error("font load failed: " .. config.font_path)
end

-- ── ctx ─────────────────────────────────────────────────
local ctx = {
	SCRIPT_DIR = SCRIPT_DIR,
	ffi = ffi,
	L = L,
	Lctx = Lctx,
	ft_ctx = ft_ctx,
	config = config,
	theme = {},
	log = log,
	backend_kind = kind,
	popup_visible = false,
	active_plugin_name = nil,
}
ctx.scr_w = L.lbar_screen_w(Lctx)
ctx.scr_h = L.lbar_screen_h(Lctx)

function ctx.get_text_size(s)
	local w, h = ffi.new("int[1]"), ffi.new("int[1]")
	L.xft_text_extent(ft_ctx, s, w, h)
	return w[0], h[0]
end
function ctx.get_line_height()
	return L.xft_primary_line_height(ft_ctx)
end

local function build_theme(cfg)
	return {
		bg = cfg.bg or 0x1e1e2e,
		fg = cfg.fg or 0xe6e1e5,
		dim = cfg.dim or 0x98989d,
		accent = cfg.accent or 0x0a84ff,
		accent_hi = cfg.accent_hi or 0x3a9bff,
		warn = cfg.warn or 0xff9f0a,
		crit = cfg.crit or 0xff453a,
		good = cfg.good or 0x30d158,
		surface = cfg.surface or 0x2c2c2e,
		bar_bg = cfg.bar_bg or 0x1c1c1e,
	}
end
ctx.theme = build_theme(config)

-- ── popup registry (defined before plugin load) ─────────
local popups = {}

function ctx.register_popup(name, popup)
	popups[name] = popup
end

function ctx.show_popup(name, anchor_x, anchor_y, direction)
	for n, p in pairs(popups) do
		if p.visible and n ~= name then
			p:hide()
		end
	end
	local p = popups[name]
	if not p then
		return
	end
	if p.visible then
		p:hide()
		ctx.active_plugin_name = nil
		if ctx.bar then
			ctx.bar.needs_redraw = true
		end
		return
	end
	p:show(anchor_x, anchor_y, direction)
	ctx.active_plugin_name = name
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

function ctx.close_popup()
	for _, p in pairs(popups) do
		if p.visible then
			p:hide()
		end
	end
	ctx.active_plugin_name = nil
	if ctx.bar then
		ctx.bar.needs_redraw = true
	end
end

-- ── bar ─────────────────────────────────────────────────
local function build_bar(cfg)
	local bar, err = Bar.new(ctx, cfg)
	if not bar then
		return nil, err
	end
	PluginMgr.load_all(ctx, bar, cfg.plugins or {})
	return bar
end

local bar, err = build_bar(config)
if not bar then
	error("bar init: " .. tostring(err))
end
ctx.bar = bar

-- ── hot reload ──────────────────────────────────────────
local function watch_paths(cfg)
	local paths = { CONFIG_PATH }
	for _, name in ipairs(cfg.plugins or {}) do
		paths[#paths + 1] = SCRIPT_DIR .. "/plugins/" .. name .. ".lua"
	end
	return paths
end

local wpaths = watch_paths(config)
local wmtimes = PluginMgr.snapshot_mtimes(wpaths)

local function reload_all()
	local ok, newcfg = pcall(dofile, CONFIG_PATH)
	if not ok or type(newcfg) ~= "table" then
		log("config reload failed: %s", tostring(newcfg))
		return
	end
	newcfg = normalize(newcfg)

	local font_changed = newcfg.font_path ~= config.font_path or newcfg.font_size ~= config.font_size
	if not font_changed then
		local a = table.concat(config.fallback_font_paths or {}, "\n")
		local b = table.concat(newcfg.fallback_font_paths or {}, "\n")
		font_changed = a ~= b
	end

	ctx.close_popup()
	bar:destroy()

	-- reset popups BEFORE plugins re-register their popups
	popups = {}

	config = newcfg
	ctx.config = config
	ctx.theme = build_theme(config)

	if font_changed then
		local ok_f, nf = pcall(load_font, config)
		if ok_f and nf then
			L.xft_done(ft_ctx)
			ft_ctx = nf
			ctx.ft_ctx = nf
			log("font reloaded: %s @ %d", config.font_path, config.font_size or 14)
		else
			log("font reload failed: %s", tostring(nf))
		end
	end

	L.lbar_close(Lctx)
	Lctx = L.lbar_open()
	ctx.Lctx = Lctx
	ctx.scr_w = L.lbar_screen_w(Lctx)
	ctx.scr_h = L.lbar_screen_h(Lctx)

	bar, err = build_bar(config)
	if not bar then
		log("bar rebuild failed: %s", tostring(err))
		os.exit(1)
	end
	ctx.bar = bar

	wpaths = watch_paths(config)
	wmtimes = PluginMgr.snapshot_mtimes(wpaths)
	log("hot reload done: %s @ %s h=%d plugins=%d", kind, bar.pos, bar.h, #bar.plugins)
end

-- ── event loop ──────────────────────────────────────────
ffi.cdef([[
  typedef struct { long tv_sec; long tv_nsec; } lbar_ts;
]])
local ts = ffi.new("lbar_ts[1]")
local function now_ms()
	libc.clock_gettime(1, ts)
	return tonumber(ts[0].tv_sec) * 1000 + tonumber(ts[0].tv_nsec) / 1e6
end

local TICK_MS = 200
local WATCH_MS = 800
local watch_accum = 0
local last_tick = now_ms()
local ev = ffi.new("lbar_event_t")

log("lbar running (%s, %dx%d, plugins=%d)", kind, ctx.scr_w, ctx.scr_h, #bar.plugins)

while true do
	L.lbar_poll(Lctx, 16)

	while L.lbar_next_event(Lctx, ev) ~= 0 do
		local t = ev.type
		local tgt = ev.target
		if t == 4 then
			if tgt == 0 then
				bar.needs_redraw = true
			else
				local vis = L.lbar_popup_visible(Lctx) ~= 0
				ctx.popup_visible = vis
				if not vis then
					-- backend hid the surface; sync Lua-side state too
					for _, p in pairs(popups) do
						p.visible = false
					end
					ctx.active_plugin_name = nil
					bar.needs_redraw = true
				end
			end
		elseif t == 1 then
			if tgt == 1 then
				for _, p in pairs(popups) do
					if p.visible then
						p:on_motion(ev.x, ev.y)
						break
					end
				end
			else
				bar:on_motion(ev.x, ev.y)
			end
		elseif t == 2 then
			if tgt == 1 then
				for _, p in pairs(popups) do
					if p.visible then
						p:on_press(ev.button, ev.x, ev.y)
						break
					end
				end
			else
				bar:on_click(ev.button, ev.x, ev.y)
			end
		end
	end

	local now = now_ms()
	local dt = now - last_tick
	if dt >= TICK_MS then
		bar:tick(dt)
		last_tick = now

		watch_accum = watch_accum + dt
		if watch_accum >= WATCH_MS then
			watch_accum = 0
			if PluginMgr.watch(ctx, bar, wpaths, wmtimes) then
				log("change detected, reloading...")
				reload_all()
			end
		end
	end
end
