-- core/screenshot.lua — full-screen capture for UI debugging (x11 + wayland)
local M = {}
local ffi = require("ffi")

local function shell_ok(rc)
	return rc == true or rc == 0
end

local function ensure_dir(path)
	local dir = path:match("^(.*/)[^/]+$")
	if dir and dir ~= "" then
		os.execute("mkdir -p '" .. dir .. "' 2>/dev/null")
	end
end

local function timestamp()
	return os.date("%Y%m%d_%H%M%S")
end

local function save_dir(ctx)
	local home = os.getenv("HOME") or "/tmp"
	return (ctx.config and ctx.config.debug_shot_dir) or (home .. "/Pictures/lbar")
end

local function write_bmp(path, buf, w, h)
	local row = w * 3
	local pad = (4 - (row % 4)) % 4
	local stride = row + pad
	local f = io.open(path, "wb")
	if not f then
		return false
	end
	local u16 = function(v)
		return string.char(v % 256, math.floor(v / 256) % 256)
	end
	local u32 = function(v)
		return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256,
			math.floor(v / 16777216) % 256)
	end
	f:write("BM", u32(54 + stride * h), u16(0), u16(0), u32(54))
	f:write(u32(40), u32(w), u32(h), u16(1), u16(24), u32(0), u32(stride * h), u32(0), u32(0), u32(0), u32(0))
	local rowbuf = ffi.new("unsigned char[?]", stride)
	for y = h - 1, 0, -1 do
		local src = y * w * 3
		for x = 0, w - 1 do
			local si = src + x * 3
			local di = x * 3
			rowbuf[di] = buf[si + 2]
			rowbuf[di + 1] = buf[si + 1]
			rowbuf[di + 2] = buf[si]
		end
		f:write(ffi.string(rowbuf, stride))
	end
	f:close()
	return true
end

local function clip_copy(path)
	if os.getenv("WAYLAND_DISPLAY") then
		if shell_ok(os.execute("command -v wl-copy >/dev/null 2>&1")) then
			os.execute("wl-copy --type image/png < '" .. path .. "' 2>/dev/null")
		end
		return
	end
	if shell_ok(os.execute("command -v xclip >/dev/null 2>&1")
		and os.execute("command -v convert >/dev/null 2>&1")) then
		local png = "/tmp/lbar_clip_" .. os.time() .. ".png"
		if shell_ok(os.execute("convert '" .. path .. "' '" .. png .. "'")) then
			os.execute("xclip -selection clipboard -t image/png -i '" .. png .. "' 2>/dev/null")
		end
		os.execute("rm -f '" .. png .. "' 2>/dev/null")
	end
end

function M.capture(ctx, tag)
	local dir = save_dir(ctx)
	ensure_dir(dir)
	tag = (tag or "screen"):gsub("[^%w_-]", "_")
	local path
	if ctx.backend_kind == "x11" then
		local w, h = ctx.scr_w, ctx.scr_h
		local buf = ffi.new("unsigned char[?]", w * h * 3)
		local rc = ctx.L.lbar_x_get_region(ctx.Lctx, 0, 0, w, h, buf, w * h * 3)
		if rc ~= 0 then
			return nil, "x11 root capture failed"
		end
		path = string.format("%s/lbar_%s_%s.bmp", dir, tag, timestamp())
		if not write_bmp(path, buf, w, h) then
			return nil, "write failed: " .. path
		end
	else
		path = string.format("%s/lbar_%s_%s.png", dir, tag, timestamp())
		local cmd = string.format("grim -g '0,0 %dx%d' '%s' 2>/dev/null", ctx.scr_w, ctx.scr_h, path)
		if not shell_ok(os.execute(cmd)) then
			return nil, "grim failed (wayland needs grim)"
		end
	end
	clip_copy(path)
	return path
end

return M
