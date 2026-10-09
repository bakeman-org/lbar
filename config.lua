return {
    position = 'top',
    height   = 'auto',
    -- height   = 1002,
    padding  = 16,
    gap      = 2,
    bar_margin = 8,

    -- builtin themes: md3_dark md3_light one_dark one_light gruvbox_dark gruvbox_light
    -- nord catppuccin_mocha catppuccin_latte tokyo_night tokyo_night_day
    -- solarized_dark solarized_light
    theme       = 'nord',
    theme_light = 'one_light',
    theme_mode  = 'dark',

    -- corner style: 'round' (rounded buttons/cards/windows) | 'square'
    corner     = 'round',

    -- UI language: 'auto' (detect from $LANG) | 'en' | 'zh'
    lang = 'zh',

    font_path = '/home/etcix/.local/share/fonts/FantasqueSansMNerdFontMono-Regular.ttf',
    font_size = 18,
    fallback_font_paths = {
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    },

    audio_panel_dir = '/home/etcix/Music',

    -- music player state file (volume + last played track)
    music_state_file = os.getenv('HOME') .. '/.local/state/lbar/music.conf',

    plugins = {
        'logo', 'workspace', 'cpu', 'mem', 'battery', 'volume', 'clock',
        'keybinds_help', 'launcher', 'clip_hist', 'pomodoro',
        'music_player', 'weather', 'sysinfo', 'sysmon',
        'color_picker', 'ui_demo', 'hide_all',
        'settings', 'wallpaper', 'wifi',
    },

    -- cpu/mem bar items are compact text labels colored by load
    cpu = {
        interval_ms = 1000,
        color = true,          -- color by load (good/warn/crit)
    },
    mem = {
        interval_ms = 2000,
        color = true,
    },

    wifi = {
        interface = 'auto',    -- or e.g. 'wlan0'
        refresh_sec = 8,
    },

    wallpaper = {
        dir = '~/Pictures',    -- string or list of dirs
        depth = 3,             -- find maxdepth
        -- set_cmd = 'swww img "$f"',  -- force a custom setter ($f = file path)
    },

    battery = {
        lock_cmd = 'swaylock -f',
        -- logout_cmd = 'niri msg action quit',  -- auto: niri/hyprland/sway
        confirm = true,        -- ask before logout/sleep/reboot/poweroff
        -- items = { 'lock', 'logout', 'sleep', 'reboot', 'poweroff' },
    },

    -- popup window animations (PPT-style enter/exit slides).
    -- style: 'auto' (pick from the panel's anchor/position) | 'slide_up' |
    --        'slide_down' | 'slide_left' | 'slide_right' | 'none'
    -- per-panel override: config.panels.<name>.anim wins over animation.style
    animation = {
        enabled     = true,
        style       = 'auto',
        duration_ms = 150,   -- enter/exit travel time
        distance    = 40,    -- slide distance in px
        exit        = true,  -- animate the exit too
    },

    -- per-panel scope: dismiss_outside = false keeps the panel open when
    -- clicking outside it (outside clicks pass through to other apps)
    panel_opts = {
        launcher = { dismiss_outside = true },
        sysmon = { dismiss_outside = true },
        music_player = { dismiss_outside = true },
        color_picker = { dismiss_outside = true },
        sysinfo = { dismiss_outside = true },
        settings = { dismiss_outside = false },
        wallpaper = { dismiss_outside = true },
        wifi = { dismiss_outside = false },
        battery = { dismiss_outside = true },
        volume = { dismiss_outside = true },
    },

    -- same keybinds as xpet
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

    panels = {
        -- per-panel entrance position: center/top/bottom/left/right/
        -- top_left/top_right/bottom_left/bottom_right, or 'auto' to anchor
        -- below the bar item; overlapping panels cascade automatically
        clock          = { pos = 'top', anim = 'auto' },
        volume         = { pos = 'bottom_right', anim = 'auto' },
        launcher       = { pos = 'top', anim = 'slide_down' },
        clip_hist      = { pos = 'top', anim = 'auto' },
        pomodoro       = { pos = 'bottom_right', anim = 'auto' },
        music_player   = { pos = 'center', anim = 'auto' },
        weather        = { pos = 'top_right', anim = 'auto' },
        sysinfo        = { pos = 'bottom_left', anim = 'auto' },
        sysmon         = { pos = 'center', anim = 'auto' },
        color_picker   = { pos = 'right', anim = 'auto' },
        ui_demo        = { pos = 'center', anim = 'auto' },
        keybinds_help  = { pos = 'left', anim = 'auto' },
        settings       = { pos = 'center', anim = 'auto' },
        wallpaper      = { pos = 'center', anim = 'auto' },
        wifi           = { pos = 'top_right', anim = 'auto' },
        battery        = { pos = 'top_right', anim = 'auto' },
    },

    pomodoro = {
        work_min = 15,
        break_min = 5,
    },

    clip_hist = {
        max_items = 30,
    },

    clock = {
        -- schedule / alarms file, one entry per line: 'YYYY-MM-DD HH:MM text'
        schedule_file = os.getenv('HOME') .. '/.local/state/lbar/schedule.conf',
    },

    launcher = {
        use_dmenu_path = true,
        -- custom your own entries
        -- entries = {
        --     { name = 'terminal', cmd = 'alacritty' },
        --     { name = 'files', cmd = 'pcmanfm' },
        --     { name = 'browser', cmd = 'firefox' },
        --     { name = 'editor', cmd = 'code' },
        --     { name = 'sysmon', cmd = 'alacritty -e btop' },
        -- },
    },

    weather = {
        units = 'c',
        refresh_sec = 900,
    },

    -- ui_demo 'windows' tab: window move/resize steps (px per click)
    move_window = {
        step = 30,
        mode = 'auto_float',
    },

    resize_window = {
        step = 50,
    },
    power = { confirm = true },
}
