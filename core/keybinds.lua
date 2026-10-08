-- core/keybinds.lua
local M = {}
local bit = require("bit")

local LOCK_BITS = bit.bor(0x2, 0x10)
local LOCK_VARIANTS = { 0, 0x2, 0x10, LOCK_BITS }

local MOD_NAMES = {
	shift = 0x1,
	lock = 0x2,
	caps = 0x2,
	ctrl = 0x4,
	control = 0x4,
	alt = 0x8,
	mod1 = 0x8,
	mod2 = 0x10,
	num = 0x10,
	mod3 = 0x20,
	super = 0x40,
	mod4 = 0x40,
	win = 0x40,
	cmd = 0x40,
	meta = 0x40,
	mod5 = 0x80,
}

function M.parse_mods(s)
	if type(s) ~= "string" then
		return nil
	end
	local mask = 0
	for part in s:gmatch("[^+]+") do
		local m = MOD_NAMES[part:match("^%s*(.-)%s*$"):lower()]
		if not m then
			return nil
		end
		mask = bit.bor(mask, m)
	end
	return mask == 0 and nil or mask
end

function M.new(ctx)
	local L, log = ctx.L, ctx.log
	local by_code = {}
	local self = {}

	function self.register_wm_binds(config)
		local cli = (ctx.lbar_dir or ".") .. "/lbar-cli"
		local wms = { "core.wm.hyprland", "core.wm.sway", "core.wm.niri" }
		for _, wmname in ipairs(wms) do
			local wm = require(wmname)
			if wm.detect() then
				local n = wm.register_binds(ctx, config, cli, log)
				if n > 0 then
					log("registered %d %s keybinds", n, wm.name)
				end
				return
			end
		end
		log("no compositor binds on %s (bind wm keys to: %s <action>)",
			tostring(ctx.backend_kind), cli)
	end

	function self.build(config)
		for k in pairs(by_code) do
			by_code[k] = nil
		end
		L.lbar_key_ungrab_all(ctx.Lctx)
		if ctx.backend_kind ~= "x11" then
			self.register_wm_binds(config)
			return
		end
		for _, kb in ipairs(config or {}) do
			local mask = M.parse_mods(kb.mod)
			if not mask then
				log("keybind unknown modifier: %s", tostring(kb.mod))
			else
				local code = L.lbar_key_code(ctx.Lctx, kb.key)
				if not code or code == 0 then
					log("keybind unknown key: %s", tostring(kb.key))
				else
					local list = by_code[code]
					if not list then
						list = {}
						by_code[code] = list
					end
					local replaced = false
					for i, entry in ipairs(list) do
						if entry.mask == mask then
							log("keybind conflict: key=%s mods=%s (%s -> %s)", tostring(kb.key), tostring(kb.mod), tostring(entry.action), tostring(kb.action))
							list[i].action = kb.action
							replaced = true
							break
						end
					end
					if not replaced then
						list[#list + 1] = { mask = mask, action = kb.action }
					end
					L.lbar_key_grab(ctx.Lctx, code, mask)
				end
			end
		end
	end

	function self.lookup(keycode, state)
		local list = by_code[keycode]
		if not list then
			return nil
		end
		local clean = bit.band(state, bit.bnot(LOCK_BITS))
		for _, entry in ipairs(list) do
			if clean == entry.mask then
				return entry.action
			end
		end
		return nil
	end

	return self
end

return M
