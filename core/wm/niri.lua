-- core/wm/niri.lua
local M = {}
M.name = "niri"

function M.detect()
	return os.getenv("NIRI_SOCKET") ~= nil
end

function M.register_binds(ctx, config, cli, log)
	local lines = { "binds {" }
	for _, kb in ipairs(config or {}) do
		local parts = {}
		for m in (kb.mod or ""):gmatch("[^+%s]+") do
			parts[#parts + 1] = m:sub(1, 1):upper() .. m:sub(2):lower()
		end
		parts[#parts + 1] = #kb.key == 1 and kb.key:upper() or kb.key
		lines[#lines + 1] = string.format('    %s { spawn "%s" "%s"; }',
			table.concat(parts, "+"), cli, kb.action)
	end
	lines[#lines + 1] = "}"
	log("niri: paste into config.kdl yourself (lbar never writes external configs):\n%s",
		table.concat(lines, "\n"))
	return 0
end

return M
