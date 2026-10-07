return {
    position = 'top',          -- 'top' | 'bottom'
    height   = 32,
    padding  = 12,
    gap      = 6,

    bar_bg    = 0x1c1c1e,
    bg        = 0x1c1c1e,
    surface   = 0x2c2c2e,
    fg        = 0xffffff,
    dim       = 0x98989d,
    accent    = 0x0a84ff,
    accent_hi = 0x3a9bff,
    warn      = 0xff9f0a,
    crit      = 0xff453a,
    good      = 0x30d158,

    font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    font_size = 14,
    fallback_font_paths = {
        '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    },

    plugins = { 'cpu', 'mem', 'battery', 'clock','system' },
}