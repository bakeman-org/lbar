-- temp test plugin: exposes ctx and creates three plain panels
local Panel = require("core.panel")
local M = {}

function M.init(ctx)
	_G.TC = ctx
	for _, n in ipairs({ "A", "B", "C" }) do
		local p = Panel.new(ctx, { name = n, w = 300, h = 200, bg = ctx.theme.surface })
		if p then
			ctx.register_panel(n, p)
		end
	end
end

function M.width(ctx)
	return 20
end

function M.draw(ctx, s, x, y, w, h)
end

return M
