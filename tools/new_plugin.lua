-- tools/new_plugin.lua — ui2 插件脚手架
--
-- 用法：luajit tools/new_plugin.lua <name>
--   生成 plugins/<name>.lua（ui2 声明式骨架：bar item + 面板 + state + 热重载注释）
--   然后直接容器测试：luajit plugin_container.lua <name>
--
-- 生成后打开面板：点 bar 上生成的 <name> item。

local name = arg and arg[1]
if not name or name == "" or not name:match("^[%w_]+$") then
	io.stderr:write("usage: luajit tools/new_plugin.lua <name>\n")
	io.stderr:write("  name: 字母数字下划线，如 todo2、netstat\n")
	os.exit(1)
end

local path = arg[0]:match("^(.*)/[^/]+$") or "."
local out = path .. "/../plugins/" .. name .. ".lua"

local fh = io.open(out, "r")
if fh then
	fh:close()
	io.stderr:write("error: plugins/" .. name .. ".lua already exists\n")
	os.exit(1)
end

local TEMPLATE = [==[
-- plugins/<NAME>.lua — ui2 插件骨架（tools/new_plugin.lua 生成）
--
-- 开发循环：
--   1. luajit plugin_container.lua <NAME>    # 容器里跑起来（先退出真 bar / 旧容器）
--   2. 点 bar 上的 "<NAME>" item 打开面板
--   3. 编辑本文件并保存 → 自动热重载，立即看到改动
--
-- ui2 速查：
--   容器   :column :row :card :end_()          pad/gap 自动，spacer 吃剩余
--   文本   :h1 :h2 :h3 :p :span :small :code :hint（字符串或 {value=..}）
--   部件   :button :toggle :slider :progress :segmented :text_field :divider
--   结构   :each(list, fn)  :component(fn, opts)  :if_(cond, fn)  :unless(cond, fn)
--   响应式 ui2.state{..} → 值用 function() return .. end 包裹，set 即重绘
--   键位   :on_key(sym, fn)

local M = {}
local ui2 = require("core.ui2")
local Util = require("core.util")
local log = Util.logger("<NAME>")

local XK_ESCAPE = 0xff1b

local ctx
local state
local panel

function M.init(c)
	ctx = c
	state = ui2.state({
		count = 0,
	})

	local b = ui2.panel(ctx, {
		name = "<NAME>",
		title = "<NAME>",
		hint = Util.keybind_hint(ctx, "toggle_<NAME>"),
	})

	b:column({ pad = 20, gap = 12 })
		:h1("<NAME>")
		:p({ value = "ui2 skeleton — edit me", color = "hint" })
		:card({ pad = 12, gap = 8 })
			:p({
				value = function() return "count: " .. state.count end,
			})
			:progress({
				pct = function() return math.min(100, state.count * 10) end,
			})
		:end_()
		:row({ gap = 8 })
			:button({
				label = "+1",
				action = function() state.count = state.count + 1 end,
			})
			:button({
				label = "reset",
				tonal = true,
				action = function() state.count = 0 end,
			})
		:end_()
	:on_key(XK_ESCAPE, function(p) p:hide() end)

	ui2.reactive(state, b, ctx)

	panel = b.panel
	panel.b = b
	ctx.register_panel("<NAME>", panel)
	log("ready")
end

-- ── bar item ──────────────────────────────────────────────────────

function M.width(ctx)
	return ctx.text_width("<NAME>") + 24
end

function M.draw(ctx, s, x, y, w, h)
	local T = ctx.theme
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "<NAME>" and ctx.popup_visible
	s:text(x + 12, math.floor((h - lh) / 2), "<NAME>", active and T.primary or T.on_surface)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "<NAME>", gx, gw)
	end
end

return M
]==]

fh = io.open(out, "w")
if not fh then
	io.stderr:write("error: cannot write " .. out .. "\n")
	os.exit(1)
end
fh:write((TEMPLATE:gsub("<NAME>", name)))
fh:close()

print("created: plugins/" .. name .. ".lua")
print("test it:  luajit plugin_container.lua " .. name)
print("          (bar 上点 '" .. name .. "' 打开面板；保存文件即热重载)")
