# lbar

LuaJIT + C 实现的轻量状态栏 / 面板套件，同时支持 **X11** 与 **Wayland**
（layer-shell）。单进程、零依赖框架，所有面板/插件用 Lua 编写，热重载即时生效。

## 特性

- 栏 + 多面板并存：面板可拖拽、自适应尺寸、入场/出场动画、点击外部关闭（可按面板配置）
- 21 个内置插件：启动器、剪贴板历史、工作区、CPU/内存/进程监控、系统信息、
  时钟 + 日程、番茄钟、音乐播放器、天气、wifi、音量、电池 + 电源菜单、
  壁纸选择器、取色器、UI 组件示例、设置面板等
- 14 套内置主题，深/浅色一键切换，全局圆角/直角风格
- 完整中文/英文国际化（`I.t()` 单一入口，根据 `$LANG` 自动检测）
- Wayland 原生支持：layer-shell、zwp_text_input_v3 输入法、IPC 全局快捷键；
  niri/hyprland/sway 均覆盖
- X11 性能：MIT-SHM 零拷贝渲染上传、事件合并，拖拽/多面板流畅

## 构建与运行

```sh
make            # 生成 lbar.so / lbar_audio.so / lbar-cli
make run        # 前台运行（luajit lbar.lua config.lua）
```

依赖：freetype2、harfbuzz、x11、xext、wayland-client、xkbcommon；
音频面板额外依赖 SDL2_mixer。可选运行时依赖：pactl（音量）、nmcli（wifi）、
zenity（文件对话框）、swww/swaybg/feh 等（壁纸）。

修改配置/插件后 800ms 内自动热重载；字体变化也支持热重载。

## 快捷键（默认，可在 config.lua 修改）

| 组合键 | 功能 |
|---|---|
| `ctrl+alt+e` / `ctrl+alt+v` | 启动器 / 剪贴板历史 |
| `ctrl+alt+t` / `ctrl+alt+i` | 系统监控 / 系统信息 |
| `ctrl+alt+g` / `ctrl+alt+b` | 时钟 / 番茄钟 |
| `ctrl+alt+m` / `ctrl+alt+s` | 音乐播放器 / 音量 |
| `ctrl+alt+n` / `ctrl+alt+o` | wifi / 电池 + 电源菜单 |
| `ctrl+alt+j` / `ctrl+alt+p` | 设置 / 壁纸 |
| `ctrl+alt+k` | 深/浅色主题切换 |
| `ctrl+alt+d` | 隐藏/恢复全部面板 |
| `ctrl+alt+shift+方向键` | 调整活动面板大小（+`0` 重置） |
| `ctrl+alt+r` | 手动热重载 |
| `ctrl+alt+q` | 退出 |

完整快捷键目录：`ctrl+alt+h`（或栏上 `keys` item）。

## 项目结构

```
lbar.lua          # 入口：主循环、事件分发、多面板焦点管理、热重载
config.lua        # 全局配置（中文注释，热重载生效）
src/
  backends.c      # 单文件双后端：Wayland layer-shell + X11（SHM 渲染、输入、IPC）
  text.c          # FreeType/HarfBuzz 文本渲染
  audio.c         # SDL2_mixer 音频
core/
  bar.lua         # 栏布局与 bar item 调度
  panel.lua       # 面板窗口：拖拽、动画、自适应、焦点
  ui.lua          # MD3 风格控件库（按钮/输入框/开关/滑条/分段控件）
  text_input.lua  # TextInput 组件（换行、选区、长按工具条）
  theme.lua       # 主题构建
  i18n.lua        # 国际化
  toast.lua       # toast 通知
  keybinds.lua    # 全局快捷键注册
  plugins.lua     # 插件加载器 + 热重载 watcher
  clipboard.lua   # 剪贴板
  screenshot.lua  # 调试截图
  util.lua        # 通用工具（corner_r 等）
  wm/             # 合成器适配（hyprland/niri/sway）
plugins/          # 每个插件一个文件，独立可装卸
docs/config.md    # config.lua 完整配置说明（中文）
tools/            # lbar-cli（IPC 快捷键）、i18n 检查脚本
```

## 配置

所有配置集中在 `config.lua`（键值说明见 [docs/config.md](docs/config.md)）。
设置面板（`ctrl+alt+j`）可在界面上修改大部分配置并自动写回。
