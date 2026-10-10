-- plugins/hello.lua — ui2 演示插件（webdev 风格）
--
-- 展示 ui2 声明式框架的全部核心特性：
--   响应式 state / :each 列表渲染 / :component 复用 / :if_ 条件 /
--   语义化文本 (h1/p/code/hint) / :on_key 一行绑键
--
-- 测试：luajit plugin_container.lua hello
-- 面板内 Esc 关闭；点 bar 上的 "todo" 项 toggle 面板。

local M = {}
local ui2 = require("core.ui2")
local Util = require("core.util")
local log = Util.logger("hello")

local XK_ESCAPE = 0xff1b

local ctx
local state
local panel

-- ── 复用组件：一行 todo ───────────────────────────────────────────

local function TodoRow(b, opts)
	local todo = opts.todo
	b:row({ pad = 0, gap = 8 })
		:toggle({
			value = function() return todo.done end,
			on_change = function(v)
				todo.done = v
				state.dirty = true
			end,
		})
		:p({
			value = function() return todo.done and todo.text .. " ✓" or todo.text end,
			color = function() return todo.done and "hint" or "on_surface" end,
		})
		:button({
			label = "×",
			tonal = true,
			action = function()
				for i, t in ipairs(state.todos) do
					if t == todo then
						table.remove(state.todos, i)
						break
					end
				end
			end,
		})
	:end_()
end

-- ── 初始化 ────────────────────────────────────────────────────────

function M.init(c)
	ctx = c
	state = ui2.state({
		todos = {
			{ text = "read ui2 source", done = true },
			{ text = "write a plugin", done = false },
			{ text = "hot reload it", done = false },
		},
		input = "",
		dirty = false,
	})

	local b = ui2.panel(ctx, {
		name = "hello",
		title = "ui2 · todo",
		hint = Util.keybind_hint(ctx, "toggle_hello"),
	})

	b:column({ pad = 20, gap = 12 })
		:h1("ui2 demo")
		:p({ value = "declarative · reactive · zero layout math", color = "hint" })
		:card({ pad = 12, gap = 6 })
			:each(function() return state.todos end, function(todo, _)
				b:component(TodoRow, { todo = todo })
			end)
			:if_(function() return #state.todos == 0 end, function(bb)
				bb:p({ value = "no tasks — add one below", color = "hint" })
			end)
		:end_()
		:row({ gap = 8 })
			:text_field({
				value = function() return state.input end,
				placeholder = "new task…",
				on_change = function(v) state.input = v end,
				on_submit = function(v)
					if v ~= "" then
						state.todos[#state.todos + 1] = { text = v, done = false }
						state.input = ""
					end
				end,
			})
			:button({
				label = "Add",
				action = function()
					if state.input ~= "" then
						state.todos[#state.todos + 1] = { text = state.input, done = false }
						state.input = ""
					end
				end,
			})
		:end_()
		:divider({})
		:p({
			value = function()
				local done = 0
				for _, t in ipairs(state.todos) do
					if t.done then
						done = done + 1
					end
				end
				return done .. " / " .. #state.todos .. " done · edit & save to hot reload"
			end,
			color = "hint",
		})
	:on_key(XK_ESCAPE, function(p) p:hide() end)

	-- 响应式：state 写入 → 面板自动重绘 + bar 请求重绘
	ui2.reactive(state, b, ctx)

	panel = b.panel
	panel.b = b
	ctx.register_panel("hello", panel)
	log("ready (ui2 demo)")
end

-- ── bar item ──────────────────────────────────────────────────────

function M.width(ctx)
	return ctx.text_width("todo") + 24
end

function M.draw(ctx, s, x, y, w, h)
	local T = ctx.theme
	local lh = ctx.get_line_height()
	local active = ctx.active_plugin_name == "hello" and ctx.popup_visible
	local fg = active and T.primary or T.on_surface
	s:text(x + 12, math.floor((h - lh) / 2), "todo", fg)
end

function M.on_click(ctx, btn, lx, ly, gx, gw)
	if btn == 1 then
		Util.toggle_from_bar(ctx, "hello", gx, gw)
	end
end

return M
