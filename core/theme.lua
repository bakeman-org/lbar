-- core/theme.lua — builtin palettes + md3 token map
local M = {}

local function pal(t, dark)
	t.dark = dark
	return t
end

M.palettes = {
	md3_dark = pal({
		bg = 0x141218,
		surface = 0x1d1b20,
		surface_hi = 0x2b2930,
		surface_hover = 0x3b383e,
		primary = 0xd0bcff,
		primary_hi = 0xe3d5ff,
		on_primary = 0x381e72,
		secondary_ctr = 0x4a4458,
		tertiary_ctr = 0x633b48,
		on_surface = 0xe6e1e5,
		on_var = 0xcac4d0,
		outline = 0x49454f,
		outline_var = 0xcac4d0,
		good = 0xb5ccb5,
		warn = 0xf5e1a4,
		crit = 0xf2b8b5,
		hint = 0xcac4d0,
	}, true),

	md3_light = pal({
		bg = 0xfdf8fd,
		surface = 0xf7f2fa,
		surface_hi = 0xf1ecf4,
		surface_hover = 0xe6e0e9,
		primary = 0x6750a4,
		primary_hi = 0x8d78c2,
		on_primary = 0xffffff,
		secondary_ctr = 0xe8def8,
		tertiary_ctr = 0xffd8e4,
		on_surface = 0x1d1b20,
		on_var = 0x49454f,
		outline = 0x79747e,
		outline_var = 0xcac4d0,
		good = 0x386a20,
		warn = 0x7c5800,
		crit = 0xb3261e,
		hint = 0x49454f,
	}, false),

	one_dark = pal({
		bg = 0x282c34,
		surface = 0x21252b,
		surface_hi = 0x2c313a,
		surface_hover = 0x333842,
		primary = 0x61afef,
		primary_hi = 0x8fc6f4,
		on_primary = 0xffffff,
		secondary_ctr = 0x2f353d,
		tertiary_ctr = 0x3e4451,
		on_surface = 0xabb2bf,
		on_var = 0x9da5b4,
		outline = 0x5c6370,
		outline_var = 0x3e4451,
		good = 0x98c379,
		warn = 0xe5c07b,
		crit = 0xe06c75,
		hint = 0x9da5b4,
	}, true),

	one_light = pal({
		bg = 0xfafafa,
		surface = 0xffffff,
		surface_hi = 0xf0f0f0,
		surface_hover = 0xe2e2e2,
		primary = 0x4078f2,
		primary_hi = 0x7ba4f5,
		on_primary = 0xffffff,
		secondary_ctr = 0xe8eaf0,
		tertiary_ctr = 0xf2dfe4,
		on_surface = 0x383a42,
		on_var = 0x4f5665,
		outline = 0xc8cdd4,
		outline_var = 0xe6e6e6,
		good = 0x50a14f,
		warn = 0xc18401,
		crit = 0xe45649,
		hint = 0x4f5665,
	}, false),

	gruvbox_dark = pal({
		bg = 0x282828,
		surface = 0x32302f,
		surface_hi = 0x3c3836,
		surface_hover = 0x504945,
		primary = 0xfabd2f,
		primary_hi = 0xffe08a,
		on_primary = 0x32302f,
		secondary_ctr = 0x504945,
		tertiary_ctr = 0x684c56,
		on_surface = 0xebdbb2,
		on_var = 0xd5c4a1,
		outline = 0x665c54,
		outline_var = 0xbdae93,
		good = 0xb8bb26,
		warn = 0xfe8019,
		crit = 0xfb4934,
		hint = 0xd5c4a1,
	}, true),

	gruvbox_light = pal({
		bg = 0xfbf1c7,
		surface = 0xf2e5bc,
		surface_hi = 0xebdbb2,
		surface_hover = 0xd5c4a1,
		primary = 0x076678,
		primary_hi = 0x458588,
		on_primary = 0xfbf1c7,
		secondary_ctr = 0xe4d9b1,
		tertiary_ctr = 0xe8ddb5,
		on_surface = 0x3c3836,
		on_var = 0x665c54,
		outline = 0xbdae93,
		outline_var = 0xebdbb2,
		good = 0x79740e,
		warn = 0xb57614,
		crit = 0x9d0006,
		hint = 0x665c54,
	}, false),

	nord = pal({
		bg = 0x2e3440,
		surface = 0x3b4252,
		surface_hi = 0x434c5e,
		surface_hover = 0x4c566a,
		primary = 0x88c0d0,
		primary_hi = 0xa9d3dd,
		on_primary = 0x2e3440,
		secondary_ctr = 0x434c5e,
		tertiary_ctr = 0x443e5c,
		on_surface = 0xeceff4,
		on_var = 0xd8dee9,
		outline = 0x4c566a,
		outline_var = 0xd8dee9,
		good = 0xa3be8c,
		warn = 0xebcb8b,
		crit = 0xbf616a,
		hint = 0xd8dee9,
	}, true),

	catppuccin_mocha = pal({
		bg = 0x1e1e2e,
		surface = 0x181825,
		surface_hi = 0x313244,
		surface_hover = 0x45475a,
		primary = 0xcba3f7,
		primary_hi = 0xd7b3ff,
		on_primary = 0x1e1e2e,
		secondary_ctr = 0x45475a,
		tertiary_ctr = 0x585b70,
		on_surface = 0xcdd6f4,
		on_var = 0xbac2de,
		outline = 0x6c7086,
		outline_var = 0x9399b2,
		good = 0xa6e3a1,
		warn = 0xf9e2af,
		crit = 0xf38ba8,
		hint = 0xbac2de,
	}, true),

	catppuccin_latte = pal({
		bg = 0xeff1f5,
		surface = 0xe6e9ef,
		surface_hi = 0xccd0da,
		surface_hover = 0xbcc0cc,
		primary = 0x8839ef,
		primary_hi = 0xb081f2,
		on_primary = 0xeff1f5,
		secondary_ctr = 0xdce0e8,
		tertiary_ctr = 0xdcdcf2,
		on_surface = 0x4c4f69,
		on_var = 0x6c6f85,
		outline = 0x9ca0b0,
		outline_var = 0xccd0da,
		good = 0x40a02b,
		warn = 0xdf8e1d,
		crit = 0xd20f39,
		hint = 0x6c6f85,
	}, false),

	tokyo_night = pal({
		bg = 0x1a1b26,
		surface = 0x16161e,
		surface_hi = 0x24283b,
		surface_hover = 0x2f334d,
		primary = 0x7aa2f7,
		primary_hi = 0x9ab8ff,
		on_primary = 0x1a1b26,
		secondary_ctr = 0x292e42,
		tertiary_ctr = 0x3b4261,
		on_surface = 0xc0caf5,
		on_var = 0xa9b1d6,
		outline = 0x414868,
		outline_var = 0x9aa5ce,
		good = 0x9ece6a,
		warn = 0xe0af68,
		crit = 0xf7768e,
		hint = 0xa9b1d6,
	}, true),

	tokyo_night_day = pal({
		bg = 0xe1e2e7,
		surface = 0xd6d9e0,
		surface_hi = 0xc4c8da,
		surface_hover = 0xb6bacc,
		primary = 0x2e7de9,
		primary_hi = 0x5f9cf0,
		on_primary = 0xffffff,
		secondary_ctr = 0xcfd4ea,
		tertiary_ctr = 0xdfd3ec,
		on_surface = 0x3760bf,
		on_var = 0x6172b0,
		outline = 0xa8aec2,
		outline_var = 0xc4c8da,
		good = 0x387068,
		warn = 0xb15c00,
		crit = 0xf52a65,
		hint = 0x6172b0,
	}, false),

	solarized_dark = pal({
		bg = 0x002b36,
		surface = 0x073642,
		surface_hi = 0x0d4453,
		surface_hover = 0x14505f,
		primary = 0x268bd2,
		primary_hi = 0x5fa5d8,
		on_primary = 0xfdf6e3,
		secondary_ctr = 0x114a59,
		tertiary_ctr = 0x3f2f46,
		on_surface = 0xeee8d5,
		on_var = 0x93a1a1,
		outline = 0x586e75,
		outline_var = 0x657b83,
		good = 0x859900,
		warn = 0xb58900,
		crit = 0xdc322f,
		hint = 0x93a1a1,
	}, true),

	solarized_light = pal({
		bg = 0xfdf6e3,
		surface = 0xeee8d5,
		surface_hi = 0xe4ddc8,
		surface_hover = 0xdad3bd,
		primary = 0x268bd2,
		primary_hi = 0x6cb0dd,
		on_primary = 0xffffff,
		secondary_ctr = 0xe3dbbf,
		tertiary_ctr = 0xf0dce0,
		on_surface = 0x073642,
		on_var = 0x586e75,
		outline = 0x93a1a1,
		outline_var = 0xeee8d5,
		good = 0x859900,
		warn = 0xb58900,
		crit = 0xdc322f,
		hint = 0x586e75,
	}, false),
}

