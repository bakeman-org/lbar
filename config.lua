return {
    position = 'top',
    height   = 'auto',
    -- height   = 1002,
    padding  = 16,
    gap      = 10,
    bar_margin = 8,

    -- builtin themes: md3_dark md3_light one_dark one_light gruvbox_dark gruvbox_light
    -- nord catppuccin_mocha catppuccin_latte tokyo_night tokyo_night_day
    -- solarized_dark solarized_light
    theme       = 'one_dark',
    theme_light = 'one_light',

    font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    font_size = 24,
    fallback_font_paths = {
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    },

    audio_panel_dir = '/home/etcix/Music',

    -- music player state file (volume + last played track)
    music_state_file = os.getenv('HOME') .. '/.local/state/lbar/music.conf',

    plugins = {
        'menu', 'cpu', 'mem', 'battery', 'clock', 'system',
        'keybinds_help', 'launcher', 'clip_hist', 'pomodoro',
        'music_player', 'weather', 'sysinfo', 'sysmon',
        'color_picker', 'ui_demo', 'hide_all',
        'move_window', 'resize_window',
    },

    -- per-panel scope: dismiss_outside = false keeps the panel open when
    -- clicking outside it (outside clicks pass through to other apps)
    panel_opts = {
        launcher = { dismiss_outside = false },
        sysmon = { dismiss_outside = false },
        music_player = { dismiss_outside = false },
        color_picker = { dismiss_outside = false },

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
        { mod = 'ctrl+alt', key = 'y', action = 'toggle_system',
          group = 'panels', desc = 'system panel' },
        { mod = 'ctrl+alt', key = 'k', action = 'toggle_theme',
          group = 'system', desc = 'toggle dark / light theme' },
        { mod = 'ctrl+alt+shift', key = 's', action = 'debug_dump_panel',
          group = 'system', desc = 'dump visible panel screenshot to /tmp' },

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
        clock          = { pos = 'center', anim = 'auto' },
        system         = { pos = 'center', anim = 'auto' },
        launcher       = { pos = 'top', anim = 'slide_down' },
        clip_hist      = { pos = 'center', anim = 'auto' },
        pomodoro       = { pos = 'bottom_right', anim = 'auto' },
        music_player   = { pos = 'center', anim = 'auto' },
        weather        = { pos = 'top_right', anim = 'auto' },
        sysinfo        = { pos = 'center', anim = 'auto' },
        sysmon         = { pos = 'center', anim = 'auto' },
        color_picker   = { pos = 'center', anim = 'auto' },
        ui_demo        = { pos = 'center', anim = 'auto' },
        keybinds_help  = { pos = 'center', anim = 'auto' },
    },

    pomodoro = {
        work_min = 25,
        break_min = 5,
    },

    clip_hist = {
        max_items = 30,
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

    move_window = {
        step = 30,
        mode = 'auto_float',
    },

    resize_window = {
        step = 30,
    },
}
