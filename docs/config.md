# lbar config.lua spec

Config lives at `config.lua` next to `lbar.lua` (or pass a path as argv[1]).
It is a single Lua table: `return { ... }`. Values are read at startup and on
hot reload (every file save triggers an 800ms watcher reload; fonts re-load
only if `font_path`/`font_size`/`fallback_font_paths` changed).

The settings panel (`ctrl+alt+j`) edits almost every key below in place.

## Top-level keys

| key | type | default | description |
|---|---|---|---|
| `position` | `'top'` \| `'bottom'` | `'top'` | bar screen edge; panels anchored to bar open below/above accordingly |
| `height` | `'auto'` \| number | `'auto'` | bar height px; `'auto'` = line height + 18 |
| `padding` | number | `16` | bar inner horizontal padding |
| `gap` | number | `10` | gap between bar items (auto-compressed if items overflow) |
| `bar_margin` | number | `0` | distance from screen edge |
| `theme` | string | `'md3_dark'` | dark-mode palette name (list below) |
| `theme_light` | string | `'md3_light'` | light-mode palette name |
| `theme_mode` | `'dark'` \| `'light'` | `'dark'` | current mode; persisted by `ctrl+alt+k` and the settings panel |
| `lang` | `'auto'` \| `'en'` \| `'zh'` | `'auto'` | UI language; `'auto'` detects from `$LANG` (`zh*` → Chinese). Switchable live from the settings panel (Options → language). Every user-visible string is translated — panel titles, labels, buttons, statuses, toasts and bar item labels (bar labels stay compact in zh) |
| `font_path` | string | — | primary font (TTF/OTF), `~` allowed |
| `font_size` | number | `14` | font size px |
| `fallback_font_paths` | list of string | `{}` | fallback fonts (e.g. Noto Sans CJK for CJK glyphs) |
| `audio_panel_dir` | string | — | music player scan directory |
| `music_state_file` | string | `$XDG_STATE_HOME/lbar/music.conf` | music player volume + last track persistence |
| `debug_shot_dir` | string | `~/Pictures/lbar` | debug screenshot output dir (`ctrl+alt+shift+x`) |
| `plugins` | list of string | — | plugin load order = bar item order (left to right) |
| `keybinds` | list of table | — | see "Keybinds" below |
| `panels` | table | — | per-panel placement, see "Panels" |
| `panel_opts` | table | — | per-panel behavior, see "Panel opts" |

## Themes

14 builtin palettes — dark: `md3_dark`, `one_dark`, `gruvbox_dark`, `nord`,
`catppuccin_mocha`, `tokyo_night`, `solarized_dark`; light: `md3_light`,
`one_light`, `gruvbox_light`, `catppuccin_latte`, `tokyo_night_day`,
`solarized_light`. `ctrl+alt+k` toggles `theme_mode` and rewrites
`theme_mode` into config.lua.

## Plugins

Valid names (each one is `plugins/<name>.lua`). Plugins with a bar item are
marked; the rest are action/panel only.

| plugin | bar item | opens |
|---|---|---|
| `logo` | tux logo | app info popup (theme switch, reload, quit) |
| `workspace` | active workspace | click cycles workspace (hyprland/sway) |
| `cpu` | `cpu` + usage | sysmon panel |
| `mem` | `mem` + usage | sysmon panel |
| `battery` | `BAT NN%` / `CHG` / `LOW` | battery + power menu (hidden if no battery) |
| `volume` | `VOL N%` / `MUTE` | volume panel (hidden without pactl) |
| `clock` | time | clock panel |
| `keybinds_help` | `keys` | keybind catalog |
| `launcher` | `apps` | app launcher |
| `clip_hist` | `clip` | clipboard history |
| `pomodoro` | timer state | pomodoro panel |
| `music_player` | track state | music panel |
| `weather` | temp | weather panel |
| `sysinfo` | `info` | system info panel |
| `sysmon` | `mon` | process monitor |
| `color_picker` | `pick` | screen color picker |
| `ui_demo` | `ui` | UI component showcase |
| `settings` | `set` | settings panel |
| `wallpaper` | `wall` | wallpaper picker |
| `wifi` | ssid + signal | wifi panel |
| `hide_all` | — (action only) | `hide_all_windows` |
| `move_window` | — (action only) | window move keybinds |
| `resize_window` | — (action only) | window resize keybinds |

## Keybinds

```lua
keybinds = {
  { mod = 'ctrl+alt', key = 'j', action = 'toggle_settings',
    group = 'panels', desc = 'settings panel' },
  ...
}
```

- `mod` — `+`-joined: `ctrl`, `alt`, `shift`, `super`
- `key` — keysym name (`a`, `s`, `F2`, `Left`, …)
- `action` — any registered action. Every panel plugin auto-registers
  `toggle_<panel>` (e.g. `toggle_sysmon`). Builtins: `quit`, `close_panels`,
  `hot_reload`, `toggle_auto_reload`, `toggle_theme`, `hide_all_windows`,
  `debug_dump_panel`, `debug_screenshot`, `toggle_debug_mode`,
  `move_win_left/right/up/down`, `resize_win_wider/narrower/taller/shorter`,
  `reset_active_window`.
- `group` / `desc` — grouping and description shown in the keybind help panel.

