# lbar config.lua 配置说明

配置文件位于 `lbar.lua` 同目录的 `config.lua`（也可通过 argv[1] 传入其他路径）。
它就是单个 Lua 表：`return { ... }`。所有值在启动时读取，且支持热重载（每次保存
触发 800ms watcher 自动重载；仅当 `font_path`/`font_size`/`fallback_font_paths`
变化时才重新加载字体）。

设置面板（`ctrl+alt+j`）可以在界面上直接编辑下表的几乎所有键并写回本文件。

## 顶层键

| 键 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `position` | `'top'` \| `'bottom'` | `'top'` | 栏在屏幕的哪一侧；锚定到栏的面板随之在栏下/上方打开 |
| `height` | `'auto'` \| number | `'auto'` | 栏高度 px；`'auto'` = 行高 + 18 |
| `padding` | number | `16` | 栏两端内边距 |
| `gap` | number | `10` | bar item 间距（溢出时自动压缩） |
| `bar_margin` | number | `0` | 栏与屏幕边缘的距离 |
| `theme` | string | `'md3_dark'` | 深色模式配色名（见下） |
| `theme_light` | string | `'md3_light'` | 浅色模式配色名 |
| `theme_mode` | `'dark'` \| `'light'` | `'dark'` | 当前模式；`ctrl+alt+k` 和设置面板切换后写回 |
| `corner` | `'round'` \| `'square'` | `'round'` | 全局圆角风格；`'square'` 会把按钮/胶囊/卡片/栏/面板窗口全部压成直角。可在设置面板切换（Options → style → corner style） |
| `lang` | `'auto'` \| `'en'` \| `'zh'` | `'auto'` | 界面语言；`'auto'` 根据 `$LANG` 检测（`zh*` → 中文）。可在设置面板实时切换。所有可见字符串（面板标题、标签、按钮、状态、toast、bar item 标签）均已翻译 |
| `font_path` | string | — | 主字体（TTF/OTF），支持 `~` |
| `font_size` | number | `14` | 字号 px |
| `fallback_font_paths` | string 列表 | `{}` | 回退字体（如 CJK 字形用 Noto Sans CJK） |
| `audio_panel_dir` | string | — | 音乐面板扫描目录 |
| `music_state_file` | string | `$XDG_STATE_HOME/lbar/music.conf` | 音乐播放器音量 + 最后播放曲目持久化 |
| `debug_shot_dir` | string | `~/Pictures/lbar` | 调试截图输出目录（`ctrl+alt+shift+x`） |
| `plugins` | string 列表 | — | 插件加载顺序 = bar item 从左到右的排列顺序 |
| `keybinds` | table 列表 | — | 见 "快捷键" 一节 |
| `panels` | table | — | 每个面板的默认位置，见 "面板位置" |
| `panel_opts` | table | — | 每个面板的行为开关，见 "面板行为" |

## 主题

14 套内置配色 — 深色：`md3_dark`、`one_dark`、`gruvbox_dark`、`nord`、
`catppuccin_mocha`、`tokyo_night`、`solarized_dark`；浅色：`md3_light`、
`one_light`、`gruvbox_light`、`catppuccin_latte`、`tokyo_night_day`、
`solarized_light`。`ctrl+alt+k` 切换 `theme_mode` 并把它写回 config.lua。

## 插件

合法名称即 `plugins/<name>.lua`。带 bar item 的已标注；其余仅为动作/面板。

