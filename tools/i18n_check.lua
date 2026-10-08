-- tools/i18n_check.lua — generic i18n coverage check: verifies every
-- literal I.t("...") key used in plugins/ and core/ has an entry in the
-- core/i18n.lua zh table (en falls back to the key itself, so only zh
-- coverage needs checking). Dynamic keys (I.t(var)) can't be resolved
-- statically — cover those by review.
-- usage: luajit tools/i18n_check.lua   (exit 1 on missing keys)
local here = arg[0]:match("^(.*)/tools/") or "."
local I = dofile(here .. "/core/i18n.lua")
local zh = I._tables.zh

local function read(p)
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function list(dir)
	local items = {}
	local p = io.popen(string.format("ls -1 %s 2>/dev/null", dir))
	if p then
		for l in p:lines() do
			items[#items + 1] = dir .. "/" .. l
		end
		p:close()
	end
	return items
end

local missing, total, dupwarn = {}, 0, {}
local seen = {}
local files = {}
for _, f in ipairs(list(here .. "/plugins")) do
	files[#files + 1] = f
end
for _, f in ipairs(list(here .. "/core")) do
	files[#files + 1] = f
end

for _, f in ipairs(files) do
	if f:match("%.lua$") then
		local src = read(f)
		if src then
			for key in src:gmatch('I%.t%(%s*"(.-)"') do
				total = total + 1
				if zh[key] == nil then
					missing[#missing + 1] = string.format("%s: %s", f:sub(#here + 2), key)
				end
				if seen[key] and seen[key] ~= f then
					dupwarn[#dupwarn + 1] = key .. "  (" .. seen[key] .. " + " .. f:sub(#here + 2) .. ")"
				end
				seen[key] = f:sub(#here + 2)
			end
		end
	end
end

print(string.format("i18n check: %d literal I.t keys scanned, %d missing zh", total, #missing))
for _, m in ipairs(missing) do
	print("  MISSING " .. m)
end
os.exit(#missing == 0 and 0 or 1)