Registration backends: Hyprland (`hyprctl eval` or `keyword bind` fallback),
Sway (`swaymsg bindsym`), generic Wayland/X11 via `lbar-cli` IPC — niri users
must paste the `binds { ... }` block printed in the lbar log into
`~/.config/niri/config.kdl` themselves (lbar never writes external configs).

## Panels

Per-panel placement and animation:

```lua
panels = {
  settings = { pos = 'center', anim = 'auto' },
}
```

- `pos` — `center` `top` `bottom` `left` `right` `top_left` `top_right`
  `bottom_left` `bottom_right`
- `anim` — `auto` (derived from pos/anchor) `slide_up` `slide_down`
  `slide_left` `slide_right` `none`

Bar-anchored opens (clicking the bar item) follow the bar item position;
`panels.<name>.pos` is used when toggled via keybind.

All panels are draggable: press and hold anywhere on the title bar (except
the `×` close button) and move the mouse. Free-positioned panels remember
the dragged position across reopens (`Panel:show`); bar-anchored panels
re-anchor to their bar item on the next click.

### Auto-fit and reactive resizing

Panels auto-fit their content: a panel whose content size changes (schedule
rows added/removed, wifi scan results, launcher filter counts, sysmon core
count, probe rows landing) recomputes its natural size via `Panel:fit()` —
live while visible, or on the next open. If you resized a panel manually
(`ctrl+alt+shift` + arrows), your size is kept and content reflows instead.

Every panel layout is reactive: the draw path re-derives from the live
surface size each frame, so manual resizes reflow lists, columns and
footers instead of overlapping them (reference pattern: `settings.lua`
`do_draw`).

## Panel opts

```lua
panel_opts = {
  launcher = { dismiss_outside = false },
}
```

- `dismiss_outside` (default `true`) — when `false`, clicking outside the
  panel does not close it and the click passes through to other apps.

## Plugin sections

### cpu / mem (bar item styling)

Compact text-only labels, colored by load/usage.

| key | default | description |
|---|---|---|
| `interval_ms` | cpu `1000`, mem `2000` | sample interval |
| `color` | `true` | color by load/usage (good/warn/crit) |

### wifi

| key | default | description |
|---|---|---|
| `interface` | `'auto'` | wifi iface name, or `'auto'` to detect |
| `refresh_sec` | `8` | periodic rescan interval while panel is open |

Requires `nmcli` (NetworkManager).

### wallpaper

| key | default | description |
|---|---|---|
| `dir` | `~/Pictures`, `~/Pictures/wallpapers`, `~/wallpapers` | scan dir — string or list |
| `depth` | `3` | `find` maxdepth |
| `set_cmd` | auto-detect | custom setter; `$f` = file path |
| `max_items` | `300` | max scanned files |

Setter auto-detect order: `set_cmd` > running swww-daemon (auto-started if
installed) > swaybg (`SWAYSOCK`) > hyprpaper (`HYPRLAND_*`) > wayland + swww
> feh > nitrogen > xwallpaper > hyprctl. Covers i3/X11 via
feh/nitrogen/xwallpaper.

### battery (session menu)

The battery bar item opens one merged panel: battery status on top, then a
Noctalia-style session card row.

| key | default | description |
|---|---|---|
| `lock_cmd` | `'swaylock -f'` | lock command (runs immediately, no confirm) |
| `logout_cmd` | auto-detect | override; auto: niri/hyprland/sway session exit |
| `confirm` | `true` | confirm footer before logout/sleep/reboot/poweroff |
| `items` | all | subset/order of `lock` `logout` `sleep` `reboot` `poweroff` |

### launcher

| key | default | description |
|---|---|---|
| `use_dmenu_path` | `true` | merge `$PATH` executables into the entry list |
| `entries` | `{}` | extra entries: `{ name = 'terminal', cmd = 'alacritty' }` |

### pomodoro

`work_min` (25), `break_min` (5).

### clip_hist

`max_items` (30) — stored clipboard entries.

### clock

| key | default | description |
|---|---|---|
| `schedule_file` | `$XDG_STATE_HOME/lbar/schedule.conf` | schedule/alarms file, one entry per line |

Entries are added with the built-in picker: click a calendar day to select
the date (the selected day gets a highlight chip), press `add`, then set the
time with the hour/minute steppers (`−`/`+`, minutes step by 5) and type a
description. Submitting a past time for a future date is rejected; a past
time on today rolls over to tomorrow. The panel auto-fits to the actual
calendar row count, schedule rows and the add-strip, and reflows on manual
resize.

The schedule file stays hand-editable — one entry per line,
`YYYY-MM-DD HH:MM text`. Up to 6 entries are shown (sorted by time); days
with pending schedules get a marker dot in the calendar. When a time comes
due, a warning toast fires once per entry — entries that are already past
when loaded never alert (e.g. after restart).

### weather

| key | default | description |
|---|---|---|
| `units` | `'c'` | `'c'` or `'f'` |
| `refresh_sec` | `900` | fetch interval |
| `manual_city` | auto-locate | city name string |

### move_window / resize_window

`move_window.step` (30), `move_window.mode` (`'auto_float'`),
`resize_window.step` (30).

## Notes

- Plugins write back to config.lua themselves (theme mode, settings panel
  edits) with an in-place section-aware editor; the auto-reload watcher is
  suppressed for one cycle after each write.
- Bar items render in `plugins` list order; if the row overflows, gaps are
  compressed first, then item widths squeezed proportionally — no item is
  dropped.
