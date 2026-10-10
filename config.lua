-- lbar 全局配置（热重载生效：ctrl+alt+r 手动重载；改动此文件后默认 800ms 内自动重载）
return {
    -- ── 栏（bar）──
    position = 'top',      -- 栏位置：'top' | 'bottom'
    height   = 'auto',     -- 'auto' 按字体行高自适应，或指定像素值
    -- height   = 1002,
    padding  = 16,         -- 栏两端内边距（px）
    gap      = 2,          -- bar item 之间的基础间距（px，溢出时自动压缩）
    bar_margin = 8,        -- 栏与屏幕边缘的距离（px，>0 时栏为圆角胶囊）

    -- ── 主题 ──
    -- 内置深色主题：md3_dark one_dark gruvbox_dark nord
    -- catppuccin_mocha tokyo_night solarized_dark
    -- 内置浅色主题：md3_light one_light gruvbox_light catppuccin_latte
    -- tokyo_night_day solarized_light
    theme       = 'nord',       -- 深色模式使用的主题
    theme_light = 'one_light',  -- 浅色模式使用的主题
    theme_mode  = 'dark',       -- 'dark' | 'light'（logo 图标/设置面板可切换并写回）

    -- 圆角风格：'round' 圆角（按钮/卡片/窗口统一圆角）| 'square' 直角
    corner     = 'round',

    -- 界面语言：'auto'（根据 $LANG 自动检测）| 'en' | 'zh'
    lang = 'zh',

    -- ── 字体 ──
    -- font_path 支持以 ~ 开头；fallback_font_paths 为回退字体（如中文 CJK）
    font_path = '/home/etcix/.local/share/fonts/FantasqueSansMNerdFontMono-Regular.ttf',
    font_size = 18,
    fallback_font_paths = {
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    },

    -- 音乐面板的初始浏览目录
    audio_panel_dir = '/home/etcix/Music',

    -- 音乐播放器状态文件（音量 + 最后播放曲目）
    music_state_file = os.getenv('HOME') .. '/.local/state/lbar/music.conf',

    -- ── bar item 与插件 ──
    -- 列表顺序即栏内从左到右的排列顺序；托盘类（wifi/音量/电池+电源菜单/时钟）
    -- 放在右端，符合常见桌面Shell布局
    plugins = {
        'logo', 'workspace', 'cpu', 'mem',
        'launcher', 'keybinds_help', 'clip_hist', 'pomodoro',
        'music_player', 'weather', 'sysinfo', 'sysmon',
        'color_picker', 'ui_demo', 'hide_all', 'settings', 'wallpaper',
        'wifi', 'volume', 'battery', 'tray', 'clock',
    },

    -- 系统托盘（XEmbed 协议：X11 应用 / Wine / Java / 旧版 Qt、GTK）
    -- 依赖 XWayland；原生 SNI（DBus StatusNotifierItem）应用暂不支持
    tray = {
        enabled   = true,      -- 是否启用托盘
        icon_size = 20,        -- 图标尺寸（px，会自动限制为不超过栏高）
        gap       = 6,         -- 图标间距（px）
    },

    -- cpu/mem bar item 采样与配色
    cpu = {
        interval_ms = 1000,    -- 采样间隔（ms）
        color = true,          -- 按负载着色（good/warn/crit）
    },
    mem = {
        interval_ms = 2000,    -- 采样间隔（ms）
        color = true,
    },

    -- wifi（依赖 nmcli）
    wifi = {
        interface = 'auto',    -- 网卡名，'auto' 自动选择，或如 'wlan0'
        refresh_sec = 8,       -- bar item 刷新间隔（秒）
    },

    -- 壁纸选择器
    wallpaper = {
        dir = '~/Pictures',    -- 扫描目录：字符串或目录列表
        depth = 3,             -- find maxdepth 扫描深度
        -- set_cmd = 'swww img "$f"',  -- 强制自定义设置命令（$f 为图片路径占位符）；
                                      -- 缺省时自动探测 swww/swaybg/hyprpaper/feh 等
    },

    -- 电池 bar item + 电源菜单（锁屏/注销/睡眠/重启/关机）
    battery = {
        lock_cmd = 'swaylock -f',               -- 锁屏命令
        -- logout_cmd = 'niri msg action quit', -- 注销命令，缺省按会话自动选择
        confirm = true,        -- 注销/睡眠/重启/关机前弹确认对话框
        -- items = { 'lock', 'logout', 'sleep', 'reboot', 'poweroff' }, -- 菜单项定制
    },

    -- ── 面板动画（入场/出场滑动）──
    -- style: 'auto'（按面板锚点/位置自动选择）| 'slide_up' | 'slide_down' |
    --        'slide_left' | 'slide_right' | 'none'
    -- 单个面板可覆盖：config.panels.<name>.anim 优先于 animation.style
    animation = {
        enabled     = true,
        style       = 'auto',
        duration_ms = 150,     -- 入场/出场动画时长（ms）
        distance    = 40,      -- 滑动距离（px）
        exit        = true,    -- 出场是否播放动画
    },

    -- ── 面板行为 ──
    -- dismiss_outside = false：点击面板外部不关闭（点击会穿透到其他应用）；
    -- true：点击外部即关闭面板
    panel_opts = {
        launcher = { dismiss_outside = true },
        sysmon = { dismiss_outside = true },
        music_player = { dismiss_outside = true },
        color_picker = { dismiss_outside = true },
        sysinfo = { dismiss_outside = true },
        settings = { dismiss_outside = false },
        wallpaper = { dismiss_outside = true },
        wifi = { dismiss_outside = false },
        battery = { dismiss_outside = false },
        volume = { dismiss_outside = true },
        clip_hist = { dismiss_outside = false },
    },

    -- ── 全局快捷键（与 xpet 相同风格）──
    -- mod: 修饰键组合；key: 键名；group: 设置面板里的分组；desc: 描述
    -- Wayland 下通过 IPC + 合成器绑定实现（X11 为 XGrabKey）
    keybinds = {
        { mod = 'ctrl+alt', key = 'h', action = 'toggle_keybinds_help',
          group = 'panels', desc = 'keybind help (this panel)' },
        { mod = 'ctrl+alt', key = 'e', action = 'toggle_launcher',
          group = 'panels', desc = 'app launcher' },
        { mod = 'ctrl+alt', key = 'v', action = 'toggle_clip_hist',
          group = 'panels', desc = 'clipboard history' },
        { mod = 'ctrl+alt', key = 'c', action = 'toggle_color_picker',
          group = 'panels', desc = 'screen color picker' },
        { mod = 'ctrl+alt', key = 'b', action = 'toggle_pomodoro',
          group = 'panels', desc = 'pomodoro timer' },
        { mod = 'ctrl+alt', key = 'm', action = 'toggle_music_player',
          group = 'panels', desc = 'music player' },
        { mod = 'ctrl+alt', key = 'w', action = 'toggle_weather',
          group = 'panels', desc = 'weather panel' },
        { mod = 'ctrl+alt', key = 'i', action = 'toggle_sysinfo',
          group = 'panels', desc = 'system info' },
        { mod = 'ctrl+alt', key = 't', action = 'toggle_sysmon',
          group = 'panels', desc = 'system monitor' },
        { mod = 'ctrl+alt', key = 'u', action = 'toggle_ui_demo',
          group = 'panels', desc = 'ui component demo' },
        { mod = 'ctrl+alt', key = 'g', action = 'toggle_clock',
          group = 'panels', desc = 'clock panel' },
        { mod = 'ctrl+alt', key = 's', action = 'toggle_volume',
          group = 'panels', desc = 'volume panel' },
        { mod = 'ctrl+alt', key = 'j', action = 'toggle_settings',
          group = 'panels', desc = 'settings panel' },
        { mod = 'ctrl+alt', key = 'p', action = 'toggle_wallpaper',
          group = 'panels', desc = 'wallpaper picker' },
        { mod = 'ctrl+alt', key = 'n', action = 'toggle_wifi',
          group = 'panels', desc = 'wifi networks' },
        { mod = 'ctrl+alt', key = 'o', action = 'toggle_battery',
          group = 'panels', desc = 'battery + power menu' },
        { mod = 'ctrl+alt', key = 'k', action = 'toggle_theme',
          group = 'system', desc = 'toggle dark / light theme' },
        { mod = 'ctrl+alt+shift', key = 's', action = 'debug_dump_panel',
          group = 'system', desc = 'dump visible panel screenshot to /tmp' },
        { mod = 'ctrl+alt+shift', key = 'd', action = 'toggle_debug_mode',
          group = 'system', desc = 'debug mode: toasts stay on screen' },
        { mod = 'ctrl+alt+shift', key = 'x', action = 'debug_screenshot',
          group = 'system', desc = 'full screen shot (panel/toast tagged) to ~/Pictures/lbar' },

        { mod = 'ctrl+alt', key = 'd', action = 'hide_all_windows',
          group = 'windows', desc = 'hide / restore all panels' },
        { mod = 'ctrl+alt', key = 'Left', action = 'move_win_left',
          group = 'windows', desc = 'move window left' },
        { mod = 'ctrl+alt', key = 'Right', action = 'move_win_right',
          group = 'windows', desc = 'move window right' },
        { mod = 'ctrl+alt', key = 'Up', action = 'move_win_up',
          group = 'windows', desc = 'move window up' },
        { mod = 'ctrl+alt', key = 'Down', action = 'move_win_down',
          group = 'windows', desc = 'move window down' },
        { mod = 'ctrl+alt+shift', key = 'Right', action = 'resize_win_wider',
          group = 'windows', desc = 'window wider' },
        { mod = 'ctrl+alt+shift', key = 'Left', action = 'resize_win_narrower',
          group = 'windows', desc = 'window narrower' },
        { mod = 'ctrl+alt+shift', key = 'Down', action = 'resize_win_taller',
          group = 'windows', desc = 'window taller' },
        { mod = 'ctrl+alt+shift', key = 'Up', action = 'resize_win_shorter',
          group = 'windows', desc = 'window shorter' },
        { mod = 'ctrl+alt+shift', key = '0', action = 'reset_active_window',
          group = 'windows', desc = 'reset panel size and position' },

        { mod = 'ctrl+alt', key = 'r', action = 'hot_reload',
          group = 'system', desc = 'hot reload config and plugins' },
        { mod = 'ctrl+alt+shift', key = 'a', action = 'toggle_auto_reload',
          group = 'system', desc = 'toggle auto reload' },
        { mod = 'ctrl+alt', key = 'q', action = 'quit',
          group = 'system', desc = 'quit lbar' },
    },

    -- ── 每个面板的默认位置与动画 ──
    -- pos: center/top/bottom/left/right/top_left/top_right/bottom_left/
    --      bottom_right，或 'auto' 锚定到对应 bar item 下方；
    --      拖拽过的面板记住位置（user_pos 优先级最高），重叠面板自动错开
    -- anim: 'auto'（按 pos/锚点推导）| 'slide_up' | 'slide_down' |
    --       'slide_left' | 'slide_right' | 'none'；
    --       默认配置已覆盖全部 6 种取值（见 docs/config.md）
    panels = {
        clock          = { pos = 'top', anim = 'auto' },
        volume         = { pos = 'bottom_right', anim = 'slide_up' },
        launcher       = { pos = 'top', anim = 'slide_down' },
        clip_hist      = { pos = 'top', anim = 'auto' },
        pomodoro       = { pos = 'bottom_right', anim = 'auto' },
        music_player   = { pos = 'center', anim = 'auto' },
        weather        = { pos = 'top_right', anim = 'auto' },
        sysinfo        = { pos = 'bottom_left', anim = 'auto' },
        sysmon         = { pos = 'center', anim = 'auto' },
        color_picker   = { pos = 'right', anim = 'slide_left' },
        ui_demo        = { pos = 'center', anim = 'none' },
        keybinds_help  = { pos = 'left', anim = 'slide_right' },
        settings       = { pos = 'center', anim = 'auto' },
        wallpaper      = { pos = 'center', anim = 'auto' },
        wifi           = { pos = 'top_right', anim = 'auto' },
        battery        = { pos = 'top_right', anim = 'auto' },
    },

    -- 番茄钟：工作/休息时长（分钟）
    pomodoro = {
        work_min = 15,
        break_min = 5,
    },

    -- 剪贴板历史：最大条数
    clip_hist = {
        max_items = 30,
    },

    -- 时钟面板：日程/闹钟文件，一行一条：'YYYY-MM-DD HH:MM 文本'
    clock = {
        schedule_file = os.getenv('HOME') .. '/.local/state/lbar/schedule.conf',
    },

    -- 应用启动器
    launcher = {
        use_dmenu_path = true,  -- true 时合并 $PATH 下所有可执行文件
        -- entries = {          -- 自定义启动项
        --     { name = 'terminal', cmd = 'alacritty' },
        --     { name = 'files', cmd = 'pcmanfm' },
        --     { name = 'browser', cmd = 'firefox' },
        --     { name = 'editor', cmd = 'code' },
        --     { name = 'sysmon', cmd = 'alacritty -e btop' },
        -- },
    },

    -- 天气面板
    weather = {
        units = 'c',            -- 'c' 摄氏 | 'f' 华氏
        refresh_sec = 900,      -- 刷新间隔（秒）
    },

    -- ui_demo 'windows' 标签页：窗口移动/缩放步长（px/次）
    move_window = {
        step = 30,
        mode = 'auto_float',
    },

    resize_window = {
        step = 50,
    },

    -- 电源菜单确认（battery 插件兼容读取）
    power = { confirm = true },
}
