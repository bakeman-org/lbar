-- core/wm/sway.lua
local M = {}
M.name = "sway"

function M.detect()
	return os.getenv("SWAYSOCK") ~= nil
end

function M.register_binds(ctx, config, cli, log)
	local n = 0
	for _, kb in ipairs(config or {}) do
		local mods = kb.mod or ""
		local ok = os.execute(string.format(
			"swaymsg bindsym '%s+%s' exec '%s %s' >/dev/null 2>&1",
			mods, kb.key, cli, kb.action))
		if ok then
			n = n + 1
		else
			log("sway bind failed: %s+%s -> %s", mods, tostring(kb.key), tostring(kb.action))
		end
	end
	return n
end

return M
