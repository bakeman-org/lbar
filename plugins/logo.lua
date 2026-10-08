local M = {}
local Util = require("core.util")

local log = Util.logger("logo")

local TUX = {
	"...bbbbb...",
	"..bbbbbbb..",
	"..bwbbwbb..",
	"..bwbbwbb..",
	".bbwwwwwbb.",
	".bbwwoowbb.",
	".bbwwwwwbb.",
	".bwwwwwwwb.",
	"bwwwwwwwwwb",
	"bwwwwwwwwwb",
	".bwwwwwwb..",
	"..oo...oo..",
}

local COL_B = 0x1a1a1a
local COL_W = 0xf5f5f5
local COL_O = 0xf2a33c

local TUX_COLS = 11
local TUX_ROWS = 12

local function draw_tux(s, x, y, px)
	for ry = 1, TUX_ROWS do
		local row = TUX[ry]
		for rx = 1, TUX_COLS do
			local ch = row:sub(rx, rx)
			local c
			if ch == "b" then
				c = COL_B
			elseif ch == "w" then
				c = COL_W
			elseif ch == "o" then
				c = COL_O
			end
			if c then
				s:rect(x + (rx - 1) * px, y + (ry - 1) * px, px, px, c)
			end
		end
	end
end

local function tux_px(h)
	return math.max(2, math.min(4, math.floor((h - 14) / TUX_ROWS)))
end

function M.width(ctx)
	local px = tux_px((ctx.bar and ctx.bar.h) or 40)
	return TUX_COLS * px + 20
end

function M.draw(ctx, s, x, y, w, h)
	local px = tux_px(h)
	draw_tux(s, x + math.floor((w - TUX_COLS * px) / 2),
		math.floor((h - TUX_ROWS * px) / 2), px)
end

function M.on_click(ctx, btn)
	if btn == 1 and ctx.actions.toggle_theme then
		ctx.actions.toggle_theme()
	end
end

function M.init(ctx)
	log("ready")
end

function M.shutdown() end

return M
