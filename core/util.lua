local M = {}

function M.logger(tag)
	return function(fmt, ...)
		io.stderr:write("[" .. tag .. "] " .. string.format(fmt, ...) .. "\n")
	end
end

function M.file_exists(p)
	local f = io.open(p, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

-- file mtime with nanosecond precision, read via the statx(2) syscall.
-- The old io.popen("stat …") spawned one shell + one stat per watched path
-- (config + every plugin ≈ 22 processes) on each 800ms watcher cycle, and
-- blocked the main loop until each child exited — a periodic stall that
-- showed up as jank/latency on X11. statx is a single syscall, no fork.
local statx_ok, statx
do
	local ffi = require("ffi")
	local bit = require("bit")
	local ok = pcall(ffi.cdef, [[
		typedef struct { int64_t tv_sec; uint32_t tv_nsec; int32_t __reserved; } lbar_statx_ts;
		typedef struct {
			uint32_t stx_mask;
			uint32_t stx_blksize;
			uint64_t stx_attributes;
			uint32_t stx_nlink;
			uint32_t stx_uid;
			uint32_t stx_gid;
			uint16_t stx_mode;
			uint16_t lbar_spare0;
			uint64_t stx_ino;
			uint64_t stx_size;
			uint64_t stx_blocks;
			uint64_t stx_attributes_mask;
			lbar_statx_ts stx_atime;
			lbar_statx_ts stx_btime;
			lbar_statx_ts stx_ctime;
			lbar_statx_ts stx_mtime;
			uint32_t stx_rdev_major;
			uint32_t stx_rdev_minor;
			uint32_t stx_dev_major;
			uint32_t stx_dev_minor;
			uint64_t stx_mnt_id;
			uint32_t stx_dio_mem_align;
			uint32_t stx_dio_offset_align;
			uint64_t lbar_spare[12];
		} lbar_statx_t;
		int statx(int dirfd, const char *pathname, int flags, unsigned int mask, void *statxbuf);
	]])
	if ok then
		local libc = ffi.C
		local buf = ffi.new("lbar_statx_t[1]")
		local AT_FDCWD = -100
		local STATX_MTIME = 0x800
		statx = function(path)
			buf[0].stx_mask = 0
			if libc.statx(AT_FDCWD, path, 0, STATX_MTIME, buf) ~= 0 then
				return nil
			end
			if bit.band(buf[0].stx_mask, STATX_MTIME) == 0 then
				return nil
			end
			local m = buf[0].stx_mtime
			return tonumber(m.tv_sec) + tonumber(m.tv_nsec) * 1e-9
		end
		local probe = statx("/proc/self/exe")
		if not probe then
			statx = nil
		end
		statx_ok = statx ~= nil
	else
		statx_ok = false
	end
end

function M.file_mtime(path)
	-- nanosecond mtime: second granularity silently misses a write that
	-- lands in the same second as the previously recorded mtime (the value
	-- then never changes again, so the watcher never fires)
	if statx_ok then
		local v = statx(path)
		if v then
			return v
		end
	end
	local p = io.popen(string.format("stat -c %%.9Y '%s' 2>/dev/null", path))
	if not p then
		return nil
	end
	local out = p:read("*l")
	p:close()
	return tonumber(out)
end

function M.utf8_step(s, i)
	local b = s:byte(i)
	if not b then
		return 1
	end
	if b < 0x80 then
		return 1
	end
	if b < 0xE0 then
		return 2
	end
	if b < 0xF0 then
		return 3
	end
	return 4
end

function M.utf8_prev(s, i)
	if i <= 1 then
		return 1
	end
	local j = i - 1
	while j > 1 do
		local b = s:byte(j)
		if b and b >= 0x80 and b < 0xC0 then
			j = j - 1
		else
			break
		end
	end
	return j
end

function M.utf8_next(s, i)
	local n = #s
	if i > n then
		return n + 1
	end
	return math.min(i + M.utf8_step(s, i), n + 1)
end

function M.utf8_truncate(s, max_chars)
	local i = 1
	local L = #s
	local n = 0
	while i <= L do
		if n >= max_chars then
			local cut = i
			while cut > 1 do
				local b = s:byte(cut)
				if b and b >= 0x80 and b < 0xC0 then
					cut = cut - 1
				else
					break
				end
			end
			return s:sub(1, cut - 1) .. "…"
		end
		i = i + M.utf8_step(s, i)
		n = n + 1
	end
	return s
end

function M.truncate(s, max)
	if #s <= max then
		return s
	end
	local cut = max - 1
	while cut > 0 do
		local b = s:byte(cut + 1)
		if not b or b < 0x80 or b >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return s:sub(1, cut) .. "…"
end

function M.keybind_hint(ctx, action)
	for _, kb in ipairs(ctx.config.keybinds or {}) do
		if kb.action == action then
			local parts = {}
			for p in kb.mod:gmatch("[^+]+") do
				parts[#parts + 1] = p:sub(1, 1):upper() .. p:sub(2):lower()
			end
			parts[#parts + 1] = kb.key:upper()
			return table.concat(parts, "+")
		end
	end
	return "?"
end

-- global corner style: config.corner == "square" flattens every rounded
-- rect (controls, pills, cards, bar and popup windows) to sharp corners
function M.corner_r(ctx, r)
	if ctx and ctx.config and ctx.config.corner == "square" then
		return 0
	end
	return r
end

function M.toggle_from_bar(ctx, name, gx, gw, align)
	-- an explicit panels.<name>.pos wins over bar anchoring: the panel
	-- opens at its configured entrance position ('auto' = anchor to bar)
	local pcfg = ctx.config.panels and ctx.config.panels[name] or nil
	if pcfg and pcfg.pos and pcfg.pos ~= "auto" then
		ctx.show_panel(name)
		return
	end
	local dir = (ctx.config.position == "bottom") and "above" or "below"
	local ay = (ctx.config.position == "top") and ctx.bar.h or (ctx.scr_h - ctx.bar.h)
	local ax = (align == "left") and gx or (gx + gw / 2)
	ctx.show_panel(name, ax, ay, dir, align)
end

return M
