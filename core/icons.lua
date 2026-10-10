-- core/icons.lua — ui2 图标解析（Nerd Font 优先，ASCII 兜底）
--
-- 解决"图标显示为豆腐块"：Nerd Font 的图标字形都在私有区
-- （PUA U+F000-F2FF），Unicode 标准区的 ⚙ ✦ ⤢ 等符号主字体没有、
-- CJK fallback 也常缺。ui2 部件的 icon/glyph 参数直接给图标名，
-- 这里按当前字体能力解析成可绘制的字符串。
--
-- 用法：
--   local icons = require("core.icons")
--   b:icon_button({ icon = "gear" })          -- ui2 部件自动走 icons
--   s:text(x, y, icons.glyph("wifi"), fg)     -- bar item 直接用
--
-- 模式自动检测：config.font_path / fallback_font_paths 含 "nerd"
-- （不区分大小写）→ nerd 模式；否则 ascii 模式。也可手动覆盖：
--   icons.mode("nerd" | "ascii")
-- 图标名不认识时返回 "?",不会画出豆腐块。

local M = {
	_mode = nil, -- nil = 未检测，惰性初始化
}

-- ── 图标集：name = { nf = PUA codepoint, ascii = 兜底字符 } ──────
local ICONS = {
	-- 动作
	plus = { nf = 0xf067, ascii = "+" },
	minus = { nf = 0xf068, ascii = "-" },
	close = { nf = 0xf00d, ascii = "x" },
	check = { nf = 0xf00c, ascii = "v" },
	gear = { nf = 0xf013, ascii = "*" },
	settings = { nf = 0xf013, ascii = "*" },
	search = { nf = 0xf002, ascii = "?" },
	trash = { nf = 0xf1f8, ascii = "x" },
	edit = { nf = 0xf040, ascii = "~" },
	refresh = { nf = 0xf021, ascii = "@" },
	sync = { nf = 0xf021, ascii = "@" },
	save = { nf = 0xf0c7, ascii = "=" },
	play = { nf = 0xf04b, ascii = ">" },
	pause = { nf = 0xf04c, ascii = "||" },
	stop = { nf = 0xf04d, ascii = "[]" },
	next = { nf = 0xf051, ascii = ">>" },
	prev = { nf = 0xf048, ascii = "<<" },
	power = { nf = 0xf011, ascii = "0" },

	-- 导航
	home = { nf = 0xf015, ascii = "^" },
	list = { nf = 0xf0c9, ascii = "=" },
	grid = { nf = 0xf00a, ascii = "#" },
	apps = { nf = 0xf009, ascii = "#" },
	chevron_right = { nf = 0xf054, ascii = ">" },
	chevron_left = { nf = 0xf053, ascii = "<" },
	chevron_up = { nf = 0xf077, ascii = "^" },
	chevron_down = { nf = 0xf078, ascii = "v" },
	arrow_up = { nf = 0xf062, ascii = "^" },
	arrow_down = { nf = 0xf063, ascii = "v" },
	arrow_left = { nf = 0xf060, ascii = "<" },
	arrow_right = { nf = 0xf061, ascii = ">" },
	expand = { nf = 0xf065, ascii = "+" },
	shrink = { nf = 0xf066, ascii = "-" },

	-- 状态 / 设备
	wifi = { nf = 0xf1eb, ascii = "((( " },
	star = { nf = 0xf005, ascii = "*" },
	heart = { nf = 0xf004, ascii = "<" },
	bell = { nf = 0xf0f3, ascii = "i" },
	moon = { nf = 0xf186, ascii = "C" },
	zap = { nf = 0xf0e7, ascii = "/" },
	battery = { nf = 0xf240, ascii = "=" },
	bluetooth = { nf = 0xf293, ascii = "@" },
	volume = { nf = 0xf028, ascii = ")" },
	camera = { nf = 0xf030, ascii = "o" },
	clock = { nf = 0xf017, ascii = "0" },
	calendar = { nf = 0xf073, ascii = "#" },
	folder = { nf = 0xf07b, ascii = "[] " },
	file = { nf = 0xf15b, ascii = "[]" },
	user = { nf = 0xf007, ascii = "@" },
	info = { nf = 0xf05a, ascii = "i" },
	question = { nf = 0xf059, ascii = "?" },
	warning = { nf = 0xf071, ascii = "!" },
	circle = { nf = 0xf111, ascii = "o" },
	square = { nf = 0xf0c8, ascii = "[]" },
	cube = { nf = 0xf1b2, ascii = "[]" },
	cog = { nf = 0xf013, ascii = "*" },
	tools = { nf = 0xf0ad, ascii = "*" },
	music = { nf = 0xf001, ascii = "~" },
	globe = { nf = 0xf0ac, ascii = "@" },
	cloud = { nf = 0xf0c2, ascii = "@" },
	link = { nf = 0xf0c1, ascii = "@" },
	lock = { nf = 0xf023, ascii = "#" },
	keyboard = { nf = 0xf11c, ascii = "[]" },
	display = { nf = 0xf108, ascii = "[]" },
}

-- codepoint → UTF-8（3 字节，PUA 全在 U+E000-U+FFFF）
local bit = require("bit")
local function cp_utf8(cp)
	return string.char(
		bit.bor(0xE0, bit.rshift(cp, 12)),
		bit.bor(0x80, bit.band(bit.rshift(cp, 6), 0x3F)),
		bit.bor(0x80, bit.band(cp, 0x3F)))
end

function M.mode(m)
	if m == "nerd" or m == "ascii" then
		M._mode = m
	end
	return M._mode
end

-- 惰性检测：优先用 ui2 注入的 config，否则读项目根 config.lua
local _injected_cfg = nil
function M.configure(config)
	_injected_cfg = config
	M._mode = nil -- 重新检测
end

local function detect()
	if M._mode then
		return
	end
	local cfg = _injected_cfg
	if not cfg then
		local ok, c = pcall(dofile, (function()
			-- 从本文件位置推断项目根 config.lua
			local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/core/")
			return (here or ".") .. "/config.lua"
		end)())
		if ok then
			cfg = c
		end
	end
	local nerd = false
	if cfg then
		local paths = { tostring(cfg.font_path or "") }
		for _, f in ipairs(cfg.fallback_font_paths or {}) do
			paths[#paths + 1] = tostring(f)
		end
		for _, p in ipairs(paths) do
			if p:lower():find("nerd") then
				nerd = true
				break
			end
		end
	end
	M._mode = nerd and "nerd" or "ascii"
end

-- 名字 → 可绘制字符串；unknown 兜底 "?"；原始字符（含 UTF-8）原样返回
function M.glyph(name)
	if not name or name == "" then
		return ""
	end
	detect()
	local ic = ICONS[name]
	if not ic then
		-- 不是已知图标名：可能是调用方直接传的字符（× › 等），原样给
		if #name > 0 and not name:match("^[%w_]+$") then
			return name
		end
		return "?"
	end
	if M._mode == "nerd" then
		return cp_utf8(ic.nf)
	end
	return ic.ascii
end

-- 图标是否存在
function M.has(name)
	return ICONS[name] ~= nil
end

-- 全部图标名（画廊/文档用）
function M.names()
	local t = {}
	for k in pairs(ICONS) do
		t[#t + 1] = k
	end
	table.sort(t)
	return t
end

return M
