local M = {}
local Util = require("core.util")
local log = Util.logger("plugins")

local function load_one(ctx, bar, name)
	local ok, mod = pcall(require, "plugins." .. name)
	if not (ok and type(mod) == "table") then
		log("load %s failed: %s", name, tostring(mod))
		return
	end
	bar:add_plugin(name, mod)
end

function M.load_all(ctx, bar, names)
	for _, name in ipairs(names or {}) do
		load_one(ctx, bar, name)
	end
end

function M.watch(ctx, bar, paths, mtimes)
	local changed = false
	for _, p in ipairs(paths) do
		local mt = Util.file_mtime(p)
		if mt and mtimes[p] and mtimes[p] ~= mt then
			log("changed: %s", p)
			changed = true
		end
		mtimes[p] = mt
	end
	return changed
end

function M.snapshot_mtimes(paths)
	local mt = {}
	for _, p in ipairs(paths) do
		mt[p] = Util.file_mtime(p)
	end
	return mt
end

return M
