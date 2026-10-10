-- core/ui2.lua — 声明式 UI 框架（webdev 风格）
--
-- 目标：像 web 开发一样写插件面板——结构声明一次，
-- 测量 / 布局 / 绘制 / 命中全部自动。跳出手算 x/y/width 的繁琐。
--
-- 用法骨架：
--   local ui2 = require("core.ui2")
--   local state = ui2.state({ count = 0 })
--   local b = ui2.panel(ctx, { name = "demo", title = "Demo" })
--   b:column({ pad = 20, gap = 12 })
--     :h1("Hello ui2")
--     :p({ value = function() return "count: " .. state.count end })
--     :row({ gap = 8 })
--       :button({ label = "+1", action = function() state.count = state.count + 1 end })
--       :button({ label = "reset", tonal = true, action = function() state.count = 0 end })
--     :end_()
--     :each(function() return state.items end, function(item, i, row)
--       row:p({ value = item, color = "hint" })
--     end)
--   :end_()
--   ui2.reactive(state, b, ctx)   -- state 变更 → 自动重绘
--   ctx.register_panel("demo", b.panel)
--
-- 旧插件 / core.panel / core.ui 一行未动——ui2 只在它们之上加声明层。

local Panel = require("core.panel")
local Icons = require("core.icons")

local M = {}

-- 图标名 → 可绘制字符串（Nerd Font PUA 码点 / ASCII 兜底）
-- 部件的 icon/glyph 参数可以是图标名（"gear"）或原始字符
function M.icon(name)
	return Icons.glyph(name)
end

local XK_ESCAPE = 0xff1b
local XK_BACKSPACE = 0xff08
local XK_RETURN = 0xff0d
local XK_KP_ENTER = 0xff8d

-- ── 工具 ──────────────────────────────────────────────────────────

-- 解析"响应式值"：函数在 draw/measure 时求值，普通值原样返回
local function rv(v, a, b)
	if type(v) == "function" then
		return v(a, b)
	end
	return v
end

-- 主题 token：字符串查 ctx.theme，数字原样
local function color(ctx, c)
	if type(c) == "number" then
		return c
	end
	if type(c) == "string" then
		return ctx.theme and ctx.theme[c] or nil
	end
	return nil
end

-- ── 响应式 state ──────────────────────────────────────────────────
-- s.count = 1 触发全部订阅者（每 key 一次）；s:set{..} 批量。

