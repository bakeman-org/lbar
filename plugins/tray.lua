-- plugins/tray.lua — 系统托盘（XEmbed 协议）bar item
--
-- 让把图标放进"通知区域"的程序显示在栏里。仅实现经典的 XEmbed 系统托盘
-- 协议（_NET_SYSTEM_TRAY_S<n>），适用于 X11 应用、Wine、Java、旧版 Qt/GTK；
-- 依赖 XWayland。原生 SNI（DBus StatusNotifierItem，如多数 Electron/GTK3 应用）
-- 不在此协议内。
--
-- • X11 后端：图标被重parent进栏窗口，由 X 原生渲染，点击直接生效。
-- • Wayland 后端：图标窗口映射在屏幕外，像素被拷贝进栏表面，点击转发给图标。
local M = {}
local Util = require("core.util")

local log = Util.logger("tray")

local function cfg(ctx)
	return (ctx.config and ctx.config.tray) or {}
end

-- 图标尺寸随栏高自适应，避免超出
local function icon_size(ctx)
	local want = tonumber(cfg(ctx).icon_size) or 20
	local h = (ctx.bar and ctx.bar.h) or 40
	return math.max(12, math.min(want, h - 10))
end

local function gap_size(ctx)
	local g = tonumber(cfg(ctx).gap) or 6
	return g >= 0 and g or 0
end

local PAD = 4

function M.init(ctx)
	M.ctx = ctx
	M._ready = false
	M._acc = 0
	if cfg(ctx).enabled == false then
		log("disabled by config")
		return
	end
	local bg = 0
	if ctx.theme and ctx.theme.surface then
		bg = tonumber(ctx.theme.surface) or 0
	end
	local rc = ctx.L.lbar_tray_init(ctx.Lctx, icon_size(ctx), bg)
	if rc ~= 0 then
		log("system tray unavailable (no X11/XWayland host)")
		return
	end
	M._ready = true
	log("ready: XEmbed host active")
end

function M.width(ctx)
	if not M._ready then
		return 0
	end
	local n = ctx.L.lbar_tray_count(ctx.Lctx)
	if n <= 0 then
		return 0
	end
	local icon, gap = icon_size(ctx), gap_size(ctx)
	return n * icon + (n - 1) * gap + PAD * 2
end

function M.draw(ctx, s, x, y, w, h)
	if not M._ready then
		return
	end
	local n = ctx.L.lbar_tray_count(ctx.Lctx)
	if n <= 0 then
		return
	end
	local icon, gap = icon_size(ctx), gap_size(ctx)
	local bar = ctx.bar
	local ox, oy = (bar and bar.x) or 0, (bar and bar.y) or 0
	ctx.L.lbar_tray_layout(ctx.Lctx, x + PAD, math.floor((h - icon) / 2), ox, oy, icon, gap)
	if ctx.backend_kind == "wayland" then
		ctx.L.lbar_tray_blit(ctx.Lctx, s.surf, s.w, s.h)
	end
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if not M._ready then
		return
	end
	-- 仅 Wayland 需要转发：X11 下点击由服务器直接送达图标子窗口
	if ctx.backend_kind == "wayland" and btn >= 1 and btn <= 5 then
		local h = (ctx.bar and ctx.bar.h) or 40
		local off = math.floor((h - icon_size(ctx)) / 2)
		ctx.L.lbar_tray_click(ctx.Lctx, lx - PAD, ly - off, btn)
	end
end

function M.tick(ctx, dt)
	if not M._ready then
		return
	end
	-- Wayland 下图标像素只有栏重绘时才会刷新：定期请求重绘以免图标陈旧
	if ctx.backend_kind == "wayland" and ctx.L.lbar_tray_count(ctx.Lctx) > 0 then
		M._acc = M._acc + dt
		if M._acc >= 400 then
			M._acc = 0
			if ctx.bar then
				ctx.bar.needs_redraw = true
			end
		end
	end
end

function M.shutdown()
	M._ready = false
	M._acc = 0
	M.ctx = nil
end

return M
