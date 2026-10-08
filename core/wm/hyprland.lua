-- core/wm/hyprland.lua
local M = {}
M.name = "hyprland"

function M.detect()
	return os.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil
end

function M.register_binds(ctx, config, cli, log)
	local function eval(code)
		local quoted = code:gsub("'", "'\\''")
		local p = io.popen("hyprctl eval '" .. quoted .. "' 2>&1", "r")
		if not p then
			return nil
		end
		local out = p:read("*a") or ""
		p:close()
		return out:find("^ok") ~= nil, out
	end

	local n = 0
	for _, kb in ipairs(config or {}) do
		local parts = {}
		for m in (kb.mod or ""):gmatch("[^+%s]+") do
			parts[#parts + 1] = m:upper()
		end
		parts[#parts + 1] = #kb.key == 1 and kb.key:upper() or kb.key
		local keys = table.concat(parts, " + ")
		local ok = eval(string.format(
			'pcall(function() hl.unbind("%s") end) hl.bind("%s", hl.dsp.exec_cmd("%s %s"))',
			keys, keys, cli, kb.action))
		local via = "eval"
		if not ok then
			via = "keyword"
			os.execute(string.format("hyprctl keyword unbind '%s,%s' >/dev/null 2>&1",
				table.concat(parts, " "), kb.key))
			ok = os.execute(string.format(
				"hyprctl keyword bind '%s,%s,exec,%s %s' >/dev/null 2>&1",
				table.concat(parts, " "), kb.key, cli, kb.action))
		end
		if ok then
			n = n + 1
		else
			log("hyprland bind failed (%s): %s -> %s", via, keys, tostring(kb.action))
		end
	end
	return n
end

return M