function M.state(initial)
	local data = {}
	local subs = {}
	local s = setmetatable({}, {
		__newindex = function(_, k, v)
			data[k] = v
			for _, fn in ipairs(subs) do
				local ok, err = pcall(fn, k, v, s)
				if not ok then
					print("ui2 state subscriber error: " .. tostring(err))
				end
			end
		end,
		__index = function(_, k)
			return data[k]
		end,
		__pairs = function()
			return pairs(data)
		end,
	})
	for k, v in pairs(initial or {}) do
		data[k] = v
	end
	function s:subscribe(fn)
		subs[#subs + 1] = fn
		return self
	end
	function s:set(t)
		for k, v in pairs(t) do
			s[k] = v
		end
		return self
	end
	return s
end

-- state 变更 → 面板可见时重绘 + bar 请求重绘。
-- 通常在树构建完成后调用一次。
-- 注意：订阅者可能在 draw 进行中被触发（on_click/on_change 里写 state）。
-- 此时不能重入 Panel:draw（763 行有 _drawing 保护）——标记 _ui2_dirty，
-- 由 M.panel 的 draw 回调在本帧末尾补画（render 中途 visible 翻转会让
-- 未 measure 的子树被绘制，必须整帧重来）。
function M.reactive(state, b_or_panel, ctx)
	local p = b_or_panel.panel or b_or_panel
	state:subscribe(function()
		if p.visible and not p.destroyed then
			if p._drawing then
				p._ui2_dirty = true
			else
				p:draw()
			end
		end
		if ctx and ctx.bar then
			ctx.bar.needs_redraw = true
		end
	end)
	return state
end

-- ── 部件测量 ──────────────────────────────────────────────────────
-- 返回自然尺寸 w, h（draw 时另有分配宽度，可 stretch）。
-- 值支持函数（响应式），measure 与 draw 每帧求值。

local BTN_PADX, BTN_PADY = 18, 14
local TOGGLE_W, TOGGLE_H = 44, 24

-- 颜色工具（color_picker 用），定义在文件尾部
local hsv_rgb, blend

local function measure_node(ctx, node)
	-- visible=false（可为响应式函数）→ 不占布局不绘制
	local vis = node.opts.visible
	if vis ~= nil and not rv(vis) then
		node._mw, node._mh = 0, 0
		return 0, 0
	end
	local lh = ctx.get_line_height()
	local k = node.kind
	if k == "text" then
		local v = rv(node.opts.value) or ""
		local pt, pb = 0, 0
		if type(node.opts.pad) == "table" then
			pt, pb = node.opts.pad[1] or 0, node.opts.pad[2] or 0
		end
		return ctx.text_width(v), lh + pt + pb
	elseif k == "button" then
		local v = rv(node.opts.label) or ""
		local w = node.opts.w or (ctx.text_width(v) + BTN_PADX * 2)
		return w, lh + BTN_PADY
	elseif k == "toggle" then
		return TOGGLE_W, TOGGLE_H
	elseif k == "slider" or k == "progress" then
		return node.opts.w or 120, k == "progress" and (node.opts.h or 8) or 22
	elseif k == "segmented" then
		local items = rv(node.opts.items) or {}
		local w = 0
		for _, it in ipairs(items) do
			w = w + ctx.text_width(tostring(it)) + 24
		end
		return math.max(w, 60), lh + 14
	elseif k == "text_field" then
		return node.opts.w or 160, lh + 16
	elseif k == "divider" then
		return node.opts.w or 0, 1
	elseif k == "spacer" then
		return 0, node.opts.h or 0
	elseif k == "gap" then
		return 0, node.opts.h or 8
	elseif k == "icon" then
		local g = rv(node.opts.glyph) or ""
		return ctx.text_width(g), lh
	-- ── MIUIX 风格部件 ──
	elseif k == "checkbox" or k == "radio" then
		return 20, 20
	elseif k == "icon_button" then
		local sz = node.opts.size or 40
		return sz, sz
	elseif k == "fab" then
		local sz = node.opts.size or 48
		return sz, sz
	elseif k == "stepper" then
		local v = tostring(rv(node.opts.value) or 0)
		return ctx.text_width(v) + 2 * 40 + 16, lh + 16
	elseif k == "search_bar" then
		return node.opts.w or 200, lh + 22
	elseif k == "tab_row" then
		local labels = rv(node.opts.tabs) or {}
		local w = 0
		for _, t in ipairs(labels) do
			w = w + ctx.text_width(tostring(t)) + 28
		end
		return math.max(w, 60), lh + 16
	elseif k == "navigation_bar" then
		local items = rv(node.opts.items) or {}
		return math.max(#items * 84, 200), lh + 26
	elseif k == "breadcrumb" then
		local segs = rv(node.opts.segments) or {}
		local w = 12
		for i, s in ipairs(segs) do
			w = w + ctx.text_width(tostring(s)) + (i < #segs and 20 or 0)
		end
		return w, lh
	elseif k == "badge" then
		local n = rv(node.opts.count)
		if n then
			return ctx.text_width(tostring(n)) + 12, 16
		end
		return 8, 8
	elseif k == "small_title" then
		local v = rv(node.opts.value) or ""
		return ctx.text_width(v), lh + 8
	elseif k == "toolbar" then
		local icons = rv(node.opts.icons) or {}
		local n = math.max(#icons, 1)
		return n * 40 + (n - 1) * 8, 40
	elseif k == "color_palette" then
		local colors = rv(node.opts.colors) or {}
		local per = node.opts.per_row or 6
		local rows = math.max(1, math.ceil(#colors / per))
		return per * 28 + (per - 1) * 8, rows * 28 + (rows - 1) * 8
	elseif k == "list_item" then
		local h = lh + 16
		if rv(node.opts.summary) then
			h = h + lh + 2
		end
		-- 自然宽：icon + 标题/摘要 + 右侧控件（draw 时仍可吃满分配宽度）
		local tw = 0
		local t = rv(node.opts.title)
		if t then
			tw = tw + ctx.text_width(t)
		end
		local s = rv(node.opts.summary)
		if s then
			tw = math.max(tw, ctx.text_width(s))
		end
		if node.opts.icon then
			tw = tw + ctx.text_width(Icons.glyph(node.opts.icon)) + 10
		end
		local right = rv(node.opts.right)
		if right == "switch" or right == "checkbox" or right == "radio" then
			tw = tw + 60
		elseif type(right) == "string" then
			tw = tw + ctx.text_width(right) + 24
		end
		return node.opts.w or math.max(tw + 20, 140), h
	-- ── Miuix 补齐 ──
	elseif k == "top_app_bar" then
		return node.opts.w or 0, lh + 16
	elseif k == "navigation_rail" then
		local items = rv(node.opts.items) or {}
		return node.opts.w or 76, #items * 52 + 12
	elseif k == "range_slider" then
		return node.opts.w or 160, 24
	elseif k == "color_picker" then
		return node.opts.w or 160, 2 * 22 + 14
	elseif k == "dropdown" then
		local v = tostring(rv(node.opts.value) or "")
		return node.opts.w or (ctx.text_width(v) + 40), lh + 14
	elseif k == "dialog" or k == "bottom_sheet" then
		return 0, 0 -- 浮层：不占布局，render 收尾绘制
	end
	-- 容器
	local pad = node.opts.pad
	if pad == nil then
		pad = 8
	end
	local gap = node.opts.gap or 8
	local wmax, hmax, wsum, hsum, flex = 0, 0, 0, 0, 0
	local last = 0
	for _, ch in ipairs(node.children) do
		local cw, chh = measure_node(ctx, ch)
		ch._mw, ch._mh = cw, chh
		-- 不可见子项 / 浮层（dialog 等）不占布局
		local skip = (ch.opts.visible ~= nil and not rv(ch.opts.visible))
			or ch.kind == "dialog" or ch.kind == "bottom_sheet"
		if skip then
			ch._flex = false
		else
			last = last + 1
			ch._flex = (ch.kind == "spacer") and (not ch.opts.h or ch.opts.h == 0)
			if ch._flex then
				flex = flex + 1
			end
			wmax = math.max(wmax, cw)
			hmax = math.max(hmax, chh)
			wsum = wsum + cw
			hsum = hsum + chh
			if last > 1 then
				wsum = wsum + gap
				hsum = hsum + gap
			end
		end
	end
	if k == "column" or k == "card" then
		return wmax + pad * 2, hsum + pad * 2
	elseif k == "row" then
		return wsum + pad * 2, hmax + pad * 2
	end
	return 0, 0
end

-- ── 部件绘制 ──────────────────────────────────────────────────────
-- 在最终坐标 (x, y) 与分配宽度 w 处绘制一个节点（含交互分发）。

local function draw_node(ctx, b, p, node, x, y, w)
	local ui, T = p.ui, ctx.theme
	local lh = ctx.get_line_height()
	local k = node.kind
	local o = node.opts
	if o.visible ~= nil and not rv(o.visible) then
		return
	end
	if k == "text" then
		local v = rv(o.value) or ""
		local fg = color(ctx, o.color) or (o.mono and T.on_var or T.on_surface)
		local bg = color(ctx, o.bg)
		local pt = type(o.pad) == "table" and (o.pad[1] or 0) or 0
		ui:label(x, y + pt, v, fg, bg)
		return
	elseif k == "button" then
		local v = rv(o.label) or ""
		local bw = math.max(w, ctx.text_width(v) + BTN_PADX * 2)
		local bh = lh + BTN_PADY
		local id = "ui2btn:" .. (o.id or tostring(node._id or v))
		local opts = {
			filled = o.filled,
			tonal = o.tonal,
			color = color(ctx, o.color),
			bg = color(ctx, o.bg),
		}
		if ui:id_button(id, x, y, bw, bh, v, opts) then
			local fn = o.action or o.on_click
			if fn then
				fn(p, b)
			end
		end
		return
	elseif k == "toggle" then
		local val = rv(o.value) and true or false
		local nv, changed = ui:toggle("ui2tgl:" .. tostring(node._id), x, y, TOGGLE_W, TOGGLE_H, val)
		if changed and o.on_change then
			o.on_change(nv, p, b)
		end
		return
	elseif k == "slider" then
		local val = rv(o.value) or 0
		local nv, changed = ui:slider("ui2sld:" .. tostring(node._id), x, y + 6, w, val, {
			min = o.min or 0,
			max = o.max or 1,
			color = color(ctx, o.color),
		})
		if changed and o.on_change then
			o.on_change(nv, p, b)
		end
		return
	elseif k == "progress" then
		local pct = rv(o.pct) or 0
		ui:progress(x, y, w, o.h or 8, pct, color(ctx, o.color))
		return
	elseif k == "segmented" then
		local items = rv(o.items) or {}
		local active = rv(o.active) or 1
		local sel = ui:segmented(x, y, w, lh + 14, items, active)
		if sel > 0 and o.on_change then
			o.on_change(sel, p, b)
		end
		return
	elseif k == "text_field" then
		local id = "ui2tf:" .. (o.id or tostring(node._id))
		local v = rv(o.value) or ""
		b._focusbox.fields[id] = node
		local clicked = ui:text_field(id, x, y, w, lh + 16, v, {
			placeholder = o.placeholder,
		})
		if clicked then
			b._focusbox.focus = id
		end
		return
	elseif k == "divider" then
		ui:divider(x, y, w, color(ctx, o.color))
		return
	elseif k == "spacer" or k == "gap" then
		return
	elseif k == "icon" then
		local g = Icons.glyph(rv(o.glyph or o.icon))
		ui:label(x, y, g, color(ctx, o.color) or T.primary)
		return
	-- ── MIUIX 风格部件 ─────────────────────────────────────────
	elseif k == "checkbox" then
		local v = rv(o.value) and true or false
		local id = "ui2cb:" .. tostring(node._id)
		if v then
			p:rrect(x, y, 20, 20, 6, color(ctx, o.color) or T.primary)
			local xs = ctx.text_width("✓")
			p:text(x + math.floor((20 - xs) / 2), y + math.floor((20 - lh) / 2), "✓", T.on_primary)
		else
			p:rrect(x, y, 20, 20, 6, T.outline)
			p:rrect(x + 1, y + 1, 18, 18, 5, color(ctx, o.bg) or T.bg)
		end
		if ui:clicked(x, y, 20, 20) and o.on_change then
			o.on_change(not v, p, b)
		end
		return
	elseif k == "radio" then
		local v = rv(o.value) and true or false
		local cx, cy = x + 10, y + 10
		if v then
			p:rrect(cx - 10, cy - 10, 20, 20, 10, color(ctx, o.color) or T.primary)
			p:rrect(cx - 5, cy - 5, 10, 10, 5, T.on_primary)
		else
			p:rrect(cx - 10, cy - 10, 20, 20, 10, T.outline)
			p:rrect(cx - 9, cy - 9, 18, 18, 9, color(ctx, o.bg) or T.bg)
		end
		if ui:clicked(x, y, 20, 20) and o.on_change then
			o.on_change(true, p, b)
		end
		return
	elseif k == "icon_button" then
		local sz = o.size or 40
		local r = math.floor(sz / 2)
		local hover = ui:hover(x, y, sz, sz)
		p:rrect(x, y, sz, sz, r, hover and T.surface_hover or (color(ctx, o.bg) or T.surface_hi))
		local g = Icons.glyph(rv(o.icon or o.glyph))
		local gs = ctx.text_width(g)
		p:text(x + math.floor((sz - gs) / 2), y + math.floor((sz - lh) / 2), g,
			color(ctx, o.color) or T.on_surface)
		-- tooltip：hover 时在按钮下方画提示
		if hover and o.tooltip then
			local tw = ctx.text_width(o.tooltip)
			p:rrect(x + math.floor((sz - tw - 16) / 2), y + sz + 4, tw + 16, lh + 8, (lh + 8) / 2, T.surface_hover)
			p:text(x + math.floor((sz - tw) / 2), y + sz + 8, o.tooltip, T.on_surface)
		end
		if ui:clicked(x, y, sz, sz) then
			local fn = o.action or o.on_click
			if fn then
				fn(p, b)
			end
		end
		return
	elseif k == "fab" then
		local sz = o.size or 48
		local r = math.floor(sz / 2)
		local hover = ui:hover(x, y, sz, sz)
		p:rrect(x, y, sz, sz, r, hover and T.primary_hi or (color(ctx, o.color) or T.primary))
		local g = Icons.glyph(rv(o.icon or o.glyph) or "plus")
		local gs = ctx.text_width(g)
		p:text(x + math.floor((sz - gs) / 2), y + math.floor((sz - lh) / 2), g, T.on_primary)
		if ui:clicked(x, y, sz, sz) then
			local fn = o.action or o.on_click
			if fn then
				fn(p, b)
			end
		end
		return
	elseif k == "stepper" then
		local v = rv(o.value) or 0
		local step = o.step or 1
		local vs = tostring(v)
		local vw = ctx.text_width(vs)
		local bh = lh + 14
		local id = "ui2stp:" .. tostring(node._id)
		-- [−] value [+]
		if ui:id_button(id .. "-d", x, y, 40, bh, "−", { bg = T.surface_hi }) then
			if o.on_change then
				o.on_change(v - step, p, b)
			end
		end
		p:text(x + 48 + math.floor(vw / 2), y + math.floor((bh - lh) / 2), vs, T.on_surface)
		if ui:id_button(id .. "-u", x + 48 + vw + 16, y, 40, bh, "+", { filled = true }) then
			if o.on_change then
				o.on_change(v + step, p, b)
			end
		end
		return
	elseif k == "search_bar" then
		local v = rv(o.value) or ""
		local h = lh + 22
		local id = "ui2sb:" .. (o.id or tostring(node._id))
		b._focusbox.fields[id] = node
		local clicked = ui:text_field(id, x, y, w, h, v, { placeholder = o.placeholder or "search…" })
		if clicked then
			b._focusbox.focus = id
		end
		-- 前缀放大镜
		p:text(x + 12, y + math.floor((h - lh) / 2), Icons.glyph("search"), T.hint)
		return
	elseif k == "tab_row" then
		local labels = rv(o.tabs) or {}
		local active = rv(o.active) or 1
		local n = math.max(#labels, 1)
		local seg = math.floor(w / n)
		for i, t in ipairs(labels) do
			local sx = x + (i - 1) * seg
			local tw = ctx.text_width(t)
			local fg = (i == active) and T.on_surface or T.hint
			p:text(sx + math.floor((seg - tw) / 2), y + 4, t, fg)
			if i == active then
				p:rrect(sx + math.floor((seg - 24) / 2), y + lh + 12, 24, 3, 2, T.primary)
			end
			if ui:clicked(sx, y, seg, lh + 16) and o.on_change then
				o.on_change(i, p, b)
			end
		end
		return
	elseif k == "navigation_bar" then
		local items = rv(o.items) or {}
		local active = rv(o.active) or 1
		local h = lh + 26
		local n = math.max(#items, 1)
		local seg = math.floor(w / n)
		p:rrect(x, y, w, h, math.floor(h / 2), T.surface_hi)
		for i, it in ipairs(items) do
			local sx = x + (i - 1) * seg
			local is_active = (i == active)
			if is_active then
				p:rrect(sx + 6, y + 5, seg - 12, h - 10, math.floor((h - 10) / 2), T.bg)
			end
			local icon, label = it, it
			if type(it) == "table" then
				icon, label = Icons.glyph(it.icon), it.label
			else
				icon = Icons.glyph(it)
			end
			local iw = ctx.text_width(icon or "")
			p:text(sx + math.floor((seg - iw) / 2), y + 9, icon or "",
				is_active and T.primary or T.hint)
			local lw = ctx.text_width(label or "")
			p:text(sx + math.floor((seg - lw) / 2), y + 9 + lh, label or "",
				is_active and T.primary or T.hint)
			if ui:clicked(sx, y, seg, h) and o.on_change then
				o.on_change(i, p, b)
			end
		end
		return
	elseif k == "breadcrumb" then
		local segs = rv(o.segments) or {}
		local active = rv(o.active) or #segs
		local cx = x + 6
		for i, s in ipairs(segs) do
			local is_active = (i == active)
			local sw = ctx.text_width(s)
			p:text(cx, y, s, is_active and T.on_surface or T.hint)
			if ui:clicked(cx - 2, y, sw + 4, lh) and o.on_change then
				o.on_change(i, p, b)
			end
			cx = cx + sw
			if i < #segs then
				p:text(cx + 6, y, "›", T.outline)
				cx = cx + 20
			end
		end
		return
	elseif k == "badge" then
		local n = rv(o.count)
		if n then
			local vs = tostring(n)
			local bw = ctx.text_width(vs) + 12
			p:rrect(x, y, bw, 16, 8, color(ctx, o.color) or T.primary)
			p:text(x + 6, y + math.floor((16 - lh) / 2), vs, T.on_primary)
		else
			p:rrect(x, y, 8, 8, 4, color(ctx, o.color) or T.crit)
		end
		return
	elseif k == "small_title" then
		local v = rv(o.value) or ""
		ui:label(x, y + 8, v, color(ctx, o.color) or T.hint)
		return
	elseif k == "toolbar" then
		local icons = rv(o.icons) or {}
		local tx = x
		for i, ico in ipairs(icons) do
			local g = Icons.glyph(ico)
			local hover = ui:hover(tx, y, 40, 40)
			p:rrect(tx, y, 40, 40, 20, hover and T.surface_hover or T.surface_hi)
			local gw = ctx.text_width(g)
			p:text(tx + math.floor((40 - gw) / 2), y + math.floor((40 - lh) / 2), g,
				color(ctx, o.color) or T.on_surface)
			if ui:clicked(tx, y, 40, 40) and o.on_select then
				o.on_select(i, g, p, b)
			end
			tx = tx + 48
		end
		return
	elseif k == "color_palette" then
		local colors = rv(o.colors) or {}
		local sel = rv(o.value)
		local per = o.per_row or 6
		local cx, cy = x, y
		for i, c in ipairs(colors) do
			local col = (i - 1) % per
			local row = math.floor((i - 1) / per)
			local sx = x + col * 36
			local sy = y + row * 36
			if c == sel then
				p:rrect(sx - 3, sy - 3, 34, 34, 10, T.on_surface)
			end
			p:rrect(sx, sy, 28, 28, 8, c)
			if ui:clicked(sx, sy, 28, 28) and o.on_change then
				o.on_change(c, i, p, b)
			end
		end
		return
	elseif k == "list_item" then
		local title = rv(o.title) or ""
		local summary = rv(o.summary)
		local right = rv(o.right)
		local ih = lh + 16 + (summary and (lh + 2) or 0)
		local hover = ui:hover(x, y, w, ih)
		if hover then
			p:rrect(x, y, w, ih, 10, T.surface_hover)
		end
		local tx = x + 4
		if o.icon then
			local ico = Icons.glyph(o.icon)
			local iw = ctx.text_width(ico)
			p:text(tx, y + math.floor((ih - lh) / 2), ico, color(ctx, o.icon_color) or T.primary)
			tx = tx + iw + 10
		end
		p:text(tx, y + 8, title, color(ctx, o.title_color) or T.on_surface)
		if summary then
			p:text(tx, y + 10 + lh, summary, T.hint)
		end
		-- 右侧控件
		if right == "arrow" then
			local aw = ctx.text_width("›")
			p:text(x + w - aw - 6, y + math.floor((ih - lh) / 2), "›", T.hint)
		elseif right == "switch" then
			local val = rv(o.value) and true or false
			local nv, changed = ui:toggle("ui2lisw:" .. tostring(node._id),
				x + w - 44, y + math.floor((ih - 24) / 2), 44, 24, val)
			if changed and o.on_change then
				o.on_change(nv, p, b)
			end
		elseif right == "checkbox" then
			local val = rv(o.value) and true or false
			if ui:clicked(x + w - 26, y + math.floor((ih - 20) / 2), 20, 20) then
				if o.on_change then
					o.on_change(not val, p, b)
				end
				val = not val
			end
			if val then
				p:rrect(x + w - 26, y + math.floor((ih - 20) / 2), 20, 20, 6, T.primary)
				local xs = ctx.text_width("✓")
				p:text(x + w - 26 + math.floor((20 - xs) / 2), y + math.floor((ih - lh) / 2), "✓", T.on_primary)
			else
				local cyv = y + math.floor((ih - 20) / 2)
				p:rrect(x + w - 26, cyv, 20, 20, 6, T.outline)
				p:rrect(x + w - 25, cyv + 1, 18, 18, 5, T.bg)
			end
		elseif right == "radio" then
			local val = rv(o.value) and true or false
			local ccx = x + w - 16
			local ccy = y + math.floor(ih / 2)
			if val then
				p:rrect(ccx - 10, ccy - 10, 20, 20, 10, T.primary)
				p:rrect(ccx - 5, ccy - 5, 10, 10, 5, T.on_primary)
			else
				p:rrect(ccx - 10, ccy - 10, 20, 20, 10, T.outline)
				p:rrect(ccx - 9, ccy - 9, 18, 18, 9, T.bg)
			end
			if ui:clicked(ccx - 10, ccy - 10, 20, 20) and o.on_change then
				o.on_change(true, p, b)
			end
		elseif type(right) == "string" then
			local rw = ctx.text_width(right)
			p:text(x + w - rw - 4, y + math.floor((ih - lh) / 2), right, T.hint)
		end
		-- 整行点击（不含右侧控件区，switch/checkbox 自己处理）
		local click_w = (right == "switch" or right == "checkbox" or right == "radio")
			and (w - 52) or w
		if ui:clicked(x, y, click_w, ih) and o.on_click then
			o.on_click(p, b)
		end
		return
	-- ── Miuix 补齐 ─────────────────────────────────────────────
	elseif k == "top_app_bar" then
		local title = rv(o.title) or ""
		p:text(x + 4, y + 8, title, color(ctx, o.color) or T.on_surface)
		local actions = rv(o.actions) or {}
		local ax = x + w
		for i = #actions, 1, -1 do
			ax = ax - 40
			local hover = ui:hover(ax, y, 40, 40)
			if hover then
				p:rrect(ax, y, 40, 40, 20, T.surface_hover)
			end
			local g = Icons.glyph(actions[i])
			local gw = ctx.text_width(g)
			p:text(ax + math.floor((40 - gw) / 2), y + math.floor((40 - lh) / 2), g,
				color(ctx, o.icon_color) or T.on_surface)
			if ui:clicked(ax, y, 40, 40) and o.on_action then
				o.on_action(i, actions[i], p, b)
			end
		end
		p:rrect(x, y + 40, w, 1, 0, T.outline)
		return
	elseif k == "navigation_rail" then
		local items = rv(o.items) or {}
		local active = rv(o.active) or 1
		local rw = w
		local cy = y + 6
		for i, it in ipairs(items) do
			local icon, label = it, it
			if type(it) == "table" then
				icon, label = it.icon, it.label
			end
			icon = Icons.glyph(icon)
			local is_active = (i == active)
			if is_active then
				p:rrect(x + 8, cy, rw - 16, 44, 12, T.surface_hi)
			end
			local iw = ctx.text_width(icon or "")
			p:text(x + math.floor((rw - iw) / 2), cy + 4, icon or "",
				is_active and T.primary or T.hint)
			if label then
				local lw = ctx.text_width(label)
				p:text(x + math.floor((rw - lw) / 2), cy + 4 + lh, label,
					is_active and T.primary or T.hint)
			end
			if ui:clicked(x, cy, rw, 48) and o.on_change then
				o.on_change(i, p, b)
			end
			cy = cy + 52
		end
		return
	elseif k == "range_slider" then
		local min_v, max_v = o.min or 0, o.max or 1
		local span = max_v - min_v
		local old_lo, old_hi = rv(o.value_low) or min_v, rv(o.value_high) or max_v
		local lo = math.max(0, math.min(1, (old_lo - min_v) / span))
		local hi = math.max(0, math.min(1, (old_hi - min_v) / span))
		local id = "ui2rng:" .. tostring(node._id)
		local hit_r = 14
		-- 点击 track：就近 handle 进入拖拽
		local over = ui.mx >= x - hit_r and ui.mx <= x + w + hit_r
			and ui.my >= y - hit_r and ui.my <= y + hit_r + 10
		if ui.mdown and over and not ui.active_id then
			local lx, hx = x + w * lo, x + w * hi
			ui.active_id = (math.abs(ui.mx - lx) <= math.abs(ui.mx - hx))
				and (id .. "-l") or (id .. "-h")
		end
		local nlo, nhi = old_lo, old_hi
		if ui.active_id == id .. "-l" then
			local px = math.max(x, math.min(x + w, ui.mx))
			nlo = math.min(min_v + (px - x) / w * span, old_hi)
		elseif ui.active_id == id .. "-h" then
			local px = math.max(x, math.min(x + w, ui.mx))
			nhi = math.max(min_v + (px - x) / w * span, old_lo)
		end
		-- 值变化才回调（防止拖拽帧 state 写入 → 重入 draw 递归）
		if o.on_change and (nlo ~= old_lo or nhi ~= old_hi) then
			o.on_change(nlo, nhi, p, b)
			old_lo, old_hi = nlo, nhi
			lo = math.max(0, math.min(1, (old_lo - min_v) / span))
			hi = math.max(0, math.min(1, (old_hi - min_v) / span))
		end
		-- track：底轨 + 选中区间
		p:rrect(x, y + 8, w, 6, 3, T.surface_hi)
		p:rrect(x + math.floor(w * lo), y + 8, math.max(6, math.floor(w * (hi - lo))), 6, 3,
			color(ctx, o.color) or T.primary)
		for _, nrm in ipairs({ lo, hi }) do
			local hx = x + math.floor(w * nrm)
			p:rrect(hx - 8, y + 3, 16, 16, 8, T.on_surface)
		end
		return
	elseif k == "color_picker" then
		-- hue 条（固定 sat=1）+ 亮度条，输出 0xRRGGBB
		local old_hue, old_bri = rv(o.hue) or 0, rv(o.bri)
		if old_bri == nil then
			old_bri = 1
		end
		local hue, bri = old_hue, old_bri
		local id = "ui2cp:" .. tostring(node._id)
		local function track(ny)
			local hit_r = 14
			local over = ui.mx >= x - hit_r and ui.mx <= x + w + hit_r
				and ui.my >= ny - hit_r and ui.my <= ny + 6 + hit_r
			if ui.mdown and over and not ui.active_id then
				ui.active_id = id .. ny
			end
			return ui.active_id == (id .. ny)
		end
		-- 色相渐变：24 段
		local seg = math.max(1, math.floor(w / 24))
		for i = 0, 23 do
			p:rrect(x + i * seg, y, math.min(seg, w - i * seg), 6, 0, hsv_rgb(i * 15, 1, 1))
		end
		if track(y) then
			hue = (math.max(x, math.min(x + w, ui.mx)) - x) / w * 360
		end
		p:rrect(x + math.floor(w * (hue % 360) / 360) - 8, y - 5, 16, 16, 8, T.on_surface)
		-- 亮度渐变：黑 → 当前纯色
		local y2 = y + 22
		local pure = hsv_rgb(hue, 1, 1)
		for i = 0, 11 do
			p:rrect(x + i * math.floor(w / 12), y2, math.min(math.floor(w / 12), w - i * math.floor(w / 12)), 6, 0,
				blend(pure, 0, i / 11))
		end
		if track(y2) then
			bri = (math.max(x, math.min(x + w, ui.mx)) - x) / w
		end
		p:rrect(x + math.floor(w * bri) - 8, y2 - 5, 16, 16, 8, T.on_surface)
		-- 值变化才回调（防重入 draw 递归）
		if o.on_change and (hue ~= old_hue or bri ~= old_bri) then
			o.on_change(hue, bri, hsv_rgb(hue, 1, bri), p, b)
		end
		return
	elseif k == "dropdown" then
		-- 按钮常态绘制；open 状态的菜单在 render 收尾阶段画（z 序 + 吞点击）
		local v = tostring(rv(o.value) or "")
		local bw = math.max(w, ctx.text_width(v) + 40)
		local open = node._open
		if not open then
			if ui:id_button("ui2dd:" .. tostring(node._id), x, y, bw, lh + 14, v, { bg = T.surface_hi })
				and not o.disabled then
				node._open = true
			end
			local g = Icons.glyph("chevron_down")
			p:text(x + bw - 18, y + 5, g, T.hint)
		else
			-- 记录按钮几何，供 overlay 阶段使用
			node._bx, node._by, node._bw, node._bh = x, y, bw, lh + 14
			p:rrect(x, y, bw, lh + 14, (lh + 14) / 2, T.surface_hi)
			p:text(x + math.floor((bw - ctx.text_width(v)) / 2), y + 7, v, T.primary)
		end
		return
	elseif k == "dialog" or k == "bottom_sheet" then
		return -- 浮层，render 收尾绘制
	end
end

-- ── 浮层绘制（dropdown 菜单 / dialog / bottom_sheet） ─────────────
-- 在整棵树画完后调用：mrelease 已恢复给浮层，树阶段点击全部被吞。

local function draw_overlay(ctx, b, p, node, ui, rel)
	local T = ctx.theme
	local lh = ctx.get_line_height()
	local o = node.opts
	local k = node.kind

	local function close()
		if o.on_open then
			o.on_open(false, p, b)
		else
			node._open = nil
		end
	end

	if k == "dropdown" then
		local items = rv(o.items) or {}
		local bx, by, bw, bh = node._bx or 0, node._by or 0, node._bw or 120, node._bh or 30
		local mw = 0
		for _, it in ipairs(items) do
			mw = math.max(mw, ctx.text_width(tostring(it)))
		end
		mw = math.max(mw + 32, bw, 100)
		local ih = lh + 12
		local mh = #items * ih + 12
		-- 菜单向下展开，超出面板底则向上
		local my = by + bh + 4
		if my + mh > p.h then
			my = by - mh - 4
		end
		p:rrect(bx, my, mw, mh, 12, T.surface_hi)
		for i, it in ipairs(items) do
			local iy = my + 6 + (i - 1) * ih
			local hover = ui:hover(bx + 4, iy, mw - 8, ih)
			if hover then
				p:rrect(bx + 4, iy, mw - 8, ih, 8, T.surface_hover)
			end
			local s = tostring(it)
			p:text(bx + 12, iy + 6, s, (i == o.active_index) and T.primary or T.on_surface)
			local hit = rel and rel.x >= bx and rel.x < bx + mw and rel.y >= iy and rel.y < iy + ih
			if hit then
				close()
				if o.on_select then
					o.on_select(it, i, p, b)
				end
			end
		end
		-- 点菜单外（含按钮本身）→ 收起
		if rel and not (rel.x >= bx and rel.x < bx + mw and rel.y >= my and rel.y < my + mh) then
			close()
		end
		return
	end

	-- dialog / bottom_sheet
	local title = rv(o.title)
	local text = rv(o.text)
	local items = rv(o.items)
	local buttons = rv(o.buttons) or {}
	local pad = 20
	local cw = math.min(p.w - 24, o.w or 320)
	local ch = pad + (title and (lh + 10) or 0) + (text and (lh + 4) or 0)
		+ (items and (#items * (lh + 12) + 8) or 0)
		+ (#buttons > 0 and (lh + 26) or 0) + pad
	local cx, cy
	if k == "bottom_sheet" then
		cx, cy = (p.w - cw) / 2, p.h - ch
		cw = p.w - 16
		cx = 8
	else
		cx, cy = (p.w - cw) / 2, (p.h - ch) / 2
	end
	local r = k == "bottom_sheet" and 16 or 24
	p:rrect(cx + 2, cy + 3, cw, ch, r, T.surface_hover) -- 拟阴影
	p:rrect(cx, cy, cw, ch, r, T.surface_hi)

	local ty = cy + pad
	if title then
		p:text(cx + pad, ty, title, T.on_surface)
		ty = ty + lh + 10
	end
	if text then
		p:text(cx + pad, ty, text, T.hint)
		ty = ty + lh + 4
	end
	if items then
		ty = ty + 8
		for i, it in ipairs(items) do
			local iy = ty
			local hover = ui:hover(cx + 8, iy, cw - 16, lh + 12)
			if hover then
				p:rrect(cx + 8, iy, cw - 16, lh + 12, 8, T.surface_hover)
			end
			local s = tostring(it)
			p:text(cx + pad, iy + 6, s, T.on_surface)
			local hit = rel and rel.x >= cx + 8 and rel.x < cx + cw - 8
				and rel.y >= iy and rel.y < iy + lh + 12
			if hit then
				close()
				if o.on_select then
					o.on_select(it, i, p, b)
				end
			end
			ty = iy + lh + 12
		end
		ty = ty + 8
	end
	if #buttons > 0 then
		local byy = cy + ch - pad - (lh + 16)
		local bw2 = math.floor((cw - pad * 2 - (#buttons - 1) * 8) / #buttons)
		for i, btn in ipairs(buttons) do
			local label = type(btn) == "table" and (btn.label or tostring(i)) or tostring(btn)
			local bxx = cx + pad + (i - 1) * (bw2 + 8)
			local clicked = ui:id_button("ui2dlg:" .. tostring(node._id) .. ":" .. i,
				bxx, byy, bw2, lh + 16, label,
				{ filled = type(btn) == "table" and btn.filled, tonal = type(btn) == "table" and btn.tonal })
			if clicked then
				close()
				if type(btn) == "table" and btn.action then
					btn.action(p, b)
				end
			end
		end
	end
	-- 点卡片外（scrim 区）→ 关闭
	if rel and not (rel.x >= cx and rel.x < cx + cw and rel.y >= cy and rel.y < cy + ch) then
		close()
	end
end

-- 颜色工具：hsv→rgb / 线性混色（color_picker 用）
hsv_rgb = function(h, s, v)
	h = (h % 360) / 60
	local i = math.floor(h)
	local f = h - i
	local p1 = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	local r, g, bl
	if i == 0 then
		r, g, bl = v, t, p1
	elseif i == 1 then
		r, g, bl = q, v, p1
	elseif i == 2 then
		r, g, bl = p1, v, t
	elseif i == 3 then
		r, g, bl = p1, q, v
	elseif i == 4 then
		r, g, bl = t, p1, v
	else
		r, g, bl = v, p1, q
	end
	return math.floor(r * 255) * 0x10000 + math.floor(g * 255) * 0x100 + math.floor(bl * 255)
end

blend = function(c1, c2, t)
	local r1, g1, b1 = math.floor(c1 / 0x10000) % 0x100, math.floor(c1 / 0x100) % 0x100, c1 % 0x100
	local r2, g2, b2 = math.floor(c2 / 0x10000) % 0x100, math.floor(c2 / 0x100) % 0x100, c2 % 0x100
	return math.floor((r1 + (r2 - r1) * t)) * 0x10000
		+ math.floor((g1 + (g2 - g1) * t)) * 0x100
		+ math.floor((b1 + (b2 - b1) * t))
end

-- ── 布局绘制（容器） ──────────────────────────────────────────────

local function draw_container(ctx, b, p, node, x, y, w, h)
	local k = node.kind
	if node.opts.visible ~= nil and not rv(node.opts.visible) then
		return
	end
	if k == "card" then
		local pad = node.opts.pad
		if pad == nil then
			pad = 12
		end
		p:rrect(x, y, w, h, node.opts.radius or 14, color(ctx, node.opts.bg) or ctx.theme.surface)
		x, y, w, h = x + pad, y + pad, w - pad * 2, h - pad * 2
	elseif k == "column" or k == "row" then
		local pad = node.opts.pad
		if pad == nil then
			pad = 8
		end
		x, y, w, h = x + pad, y + pad, w - pad * 2, h - pad * 2
	end

	local gap = node.opts.gap or 8
	local align = node.opts.align or "left"
	local children = node.children
	local n = #children

	-- 默认吃满宽度的部件（行/列里均可）
	local function natural_w(ch, avail)
		if ch.opts and ch.opts.fill then
			return avail
		end
		if ch.kind == "slider" or ch.kind == "progress" or ch.kind == "text_field"
			or ch.kind == "divider" or ch.kind == "segmented" or ch.kind == "list_item"
			or ch.kind == "search_bar" or ch.kind == "tab_row" or ch.kind == "navigation_bar"
			or ch.kind == "toolbar" then
			return avail
		end
		return ch._mw
	end

	-- 子项实际高度（spacer 弹性吃掉剩余空间）
	local flex = 0
	for _, ch in ipairs(children) do
		if ch._flex then
			flex = flex + 1
		end
	end
	local flex_h = 0
	if flex > 0 then
		local content = 0
		for i, ch in ipairs(children) do
			local chh = ch._flex and flex_h or (ch._mh or 0)
			if chh > 0 or ch._flex then
				content = content + chh
				if i < n then
					content = content + gap
				end
			end
		end
		flex_h = math.max(0, (h - content) / flex)
	end

	if k == "column" or k == "card" then
		local cy = y
		for i, ch in ipairs(children) do
			local chh = ch._flex and flex_h or (ch._mh or 0)
			local chw = natural_w(ch, w)
			local cx = x
			if align == "center" then
				cx = x + math.floor((w - chw) / 2)
			end
			if ch.children then
				draw_container(ctx, b, p, ch, cx, cy, chw, chh)
			else
				draw_node(ctx, b, p, ch, cx, cy, chw)
			end
			if chh > 0 or ch._flex then
				cy = cy + chh + gap
			end
		end
	elseif k == "row" then
		local cxx = x
		for i, ch in ipairs(children) do
			local chh = ch._flex and h or (ch._mh or 0)
			local chw = ch._flex and 0 or (ch._mw or 0)
			if ch.opts and ch.opts.fill then
				chw = w
			end
			local ry = y + math.floor((h - chh) / 2)
			if ch.children then
				draw_container(ctx, b, p, ch, cxx, ry, chw, chh)
			else
				draw_node(ctx, b, p, ch, cxx, ry, chw)
			end
			if chw > 0 or ch._flex then
				cxx = cxx + chw + gap
			end
		end
	end
end

-- ── Builder ───────────────────────────────────────────────────────

local Builder = {}
Builder.__index = Builder

local next_id = 0

local function node(kind, opts)
	next_id = next_id + 1
	return { kind = kind, opts = opts or {}, children = nil, _id = next_id }
end

local function container(kind, opts)
	local n = node(kind, opts)
	n.children = {}
	return n
end

-- 当前打开的容器（栈顶）；没有则报错
function Builder:_cur()
	local c = self.stack[#self.stack]
	if not c then
		error("ui2: no open container — forgot :column(...)/:row(...)?")
	end
	return c
end

function Builder:_add(kind, opts)
	local c = self:_cur()
	local n = node(kind, opts)
	c.children[#c.children + 1] = n
	return n
end

local function _container(kind, opts)
	return function(self, o)
		local c = container(kind, o)
		local cur = self:_cur()
		cur.children[#cur.children + 1] = c
		self.stack[#self.stack + 1] = c
		return self
	end
end

Builder.column = _container("column")
Builder.row = _container("row")
Builder.card = _container("card")

-- 关闭最近打开的容器（根 builder 用；child view 上多余调用无害）
function Builder:end_()
	if #self.stack > 1 then
		self.stack[#self.stack] = nil
	end
	return self
end

-- ── 部件 ──────────────────────────────────────────────────────────

local function _text(kind, defaults)
	return function(self, opts)
		if type(opts) == "string" then
			opts = { value = opts }
		end
		opts = opts or {}
		for k, v in pairs(defaults or {}) do
			if opts[k] == nil then
				opts[k] = v
			end
		end
		self:_add(kind, opts)
		return self
	end
end

-- 语义化文本（同一字体，用颜色 / 留白区分层级）
Builder.h1 = _text("text", { color = "on_surface", pad = { 8, 4 } })
Builder.h2 = _text("text", { color = "on_surface", pad = { 6, 2 } })
Builder.h3 = _text("text", { color = "on_surface", pad = { 4, 1 } })
Builder.p = _text("text", {})
Builder.span = _text("text", {})
Builder.small = _text("text", { color = "hint" })
Builder.big = _text("text", {})
Builder.code = _text("text", { color = "on_var", bg = "surface_hi", mono = true })
Builder.div = _text("text", {})
Builder.text = _text("text", {})
Builder.hint = _text("text", { color = "hint" })

function Builder:centered_text(opts)
	if type(opts) == "string" then
		opts = { value = opts }
	end
	opts = opts or {}
	opts._center = true
	self:_add("text", opts)
	return self
end

function Builder:icon(opts)
	self:_add("icon", opts)
	return self
end

function Builder:button(opts)
	self:_add("button", opts)
	return self
end

function Builder:toggle(opts)
	self:_add("toggle", opts)
	return self
end

function Builder:slider(opts)
	self:_add("slider", opts)
	return self
end

function Builder:progress(opts)
	self:_add("progress", opts)
	return self
end

function Builder:segmented(opts)
	self:_add("segmented", opts)
	return self
end

function Builder:text_field(opts)
	self:_add("text_field", opts)
	return self
end

function Builder:divider(opts)
	self:_add("divider", opts)
	return self
end

-- ── MIUIX 风格部件 ────────────────────────────────────────────────

Builder.checkbox = function(self, opts) self:_add("checkbox", opts) return self end
Builder.radio = function(self, opts) self:_add("radio", opts) return self end
Builder.icon_button = function(self, opts) self:_add("icon_button", opts) return self end
Builder.fab = function(self, opts) self:_add("fab", opts) return self end
Builder.stepper = function(self, opts) self:_add("stepper", opts) return self end
Builder.search_bar = function(self, opts) self:_add("search_bar", opts) return self end
Builder.tab_row = function(self, opts) self:_add("tab_row", opts) return self end
Builder.navigation_bar = function(self, opts) self:_add("navigation_bar", opts) return self end
Builder.breadcrumb = function(self, opts) self:_add("breadcrumb", opts) return self end
Builder.badge = function(self, opts) self:_add("badge", opts) return self end
Builder.small_title = function(self, opts)
	if type(opts) == "string" then
		opts = { value = opts }
	end
	self:_add("small_title", opts)
	return self
end
Builder.toolbar = function(self, opts) self:_add("toolbar", opts) return self end
Builder.color_palette = function(self, opts) self:_add("color_palette", opts) return self end
Builder.list_item = function(self, opts) self:_add("list_item", opts) return self end

-- ── Miuix 补齐 ────────────────────────────────────────────────────
Builder.top_app_bar = function(self, opts) self:_add("top_app_bar", opts) return self end
Builder.navigation_rail = function(self, opts) self:_add("navigation_rail", opts) return self end
Builder.range_slider = function(self, opts) self:_add("range_slider", opts) return self end
Builder.color_picker = function(self, opts) self:_add("color_picker", opts) return self end
Builder.dropdown = function(self, opts) self:_add("dropdown", opts) return self end
-- dialog / bottom_sheet：浮层。open 传函数（响应式）或 nil（组件内自管状态）
Builder.dialog = function(self, opts) self:_add("dialog", opts) return self end
Builder.bottom_sheet = function(self, opts) self:_add("bottom_sheet", opts) return self end
-- Miuix BasicComponent：可点击的 icon+title 行（= 无右侧控件的 list_item）
Builder.basic_component = function(self, opts)
	opts = opts or {}
	opts.right = nil
	self:_add("list_item", opts)
	return self
end
-- Miuix preference 系列便捷封装：list_item + 对应控件
Builder.arrow_preference = function(self, opts)
	opts = opts or {}
	opts.right = "arrow"
	self:_add("list_item", opts)
	return self
end
Builder.switch_preference = function(self, opts)
	opts = opts or {}
	opts.right = "switch"
	self:_add("list_item", opts)
	return self
end
Builder.checkbox_preference = function(self, opts)
	opts = opts or {}
	opts.right = "checkbox"
	self:_add("list_item", opts)
	return self
end
Builder.radio_preference = function(self, opts)
	opts = opts or {}
	opts.right = "radio"
	self:_add("list_item", opts)
	return self
end

-- Snackbar：桥接 lbar 的 toast（ctx.notify）
-- ui2.snackbar(ctx, "已保存", { style = "info" })
function M.snackbar(ctx, message, opts)
	if ctx and ctx.notify then
		ctx.notify(message, opts)
	end
end

function Builder:spacer(opts)
	self:_add("spacer", opts or {})
	return self
end

function Builder:gap(opts)
	if type(opts) == "number" then
		opts = { h = opts }
	end
	self:_add("gap", opts or { h = 8 })
	return self
end

-- ── webdev 结构特性 ───────────────────────────────────────────────

-- 子视图：栈指向当前容器，fn 内部的 :row()/:text() 落到真实树，
-- fn 返回后无需拼接。focusbox 与主 builder 共享（component 内的
-- text_field 聚焦才有效）。
function Builder:_child_view()
	return setmetatable({
		ctx = self.ctx,
		keys = self.keys,
		stack = { self:_cur() },
		panel = self.panel,
		_focusbox = self._focusbox,
	}, Builder)
end

-- v-for：list 支持 table 或函数（响应式）。
-- fn(item, i, b) 里 b 是子视图，直接声明该子项内容。
function Builder:each(list, fn)
	list = rv(list)
	for i, item in ipairs(list or {}) do
		local ok, err = pcall(fn, item, i, self:_child_view())
		if not ok then
			if self.ctx.log then
				self.ctx.log("ui2 :each[%d]: %s", i, tostring(err))
			end
		end
	end
	return self
end

-- 复用组件：fn(b, opts) 把组件内容声明到当前位置。
-- function ListItem(b, opts) b:row({gap=4}):icon({glyph="*"}):p(opts.label):end_() end
-- b:component(ListItem, { label = "first" })
function Builder:component(fn, opts)
	local ok, err = pcall(fn, self:_child_view(), opts)
	if not ok then
		if self.ctx.log then
			self.ctx.log("ui2 :component: %s", tostring(err))
		end
	end
	return self
end

-- v-if / v-else（unless = not if）
function Builder:if_(cond, fn)
	if rv(cond) then
		local ok, err = pcall(fn, self:_child_view())
		if not ok then
			if self.ctx.log then
				self.ctx.log("ui2 :if_: %s", tostring(err))
			end
		end
	end
	return self
end

function Builder:unless(cond, fn)
	if not rv(cond) then
		local ok, err = pcall(fn, self:_child_view())
		if not ok then
			if self.ctx.log then
				self.ctx.log("ui2 :unless: %s", tostring(err))
			end
		end
	end
	return self
end

-- 一行绑键：on_key 散落的 if/else 链换成声明
function Builder:on_key(sym, fn)
	self.keys[#self.keys + 1] = { sym = sym, fn = fn }
	return self
end

-- ── 测量 / 渲染 / 事件 ───────────────────────────────────────────

function Builder:measure()
	local wmax, hsum = 0, 0
	local n = #self.children
	local last = 0
	for i, ch in ipairs(self.children) do
		local cw, chh = measure_node(self.ctx, ch)
		ch._mw, ch._mh = cw, chh
		if chh > 0 then
			last = last + 1
			wmax = math.max(wmax, cw)
			hsum = hsum + chh
			if last > 1 then
				hsum = hsum + 4
			end
		end
	end
	local m = { W = wmax, H = hsum }
	return m
end

function Builder:render(p)
	local ctx = self.ctx
	local W, H = p.w, p.h
	-- 浮层：收集本帧 open 的 dropdown/dialog/bottom_sheet。
	-- 吞掉本帧 pointer release：树阶段控件收不到点击（防误触），
	-- 浮层最后绘制（z 序正确）并用保存的 release 做命中。
	local overlays = {}
	local function scan(list)
		for _, ch in ipairs(list) do
			if ch.children then
				scan(ch.children)
			end
			if ch.kind == "dropdown" and ch._open then
				overlays[#overlays + 1] = ch
			elseif ch.kind == "dialog" or ch.kind == "bottom_sheet" then
				local open = rv(ch.opts.open)
				if open == nil then
					open = ch._open
				end
				if open then
					overlays[#overlays + 1] = ch
				end
			end
		end
	end
	scan(self.children)
	local ui = p.ui
	local rel
	if #overlays > 0 then
		rel = ui.mrelease
		ui.mrelease = nil
	end
	-- 头部（可选）
	local oy = 0
	if self._title then
		oy = p:draw_header(self._title, self._hint, self._header_pad)
	end
	-- 根节点逐个绘制（通常根只有一个 column）
	local cursor = oy
	for _, ch in ipairs(self.children) do
		local chh = ch._mh
		local chw
		if ch.opts and ch.opts.fill then
			chw = W
		elseif ch.kind == "column" or ch.kind == "card" or ch.kind == "row" then
			chw = W
		else
			chw = ch._mw
		end
		local cx = 0
		if ch.kind == "text" and ch.opts._center then
			cx = math.floor((W - ch._mw) / 2)
		end
		if ch.children then
			draw_container(ctx, self, p, ch, cx, cursor, chw, chh)
		else
			draw_node(ctx, self, p, ch, cx, cursor, chw)
		end
		if chh > 0 then
			cursor = cursor + chh + 4
		end
	end
	-- 浮层收尾绘制
	if #overlays > 0 then
		ui.mrelease = rel
		for _, ov in ipairs(overlays) do
			draw_overlay(ctx, self, p, ov, ui, rel)
		end
	end
	-- 文本字段失去焦点时清引用
	local box = self._focusbox
	if box.focus and not p.ui:has_focus(box.focus) then
		box.focus = nil
	end
end

function Builder:dispatch_key(sym)
	local box = self._focusbox
	-- 1. 聚焦的 text_field 吃掉可打印字符
	if box.focus and box.fields[box.focus] then
		local node = box.fields[box.focus]
		local o = node.opts
		local v = rv(o.value) or ""
		if sym == XK_BACKSPACE then
			if #v > 0 then
				v = v:sub(1, -2)
			end
			if o.on_change then
				o.on_change(v, self.panel, self)
			end
			return true
		elseif sym == XK_RETURN or sym == XK_KP_ENTER then
			if self.panel.ui then
				self.panel.ui:blur_input()
			end
			box.focus = nil
			if o.on_submit then
				o.on_submit(v, self.panel, self)
			end
			return true
		elseif sym >= 32 and sym <= 126 then
			v = v .. string.char(sym)
			if o.on_change then
				o.on_change(v, self.panel, self)
			end
			return true
		end
	end
	-- 2. Escape 默认隐藏
	if sym == XK_ESCAPE then
		self.panel:hide()
		return true
	end
	-- 3. 声明式键位
	for _, kb in ipairs(self.keys) do
		if kb.sym == sym then
			local ok, r = pcall(kb.fn, self.panel, self)
			if not ok then
				if self.ctx.log then
				self.ctx.log("ui2 on_key: %s", tostring(r))
			end
				return true
			end
			if r ~= false then
				return true
			end
		end
	end
	return false
end

-- 面板显示时重新测量（响应式数据可能变了）
function Builder:refit()
	if self.panel and not self.panel.destroyed then
		self.panel:refit()
	end
end

-- ── 入口：创建带声明树的面板 ──────────────────────────────────────

function M.panel(ctx, opts)
	Icons.configure(ctx.config)
	opts = opts or {}
	local b = setmetatable({
		ctx = ctx,
		children = {},
		stack = {},
		keys = {},
		_focusbox = { focus = nil, fields = {} },
		-- 注意：字段名不能叫 title/hint —— Builder.hint 是文本方法，
		-- nil 字段会穿透到 metatable 命中函数，draw_header 里炸 text_width
		_title = opts.title,
		_hint = opts.hint,
		_header_pad = opts.header_pad,
	}, Builder)

	local panel = Panel.new(ctx, {
		name = opts.name or "ui2",
		radius = opts.radius or 16,
		bg = opts.bg or ctx.theme.bg,
		kbd = opts.kbd ~= false,
		model_fn = function(c, us)
			local m = b:measure()
			if opts.width then
				m.W = math.max(m.W, opts.width)
			end
			if us then
				m.W = math.max(m.W, us.w)
				m.H = math.max(m.H, us.h)
			end
			return m
		end,
		size_fn = function(c)
			local m = b:measure()
			if opts.width then
				m.W = math.max(m.W, opts.width)
			end
			return m.W, m.H
		end,
		draw = function(p)
			-- render 中途 state 变更（on_click/on_change 写 state → visible
			-- 翻转）会让过期布局炸掉（未 measure 的子树 / nil 宽度）：
			-- 错误与 dirty 同时出现 = 过期帧，丢弃重画；第二轮（新 state）
			-- 仍失败才是真实 bug，抛给 Panel:draw 上报
			for attempt = 1, 2 do
				p._ui2_dirty = nil
				b:measure()
				local ok, err = pcall(b.render, b, p)
				if not ok then
					if not (attempt == 1 and p._ui2_dirty) then
						error(err, 0)
					end
				elseif not p._ui2_dirty then
					break
				end
			end
			p._ui2_dirty = nil
		end,
		on_key = function(p, sym)
			return b:dispatch_key(sym)
		end,
		on_show = opts.on_show,
		on_hide = opts.on_hide,
	})
	if not panel then
		return nil
	end
	b.panel = panel

	-- 根容器：栈为空时，第一个 :column/:row/:card 落到 b.children。
	-- 栈底压入一个虚拟根（children 直接指向 b.children）。
	b.stack[1] = { kind = "root", opts = {}, children = b.children }
	return b
end

return M
