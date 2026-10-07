local M = {}
local Util = require("core.util")

local log = Util.logger("hide_all")

function M.init(ctx)
	M.ctx = ctx
	ctx.actions["hide_all_panels"] = function()
		M.hide_all()
	end
	ctx.actions["hide_all_windows"] = function()
		M.hide_all()
	end
	log("ready")
end

function M.hide_all()
	local ctx = M.ctx
	if not ctx then
		return
	end
	local count = 0
	for _, p in pairs(ctx._panels or {}) do
		if p.visible then
			p:hide()
			count = count + 1
		end
	end
	if count > 0 then
		ctx.notify(string.format("closed %d panel(s)", count), { style = "info" })
	else
		ctx.notify("no open panels", { style = "plain" })
	end
end

function M.shutdown()
	M.ctx = nil
end

return M