| 插件 | bar item | 打开内容 |
|---|---|---|
| `logo` | tux logo | 应用信息弹窗（主题切换、重载、退出） |
| `workspace` | 当前工作区 | 点击切换工作区（hyprland/sway） |
| `cpu` | `cpu` + 占用 | 系统监控面板 |
| `mem` | `mem` + 占用 | 系统监控面板 |
| `battery` | `BAT NN%` / `CHG` / `LOW` | 电池 + 电源菜单（无电池时隐藏） |
| `volume` | `VOL N%` / `MUTE` | 音量面板（缺 pactl 时隐藏） |
| `clock` | 时间 | 时钟面板 |
| `keybinds_help` | `keys` | 快捷键目录 |
| `launcher` | `apps` | 应用启动器 |
| `clip_hist` | `clip` | 剪贴板历史 |
| `pomodoro` | 计时状态 | 番茄钟面板 |
| `music_player` | 曲目状态 | 音乐面板 |
| `weather` | 温度 | 天气面板 |
| `sysinfo` | `info` | 系统信息面板 |
| `sysmon` | `mon` | 进程监控 |
| `color_picker` | `pick` | 取色器 |
| `ui_demo` | `ui` | UI 组件示例 |
| `settings` | `set` | 设置面板 |
| `wallpaper` | `wall` | 壁纸选择器 |
| `wifi` | ssid + 信号 | wifi 面板 |
| `tray` | 系统托盘图标 | 无面板（图标直接内嵌在栏中，显示可能为空） |
| `hide_all` | —（纯动作） | `hide_all_windows` |
| `move_window` | —（纯动作） | 窗口移动快捷键 |
| `resize_window` | —（纯动作） | 窗口缩放快捷键 |

## 快捷键

```lua
keybinds = {
  { mod = 'ctrl+alt', key = 'j', action = 'toggle_settings',
    group = 'panels', desc = 'settings panel' },
  ...
}
```

- `mod` — `+` 连接：`ctrl`、`alt`、`shift`、`super`
- `key` — keysym 名（`a`、`s`、`F2`、`Left` 等）
- `action` — 任意已注册动作。每个面板插件自动注册 `toggle_<panel>`（如
  `toggle_sysmon`）。内置动作：`quit`、`close_panels`、`hot_reload`、
  `toggle_auto_reload`、`toggle_theme`、`hide_all_windows`、
  `debug_dump_panel`、`debug_screenshot`、`toggle_debug_mode`、
  `move_win_left/right/up/down`、`resize_win_wider/narrower/taller/shorter`、
  `reset_active_window`。
- `group` / `desc` — 快捷键帮助面板里的分组与描述。

注册后端：Hyprland（`hyprctl eval`，回退 `keyword bind`）、Sway
（`swaymsg bindsym`）、通用 Wayland/X11 通过 `lbar-cli` IPC — niri 用户需
把 lbar 日志打印的 `binds { ... }` 块手动粘贴到
`~/.config/niri/config.kdl`（lbar 绝不写外部配置文件）。

## 面板位置

每个面板的默认位置与动画：

```lua
panels = {
  settings = { pos = 'center', anim = 'auto' },
}
```

- `pos` — `center` `top` `bottom` `left` `right` `top_left` `top_right`
  `bottom_left` `bottom_right`，或 `auto`（锚定到对应 bar item）
- `anim` — `auto`（按 pos/锚点推导）`slide_up` `slide_down`
  `slide_left` `slide_right` `none`

显式 `pos`（非 `auto`）优先于 bar 锚定：每次打开（包括点击 bar item）都
落在配置的入场位置。`auto` 面板锚定到自己的 bar item。用户拖拽过的位置
（user_pos）优先级最高，重开后保留。面板打开时若与可见面板重叠，自动
挪到最近的空位（候选锚点 = 屏幕四角/中心 + 各可见面板边缘，仍无空位才
对角级联兜底，见 `Panel:avoid_overlap`）；拖拽/缩放/内容长高后始终夹取
在屏幕内（保留 8px 边距），底部/右侧不会被截断。

`panels.<name>.anim` 优先于 `animation.style`，两者均在启动时读取。

### 窗口动画（PPT 式入场/出场）