M.md3 = {
	bg = 0x141218,
	surface = 0x1d1b20,
	surface_hi = 0x2b2930,
	surface_hover = 0x3b383e,
	primary = 0xd0bcff,
	primary_hi = 0xe3d5ff,
	on_primary = 0x381e72,
	secondary_ctr = 0x4a4458,
	tertiary_ctr = 0x633b48,
	on_surface = 0xe6e1e5,
	on_var = 0xcac4d0,
	outline = 0x49454f,
	outline_var = 0xcac4d0,
	hint = 0xcac4d0,
}

M.legacy_map = {
	fg = "on_surface",
	dim = "on_var",
	accent = "primary",
	accent_hi = "primary_hi",
	bar_bg = "surface",
}

function M.build(cfg)
	cfg = cfg or {}
	local light = cfg.theme_mode == "light"
	local name = light and (cfg.theme_light or "md3_light") or (cfg.theme or "md3_dark")
	if not M.palettes[name] then
		name = light and "md3_light" or "md3_dark"
	end
	local pal = M.palettes[name]
	local t = { name = name, dark = pal.dark }
	for k, v in pairs(pal) do
		t[k] = v
	end
	for k, v in pairs(cfg) do
		if M.md3[k] ~= nil and type(v) == "number" then
			t[k] = v
		end
	end
	for legacy, md3 in pairs(M.legacy_map) do
		t[legacy] = t[md3]
	end
	for k, v in pairs(t) do
		if type(v) == "number" and v ~= 0 and v < 0xFF000000 then
			t[k] = v + 0xFF000000
		end
	end
	return t
end

return M