```lua
animation = {
  enabled     = true,   -- 总开关（false = 面板即时出现）
  style       = 'auto', -- 或 slide_up / slide_down / slide_left / slide_right / none
  duration_ms = 150,    -- 入场/出场时长
  distance    = 40,     -- 滑动距离 px
  exit        = true,   -- 出场是否播动画
}
```

`style = 'auto'` 时每个面板从自己的锚点侧滑入（bar 锚定面板沿锚点方向，
自由面板沿 `panels.<name>.pos` 对应的边）。

支持的全部取值：`auto` `slide_up` `slide_down` `slide_left`
`slide_right` `none`。默认 `config.lua` 已覆盖全部 6 种：
`volume` → `slide_up`（底部上滑）、`launcher` → `slide_down`（顶部下滑）、
`color_picker` → `slide_left`（右侧左滑）、`keybinds_help` →
`slide_right`（左侧右滑）、`ui_demo` → `none`（即时显隐）、其余 `auto`。
覆盖情况由 `tools/plugin_test.lua` 启动时静态检查（不覆盖或取值非法即
FAIL）。

所有面板可拖拽：按住标题栏（`×` 关闭按钮除外）拖动即可。自由定位面板
记住拖拽位置（`Panel:show`）；bar 锚定面板下次点击时重新锚定。

### 自适应尺寸与响应式重排

面板自动适配内容：内容尺寸变化（日程增删、wifi 扫描结果、启动器过滤
数量、sysmon 核心数、探针行返回等）时经 `Panel:fit()` 重算自然尺寸 —
可见时实时调整（live resize），否则下次打开时生效。若用户手动调整过大小
（`ctrl+alt+shift` + 方向键），则保留用户尺寸，内容重排（reflow）。

每个面板布局都是响应式的：绘制路径每帧从实际 surface 尺寸推导，手动
缩放时列表、列、页脚重排而不是互相覆盖（参考模式：`settings.lua`
的 `do_draw`）。

## 面板行为

```lua
panel_opts = {
  launcher = { dismiss_outside = false },
}
```

- `dismiss_outside`（默认 `true`）— 设为 `false` 时点击面板外部不关闭，
  点击穿透到其他应用。X11 上是 pointer grab；Wayland 上由全屏透明捕获面
  （位于面板之下、挖掉栏区）接收外部按下并吞掉，行为与 X11 一致。

## 各插件配置节

### cpu / mem（bar item 样式）

紧凑纯文本标签，按负载/占用着色。

| 键 | 默认值 | 说明 |
|---|---|---|
| `interval_ms` | cpu `1000`、mem `2000` | 采样间隔 |
| `color` | `true` | 按负载/占用着色（good/warn/crit） |

### wifi

| 键 | 默认值 | 说明 |
|---|---|---|
| `interface` | `'auto'` | 网卡名，`'auto'` 自动检测 |
| `refresh_sec` | `8` | 面板打开时的周期重扫间隔 |

依赖 `nmcli`（NetworkManager）。

### wallpaper

| 键 | 默认值 | 说明 |
|---|---|---|
| `dir` | `~/Pictures`、`~/Pictures/wallpapers`、`~/wallpapers` | 扫描目录 — 字符串或列表 |
| `depth` | `3` | `find` maxdepth |
| `set_cmd` | 自动探测 | 自定义设置命令；`$f` = 图片路径 |
| `max_items` | `300` | 最多扫描文件数 |

设置器自动探测顺序：`set_cmd` > 运行中的 swww-daemon（未运行则自动拉起）
> swaybg（`SWAYSOCK`）> hyprpaper（`HYPRLAND_*`）> wayland + swww > feh >
nitrogen > xwallpaper > hyprctl。i3/X11 经 feh/nitrogen/xwallpaper 覆盖。

### battery（会话/电源菜单）

电池 bar item 打开一个合并面板：上方电池状态，下方会话卡片行（锁屏/注销/
睡眠/重启/关机）。

| 键 | 默认值 | 说明 |
|---|---|---|
| `lock_cmd` | `'swaylock -f'` | 锁屏命令（立即执行，不确认） |
| `logout_cmd` | 自动探测 | 覆盖注销命令；自动：niri/hyprland/sway 会话退出 |
| `confirm` | `true` | 注销/睡眠/重启/关机前弹确认 |
| `items` | 全部 | `lock` `logout` `sleep` `reboot` `poweroff` 的子集/顺序 |

### launcher

| 键 | 默认值 | 说明 |
|---|---|---|
| `use_dmenu_path` | `true` | 把 `$PATH` 下可执行文件合并进条目列表 |
| `entries` | `{}` | 额外条目：`{ name = 'terminal', cmd = 'alacritty' }` |

### pomodoro

`work_min`（25）、`break_min`（5）。

### clip_hist

`max_items`（30）— 保留的剪贴板条数。

### clock

| 键 | 默认值 | 说明 |
|---|---|---|
| `schedule_file` | `$XDG_STATE_HOME/lbar/schedule.conf` | 日程/闹钟文件，一行一条 |

日程通过内置选择器添加：点击日历某天选中日期（选中日高亮 chip），按
`add`，再用时/分步进器（`−`/`+`，分钟步进 5）设置时间并输入描述。过去
时间 + 未来日期会被拒绝；今天已过时间自动滚动到明天。面板按实际日历行数、
日程行数与添加条自适应尺寸，手动缩放时重排。

日程文件保持可手编 — 一行一条，`YYYY-MM-DD HH:MM 文本`。最多显示 6 条
（按时间排序）；有待办日程的日期在日历上显示圆点标记。到点时每条触发
一次 warning toast — 加载时已过期的条目不再提醒（如重启后）。

### weather

| 键 | 默认值 | 说明 |
|---|---|---|
| `units` | `'c'` | `'c'` 或 `'f'` |
| `refresh_sec` | `900` | 拉取间隔 |
| `manual_city` | 自动定位 | 城市名字符串 |

### tray（系统托盘）

把"通知区域"图标（XEmbed 协议）直接内嵌到栏里。无图标时该 item 自动隐藏，
宽度为 0。

| 键 | 默认值 | 说明 |
|---|---|---|
| `enabled` | `true` | 是否启用托盘 |
| `icon_size` | `20` | 图标尺寸 px（会自动限制为不超过栏高） |
| `gap` | `6` | 图标之间的间距 px |

- 仅支持经典的 **XEmbed** 系统托盘协议（`_NET_SYSTEM_TRAY_S<n>`），适用于
  X11 应用、Wine、Java、旧版 Qt/GTK 程序；需要 **XWayland**（Wayland 会话）。
- 原生 **SNI**（DBus `StatusNotifierItem`，多数 Electron / 现代 GTK3 应用）
  不在该协议内，暂不显示。
- X11 后端：图标被重 parent 进栏窗口，由 X 原生渲染，点击/滚轮直接生效。
- Wayland 后端：图标窗口映射在屏幕外，像素拷贝进栏表面，点击通过
  `XSendEvent` 转发给图标（部分应用的右键菜单可能不响应）。
- 若已有其它托盘宿主（如 waybar）在运行，lbar 取得不了选择权，托盘会自动
  保持为空且不影响栏的其它部分。

### move_window / resize_window

`move_window.step`（30）、`move_window.mode`（`'auto_float'`）、
`resize_window.step`（30）。

## 备注

- 插件会自己写回 config.lua（主题模式、设置面板编辑），使用就地
  section-aware 编辑器；每次写回后自动重载 watcher 抑制一个周期。
- bar item 按 `plugins` 列表顺序渲染；行溢出时先压缩间距，再按比例压缩
  item 宽度 — 不会丢弃任何 item。
- X11 渲染使用 MIT-SHM 零拷贝上传（不可用时自动回退 XPutImage），鼠标
  移动事件在 C 层合并，保证拖拽/多面板/动画流畅。
