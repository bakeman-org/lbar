# lbar 更新日志

本文件由历史 TODO 日志迁移而来（第 1–90 条，按时间从旧到新排列），记录已完成的工作项。

## 1. 修复弹窗 UI 花屏
采用 xpet 验证过的 XImage 刷新路径：图像数据改用 calloc 分配，并按 bytes_per_line 逐行拷贝，消除弹窗乱码。

## 2. 面板（popup）重构为 xpet 面板系统
整体重构面板实现并修复 wayland 路径：move/show 时提交 margin、flush 增加保护、隐藏后可重新显示。

## 3. 每次改动全量编译
构建流程调整为每次变更都对全部代码重新编译。

## 4. 移植 xpet 全局快捷键
新增 config.keybinds，通过 X11 grab 实现 ctrl+alt+c/y/h/r/q 等全局按键。

## 5. 完成 xpet 插件全量迁移
迁移插件包括：launcher、clip_hist、pomodoro、music_player、weather、sysinfo、sysmon、color_picker、move_window、resize_window、ui_demo、keybinds_help、hide_all。

## 6. config.lua 中的 xpet 快捷键
keybinds 带分组与描述（供 keybinds_help 展示），并支持各插件选项。

## 7. 面板随字号自适应
引入 size_fn 与基于行高（lh）推导的尺寸模型，面板随字体大小自动调整。

## 8. 通用 UI 控件框架
提供按钮、滑块、开关、进度条等控件，基于 id 的 hover/click 事件处理。

## 9. MD3 设计语言
core/theme.md3 引入 Material Design 3 风格，同时保留旧配色映射。

## 10. xpet 风格 toast
弹窗槽位支持 toast 提示，样式分为 plain/success/error。

## 11. 面板 live_resize/move_to/move_by
支持动态调整大小与移动；指针 grab + 屏幕采样取色（X11）用于取色器。

## 12. 弹窗槽位与交互规则
LBAR_POPUP_MAX 上限设为 16；Escape 关闭 sticky 面板；实现滚动事件路由。

## 13. music_player 时长错误修复
探测失败的音轨会显示虚假时长，现钳制 d < 3600。

## 14. wayland 点击与全局快捷键（部分完成）
### 修复
- bar/弹窗点击失效：wl_pointer.button 传入的是原始 linux 按键码（BTN_LEFT=0x110），Lua 侧 btn==1 判断全部失败；现映射为 X11 风格 1/2/3/8/9。
- 全局快捷键：unix IPC socket（$XDG_RUNTIME_DIR/lbar.sock）+ lbar-cli 工具 + 启动时自动注册 compositor 绑定（hyprctl keyword bind / swaymsg bindsym）；命令经主循环分发（空格转下划线，如 "toggle launcher"）；wl 指针 enter/button 已加调试日志。
### 遗留
- 弹窗键盘（wl_keyboard/文本输入）仍为 X11-only；真实 sway/hyprland 会话上的面板验证尚未完成。

## 15. 全部面板插件的 bar 项
为 apps/clip/pomo/music/wttr/info/mon/pick/ui/keys 等面板提供 bar 项，经 Util.toggle_from_bar 锚定切换。

## 16. 面板自动适配
每次 show 时重新 fit；model_fn 依据当前行高重建布局。

## 17. bar 间距压缩
大字号下条目超出宽度时压缩间隙；pomodoro/keybinds 面板尺寸上限随行高缩放。

## 18. reload_all 清理旧面板
热重载销毁旧面板并清空 ctx._panels（避免陈旧 popup id）；toast 改用 live_resize。

## 19. 内置主题
提供 md3/one/gruvbox/nord/catppuccin/tokyo_night/solarized 各 dark+light 主题（config 中 theme = 名称即可）。

## 20. 深色/浅色模式切换
ctrl+alt+k 或菜单面板 Theme 按钮，bar 与面板实时重绘。

## 21. 面板位置记忆
ctrl+alt+arrows 移动的位置在 hide（ctrl+alt+d）后再次 show 时保持。

## 22. 提示文字对比度
将偏暗的 T.outline 提示文字改为可读的 T.hint（on_var），应用到所有面板。

## 23. 菜单插件
bar 最左侧显示 tux logo；应用信息面板（backend/screen/engine/font/plugins/uptime）+ theme/reload/quit 按钮。

## 24. ui_demo 完整控件展示
按钮、chips、slider+progress、开关、可输入文本框、hover+select 列表，并带主题标签。

## 25. color_picker 面板加宽
面板 320→420，色块 64→96。

## 26. 标准面板头框架
Panel:draw_header(title,hint,pad) / header_close / header_hit：表面条带、标题居左、提示居右、统一 28x28 圆角 8 关闭按钮与分隔线；应用到全部 13 个面板（weather、sysinfo、color_picker、pomodoro、clip_hist、keybinds_help、music_player、system、launcher、sysmon、menu、ui_demo、clock）。

## 27. 面板显示不再自动抢键盘
面板 show 时不再自动 grab 键盘/输入焦点（曾阻塞 i3 的 super+shift+p）；仅文本输入聚焦时 grab（点击聚焦、点击外部失焦）——涉及 launcher、sysmon、music_player、ui_demo。

## 28. 点击面板外部隐藏
面板可见期间持有指针 grab（toast 与 color_mag 除外）。

## 29. music_player 持久化
头栏关闭快捷键 ctrl+alt+m；音量与上一曲保存到 ~/.local/state/lbar/music.conf（热重载保留 ctx._music_state）。

## 30. 面板响应式缩放
ctrl+alt+shift+arrows 设置 user_size，live_resize 中以 model_fn(ctx, user_size) 重建；flow 面板重算可见行数，固定面板钳到自然最小值；ctrl+alt+shift+0 重置。

## 31. color_picker 取色流程修复
事件现路由到 ctx.active_panel（放大镜原本不在 panels 表中）；取色期间放大镜 grab 键盘，Escape 取消。

## 32. panel_opts 每面板配置
config.lua 中 dismiss_outside = false 让面板在外部点击时保持打开并放行点击（launcher、sysmon、music_player）；ctrl+alt+shift+s 将可见面板转储为 /tmp/lbar_<name>.bmp 供 UI 反馈。

## 33. launcher 占位符缩短
改为 "search apps…"（原 440px 宽输入框中被裁切）。

## 34. music_player 头栏副标题移除
避免与曲目名重复；状态文件可经 config.music_state_file 配置，保存时按需创建目录。

## 35. sysmon 细节修复
搜索框在头栏条带内居中（不再遮挡 CPU/spark）；pid 列宽取可见最宽 pid（避免与名称重叠）；ctrl+k / 右键先询问——底栏确认条 "kill <pid> <name>?" 带 kill/cancel 按钮，再次 ctrl+k 确认，Esc 取消。

## 36. clip_hist 重做
标准头栏含快捷键提示；清空按钮移到底栏（左侧 N / M 计数，右侧 tonal 清空按钮）。

## 37. color_picker 重写
取色开始时冻结全屏截图（X11 经 lbar_x_get_region 一次性 XGetImage，wayland 经 grim PPM），放大镜 + 十字线 + 点击取色均读取冻结缓冲（修复实时采样总得到白色 #FFFFFF 的 bug）；方向键移动光标（8px，shift 为 1px），Enter 取色，Esc/右键取消；X11 与 wayland 均可用。

## 38. ui_demo 标签页
controls / lists / inventory 三个标签；新增可拖动 ui:scrollbar 控件演示、控件清单与面板快捷键列表。

## 39. 调试模式开关
ctrl+alt+shift+d 切换 ctx.debug，将 toast 固定在屏幕上（不自动消失）便于截图；关闭时隐藏固定 toast。

## 40. 通用调试截图工具 core/screenshot.lua
ctrl+alt+shift+x：全屏截图并以可见面板/toast/屏幕命名，保存到 config.debug_shot_dir（默认 ~/Pictures/lbar），X11 用原生 XGetImage 存 BMP，wayland 用 grim 存 PNG；尽力复制到剪贴板（xclip+convert / wl-copy），灵感来自用户的截图 shell 脚本。

## 41. lbar-cli IPC
`lbar-cli toggle launcher`（或任意 action，空格=下划线）通知运行中的 lbar 执行；hyprland 启动时经 hyprctl eval hl.bind("CTRL + ALT + h", hl.dsp.exec_cmd("lbar-cli <action>")) 自动注册快捷键——注意 hyprctl keyword bind 在 Hyprland 0.56 已失效（非 legacy 解析器）；先 unbind 再注册防止重复触发；sway 仍用 swaymsg bindsym。

## 42. wayland 透明 bug（主题色）
主题色原为 24 位（alpha=0）——X11 忽略 alpha，但 wl ARGB8888 缓冲参与合成，导致所有填充半透明（"theme broken"）；M.build 现对每个颜色 token OR 0xFF000000（0 仍保持透明以支持圆角）。

## 43. wayland 协议崩溃防护
针对 "layerSurface was not configured, but a buffer was attached"：flush 在 attach 前检查 configured，并在每次 attach 前执行 wl_display_dispatch_pending + wl_display_roundtrip，确保 compositor 触发的 configure（快速双击层抖动）总是先被 ack；pending popup flush 延迟，pop_configure 经 expose 事件（ev.btn = popup id）重触发精确面板重绘；pop_buf_release 匹配释放的缓冲；新增实例锁（$XDG_RUNTIME_DIR/lbar.lock）拒绝第二个 lbar，防止陈旧旧二进制进程残留。

## 44. 主题模式持久化
config.theme_mode = 'dark'|'light' 在 Theme.build 中选择 theme/theme_light 配色；ctrl+alt+k 切换时将 theme_mode 原地写回 config.lua（gsub，插到 theme_light 之后或追加）——重启/热重载恢复上次使用的模式而非固定 dark；菜单 logo 的 Theme 按钮走同一 actions.toggle_theme 以保证持久化。

## 45. wayland "过于透明" 根因
所有软件光栅路径（surf_fill、blend、blend_px、彩色 emoji blit）把 alpha 字节掩成 0——X11 忽略 alpha 看似正常，但 wl ARGB8888 合成 alpha，导致 hyprland/niri 上所有填充（bar + 弹窗）完全不可见；blend 辅助函数现写入正确的 "over" alpha（premultiplied 正确），surf_fill 强制不透明，并经 ffi 验证 surf_fill(0x141218) → 0xFF141218。

## 46. niri width-0 协议错误（初版钳制）
"width 0 requested without setting left and right anchors" 会杀死整个 wayland 连接（表面冻结/花屏，如坏掉的 sysmon）：lbar_popup_create 将 w/h 钳到 >=1，wl_create_bar 钳 h，Panel.new/Panel:resize 同样钳制——不再有 set_size(0) 到达 compositor（但钳制并非真正诱因，见第 48 条）。

## 47. X11 崩溃修复（lbar.lua:457）
"'struct 99' has no member named 'btn'"：lbar_event_t 字段是 `button`，旧的延迟 flush expose 处理器误用 ev.btn；已删除死注释块（处理器已重构为 lbar_popup_visible + active_panel 重绘）。

## 48. niri width-0 真正修复
错误发生在 hide→remap 周期：wl_popup_hide 经 attach(NULL) unmap，而 wl_popup_show 只重发 set_margin 并 commit，依赖跨 unmap 的陈旧 layer-shell 状态，niri/smithay 在 remap 时拒绝；现 wl_popup_hide 重置 configured/flush_pending，wl_popup_show 在 commit 前重发 set_size/anchor/exclusive_zone/margin，使每次 remap 等待有效正尺寸的新 configure。

## 49. 面板花屏/静态噪声修复
compositor 可能把层表面配置得比请求小（日志：configure 462x704 vs buffer 462x796），而 Lua 沿用自己的尺寸，lbar_popup_flush 从较小的 Lua surf memcpy p->w*p->h 字节（堆越读 = 噪声 + 损坏）；flush 现接收 (sw,sh) 并按行拷贝最小重叠区、其余补零，经出参返回实时 popup 尺寸；新增 lbar_popup_size 导出；Panel:draw 绘制前将 self.w/h/surf 同步到 C 尺寸；Panel:_begin_show 将面板尺寸钳到屏幕边界以尽量免于 compositor 钳制。

## 50. 热重载按钮崩溃修复
Reload 按钮在被销毁面板自身的 Panel:on_press 中运行 reload_all——Panel.destroy() 置空 self.surf 后 on_press 继续进入 draw() → surf_fill(NULL) 段错误；新增 Panel.destroyed 标志守卫 draw/on_press/on_release，lbar.lua 中全部面板事件分发（motion/press/release/key）经 pcall 包裹，reload_all 守卫 lbar_open 返回 nil。

## 51. menu 插件改为 logo 插件
plugins/logo.lua：bar 上 tux logo 点击经 actions.toggle_theme 直接切换主题（同时持久化 theme_mode 到 config.lua）；移除 info/quit 面板，config.lua 插件列表更新。

## 52. niri 全局快捷键（后被撤销，见 54）
register_wm_binds 检测 NIRI_SOCKET 并向 ~/.config/niri/config.kdl（或 $NIRI_CONFIG）注入带标记的 "// >>> lbar-binds >>>" 块（binds { Ctrl+Alt+E { spawn "<abs>/lbar-cli" "toggle_launcher"; } ... }）；每次启动/热重载先剥离再重写（幂等）；niri 自动重载配置，使 ctrl+alt 快捷键在所有应用中全局生效。

## 53. niri 弹窗 remap 死锁 → 弹窗不可交互
第 48 条的修复让 hide 重置 configured=0 且 show 等待新 configure，但 niri/smithay 只在尺寸变化时发送 configure——同尺寸重 commit 不会收到 configure，configured 恒 0，flush 永远延迟，面板永不映射（点击落到下层 = "按钮/文本框点击无反馈"）；现 wl_popup_show 自给自足（同一次 commit 内重发 set_size/anchor/exclusive_zone/margin 并 attach 现有缓冲 + damage，不等待 configure），wl_popup_hide 保留 configured；同时补齐 wayland 文本输入键盘焦点：lbar_kbd_grab/ungrab 驱动 zwlr_ls_set_keyboard_interactivity exclusive/none + commit（原为 X11-only XGrabKeyboard，wayland 文本输入无法接收按键）；Panel:_kbd_sync 已调用这些，niri/hyprland/sway 上点击聚焦输入可用。

## 54. 撤销 niri config.kdl 绑定注入（第 52 条）
写外部配置文件有风险；niri 上 lbar 仅在日志中打印可直接粘贴的 binds { ... } 块由用户手动添加；hyprland（hyprctl eval）与 sway（swaymsg）不变（运行时 IPC，不触碰文件）；若之前运行注入过 "// >>> lbar-binds >>>" 块需手动删除。

## 55. 通用 wayland 平台层
core/wm/{hyprland,sway,niri}.lua 各实现 detect() + register_binds(ctx,config,cli,log)；core/keybinds.lua 只分发给首个检测到的平台——平台特定逻辑收敛到各自模块。

## 56. hyprland 快捷键修复（两个根因）
### (a) SCRIPT_DIR 为相对路径
绑定 spawn "./lbar-cli" 时 compositor 无法解析（其 cwd 不同）；lbar.lua 启动时从 $PWD 绝对化 SCRIPT_DIR。
### (b) hyprctl eval 依赖 Lua 配置提供器
hyprland.lua 在 eval 失败时回退到 "hyprctl keyword bind MODS,key,exec,cmd"（两条路径均先 unbind）。

## 57. wayland 文本输入可打字
backends.c 实现 wl_keyboard：规范的 wl_seat capabilities 监听、按能力绑定键盘、keymap fd mmap 进 xkbcommon 状态、wl_keyboard.key 推送 ev5 target=1（evdev+8 键码 + X11 兼容的按下修饰掩码 xkb_state_serialize_mods）、修饰键更新 xkb_state_mask；lbar_key_lookup 增加 wayland 分支（xkb_state_key_get_one_sym + get_utf8，与 X11 相同的 keysym 数字与文本），Panel 的 key_translate/text_input 无需改动；Makefile 链接 xkbcommon。

## 58. niri 双击协议错误（bar 消失）
niri/smithay 对同尺寸层表面的 unmap→remap 不发送新 configure 但仍拒绝 attach——popup hide 现在销毁整个表面槽位（layer+surf+pool+buf），show 经 wl_popup_init 全新重建；全新层表面总会收到初始 configure，在 niri/hyprland/sway 上由协议保证，而不再依赖各 compositor 的 remap 怪癖。

## 59. 编译告警清理
ipc_init（backends.c）与 lbar-cli.c 中 strncpy 改为带钳制的显式 memcpy；lbar.so/lbar-cli 以 -Wall -Wextra 编译无告警。

## 60. wl_seat capabilities 竞态
capabilities 由 compositor 在 bind 时立即发送——而 seat 监听器在 registry roundtrip 之后才安装，事件被丢弃，seat_caps 从未运行，wayland 上既无指针也无键盘（面板可见但不可点击、不能输入）；seat 监听器现移入 wl_registry_global 中紧接 wl_seat bind 之后添加，capabilities 总能被捕获。

## 61. cpu/mem bar 项美化（配置项）
config 提供 cpu.style/mem.style 'text'|'graph'|'both'、interval_ms、cpu.history spark 采样、颜色：cpu 在百分比文本旁绘制彩色 sparkline 历史，mem 绘制进度胶囊；两项点击均打开 sysmon 面板。

## 62. 设置面板
plugins/settings.lua，ctrl+alt+j，bar "set"：主题选择 chips 覆盖全部 14 套内置配色（按 dark/light 分组，即时生效并持久化 theme/theme_light）、字号 -/+（持久化 font_size 并热重载字体）、auto-reload 与 debug 开关（ctx.auto_reload 自 lbar.lua 暴露）、reload/关闭面板/quit 按钮；持久化经新的 ctx.config_path + 可复用的原地 gsub save_field（键匹配替换，否则在末尾 } 前插入）。

## 63. 壁纸面板
plugins/wallpaper.lua，ctrl+alt+p，bar "wall"：扫描 config.wallpaper.dir（find，depth 可选，图片扩展名），prev/next/random/refresh 工具栏，点击行设置（✓ 标记当前），自动探测 setter 顺序 swww-daemon > swaybg(SWAYSOCK) > hyprpaper(HYPRLAND_*) 附带命令回退，或 config.wallpaper.set_cmd 用 $f 占位符；hyprpaper 路径预载新图并卸载上一张；底栏显示文件数与探测到的工具。

## 64. WiFi 面板
plugins/wifi.lua，ctrl+alt+n，top_right：基于 nmcli——状态卡（ssid、信号格、iface、ip）、WiFi 开关、断开、重扫描（延迟列表刷新）、转义感知的 -g 解析（nmcli 将 SSID 中的 ':' 转义为 '\:'）、点击连接（开放网络直连，加密网络在底栏文本框询问密码）；bar 项显示 ssid + 按强度着色的信号%；config.wifi {interface, refresh_sec}。

## 65. 电源菜单
plugins/power.lua，ctrl+alt+o：lock/logout/sleep/reboot/shutdown 网格按钮带确认底栏（config.power.confirm，lock 总是立即执行）；logout 自动探测会话（niri msg action quit / hyprctl dispatch exit / swaymsg exit，或 logout_cmd 选项）；lock_cmd 选项（默认 swaylock -f），suspend/reboot/poweroff 用 systemctl。

## 66. bar 项溢出修复
插件列表增长后 Bar:layout 把条目推出 bar 边缘（settings/wallpaper/wifi/power 追加在后 → "power bar 什么都看不到"）；layout 现先压缩间隙，再按比例收窄条目宽度，保证所有条目都在 bar 内。

## 67. 设置面板崩溃/bug 修复
破坏性操作（字号 -/+ 的 hot_reload、reload、quit）在 draw() 内调用会中途销毁面板 → flush 到 nil surf；全部改为 M.pending_action 在 M.tick 中延迟执行；分组标签真正绘制（m.labels）；主题应用不再重绘设置面板自身（避免重入）；保存后设置 ctx.skip_reload_once，让 auto-reload 监视器同步 mtime 而不是 reload_all 关闭面板。

## 68. 壁纸点击修复 + X11/i3 支持
swww img 前自动启动 swww-daemon（pgrep + 0.4s 等待）；os.execute 结果显式检查并以 error/success toast 报告 + 完整命令入日志；setter 探测顺序：set_cmd 选项 > swww-daemon 运行中 > swaybg(SWAYSOCK) > hyprpaper(HYPRLAND_*) > wayland+swww > feh > nitrogen > xwallpaper > swaybg > hyprctl（覆盖 i3/X11：feh --bg-fill、nitrogen --set-zoom-fill、xwallpaper --zoom）；扫描多个默认目录（~/Pictures、~/Pictures/wallpapers、~/wallpapers）；refresh 重置工具缓存。

## 69. WiFi 连接不再冻结 UI
nmcli 连接经后台子 shell 异步执行并将退出码写入临时文件，M.tick 轮询（45s 超时）后刷新状态/列表并 toast connected/failed/timeout；开放网络行点击直连，加密网络经底栏密码输入（Enter 或 ok 按钮）。

## 70. 弹窗槽位耗尽
LBAR_POPUP_MAX 16 而面板已有 17 个（第 18 个 = 懒创建的 toast）——Panel.new 对 "power" 静默返回 nil（bar 项点击无反应）、"toast" 同样（Toast:show 遇 nil 面板报错，中断设置面板当帧绘制 = 被点击 chip 下方的主题按钮消失）；上限提升到 32 且 toast 对 Panel.new 失败做了 nil 守卫。

## 71. settings.lua 重写
标签式 UI（themes / options / panels），ui:scrollbar 行，覆盖 config.lua 全部键（bar、fonts、paths、cpu、mem、network、wallpaper、power、launcher、pomodoro、clip_hist、weather、move/resize_window、panel_opts）；主题模式按钮 + 14 个调色板 chips 即时生效；每节的原地配置编辑器（tokenizer 跳过注释/字符串、括号深度作用域栈、值跨到深度 0 的逗号，处理被注释的键 + 缺失作用域时递归建表）；热键（position/height/fonts）触发 hot_reload，其余实时更新 ctx.config；保存设置 ctx.skip_reload_once。

## 72. 面板打开延迟优化
on_show/init 路径的 io.popen 阻塞主循环——wifi（每次打开 4 次 nmcli，100ms+）、launcher（每次打开都跑 dmenu_path 约 3000 项）、wallpaper（每次打开 find）、sysmon（ls /proc）；全部改为后台任务 + M.tick 轮询（tmpfile + DONE 标记）并缓存即时打开绘制；wifi 重扫描/刷新同样异步。

## 73. sysmon 与 system 插件合并（后者删除）
用 ffi opendir/readdir 读 /proc pids（不再 ls|grep popen）；面板增加 swap + loadavg + uptime 行，随采样读取。

## 74. 电池
多电池探测（BAT0-5/BATT/BATTERY，平均容量，30s 重探测），charging/Full 状态，2s 实时刷新，点击打开电源面板（Util.toggle_from_bar）。

## 75. 新音量插件
plugins/volume.lua，ctrl+alt+s：pactl 默认 sink 音量 bar 项（VOL N% / MUTE，无 pactl 时隐藏），滚轮 ±5，点击打开滑块面板（大号 % 标签、ui:slider、-/+ 按钮、mute 开关）；滑块拖动经 tick 中 150ms pending 定时器合并为一次 pactl 调用。

## 76. system.lua 删除
config.lua 更新：插件列表、快捷键 toggle_volume ctrl+alt+s 替换 toggle_system、panels volume 条目、panel_opts volume。

## 77. bar 项修复（settings "set" 与 volume "vol" 静默缺失等）
### (a) settings
size_fn 返回布局表而 Panel.new 解构 (w,h) → math.max(1, table) 初始化错误 → 插件被跳过。
### (b) volume
HAVE_PACTL 用 os.execute(...) == true 判断，但此 LuaJIT 返回原始退出状态（0），检查恒假导致插件自禁用。
### (c) sysmon
显示 "0 processes"——tonumber(ffi char[256] cdata) 恒为 nil，必须 ffi.string(e.d_name)；全部经 stub-ctx 初始化 harness 验证。

## 78. logo 恢复旧的 menu 行为
tux 点击打开应用信息弹窗（backend/screen/engine/font/插件数/uptime），带 Theme（actions.toggle_theme，持久化）、Reload（tick 中经 pending_action 延迟）与 Quit（延迟）按钮；破坏性操作绝不在 draw() 内执行。

## 79. bar 项偶发消失修复（"mon sometimes gone"）
热重载复用了 require 缓存的插件模块——陈旧的 M 引用指向已销毁面板导致重初始化失败，add_plugin 静默跳过插件；reload_all 现在重建前对每个插件丢弃 package.loaded，所有插件全新初始化，每个启用插件始终有 bar 项。

## 80. logo 弹窗锚定（android PopupWindow/MIUIX 风格）
ctx.show_panel/Panel:show_at/Util.toggle_from_bar 支持 align="left"，将弹窗左缘钉在锚定条目（钳 8px，位于 bar 下方）；logo 使用之——其他面板保持居中锚定。

## 81. 设置面板缩放自愈
do_draw 每帧将 m.W/m.H 同步到实际 surface，页脚与行裁剪始终匹配真实尺寸（ctrl+alt+shift 缩放后行不再与页脚编辑条重叠）；最小尺寸提高（缩放后 480x460，自然 H >= 520）保证文字放得下。

## 82. 可拖动弹窗 + i18n + fastfetch 风格 sysinfo
### (a) Panel 核心拖动
在头栏条带按下（关闭按钮除外）设置 _drag{sx,sy,mx0,my0}，on_motion 经 Panel:move_to 移动（lbar_popup_move = zwlr margins+commit，niri 上 compositor 安全；wayland 的 ev.root_* 为 0，增量改用 surface-local 坐标），on_release 清除并吞掉合成的 ui 点击；关闭按钮处理集中到 Panel:on_press（插件自身的 header_hit→hide 分支成为死代码但无害）；opts.draggable=false 可关闭。
### (b) core/i18n.lua
gettext 风格（英文源串为键）en/zh 表，config lang='auto'|'en'|'zh'（auto 取自 $LANG），I.t(key,...) 支持 string.format；lbar.lua 启动 + 重载时初始化；全部 18 个面板头、settings 标签/分组/行标签/toast、keybinds_help 分组均已翻译；settings Options 增加语言行（save_enum 实时重初始化 i18n + redraw_all，无需重载）。
### (c) sysinfo 重写
fastfetch 风格 macOS 分组列表——accent 圆点 + user@host 标题、左提示标签/右对齐值行、内嵌发丝分隔线；同步数据来自 procfs（os-release、version、cpuinfo cores+MHz、meminfo、uptime）+ 一个后台探测任务（uname -m、hostname -I、lspci GPU、dpkg/pacman/rpm 计数、df /）写入 /tmp/lbar-sysinfo-probe 并带 DONE 标记，tick 中轮询（400ms 累计，6s 超时），数据到达后重绘；经 /tmp/test_plugin_draw.lua stub harness 在 en+zh 验证绘制路径。

## 83. 时钟日程/闹钟
时钟面板增加日程区（最多 6 行按时间排序）+ 有待办条目的日期上的日历标记点；"add" 打开底栏输入条（esc/ok 按钮，Enter 提交，show 时不自动聚焦），接受 "YYYY-MM-DD HH:MM text"、"MM-DD HH:MM text"（今年，已过则明年）或 "HH:MM text"（今天，已过则明天）；条目逐行持久化到 clock.schedule_file（默认 $XDG_STATE_HOME/lbar/schedule.conf），add/× 删除（删除经 M.del_idx 延迟到 tick，绝不在 draw 中途执行）；M.tick（1s 节流）对到期条目触发一次性警告 toast "alarm: HH:MM text"（15s）——加载时已过期的条目标记为 fired（避免启动刷屏）；已 i18n（schedule/add/alarm toast，含 zh）；settings Options paths 组增加 schedule_file 行；docs/config.md 新增 ### clock 节；离线测试 /tmp/test_clock_sched.lua（21 项检查：解析变体含 roll-forward + 非法输入、save/load 往返、过期条目 fired 标记、tick 内闹钟只触发一次、延迟删除 + 文件重写）——抓到真实 bug：MM-DD 解析分支把 5 个 pattern 捕获赋给 6 个变量，导致 month/day/hour/min 错位且 txt 为 nil（所有 MM-DD 解析返回 nil）；同时为 tick 中的 P.visible 增加 nil 守卫（Panel.new 在槽位上限时可能静默返回 nil）。

## 84. 全量 i18n 覆盖 + 自动适配/响应式面板
### (a) 通用规则
I.t() 是全部 23 个插件中每个用户可见字符串（面板标题、行/按钮标签、状态、空态、toast、输入占位符）与 bar 项标签（BAT/CHG/LOW/CPU/MEM/mon/wall/Clip/Keys/Pick/pomo/♪ music/VOL/MUTE/wifi-*/wttr…）的唯一入口；M.width 用代表性值测量翻译后的文本，保证 zh 宽度正确；冲突经不同键化解（音乐 "prev track"/"next track" vs 壁纸 "prev"/"next"；sysinfo 行 "Processor" 保留 处理器 而 cpu bar 保持紧凑 "CPU"）。
### (b) zh 表扩充
core/i18n.lua zh 表扩至约 280 条（验证 262 处字面调用点），M._tables 暴露给工具。
### (c) 检查工具
tools/i18n_check.lua 扫描 plugins/+core/ 中的字面 I.t 键，报告 zh 缺失项（exit 1）；当前 0 缺失。
### (d) 自动适配
core/panel.lua Panel:fit() 重算 size_fn（钳到屏幕），对隐藏面板 resize、可见面板 live-resize，user_size 设置时 no-op（手动缩放优先）；调用点在 tick 中由廉价变更检查守卫：wifi+wallpaper（扫描批次应用）、launcher/clip_hist（过滤计数）、clock（日程增删经 M.need_fit）、music_player（播放列表长度）、sysmon（ncores_display）、sysinfo（行数/探测状态键）。
### (e) 响应式重排
每个面板绘制前自愈 m.W/m.H = p.w/p.h 并从实时 W/H 重推 view_h/VROWS/页脚/列（settings.lua 模式复制到全部 18 个面板插件；sysmon 将 CPU%/MEM% 列钳到 W，volume mute 标签右对齐重测，color_picker 底部锚定重推 BTN_Y/HEX_Y，keybinds_help 重钳滚动）；验证：所有触碰文件语法、tools/i18n_check.lua 干净、/tmp/test_plugin_draw.lua 对全部面板插件在 en 与 zh 下 init+draw+reflow(380x300, 860x960)（harness 增加 resize-reflow pass + 音频库 stub；bar 项经 /tmp/test_bar_items.lua en+zh），docs/config.md 增加 lang 行与 "Auto-fit and reactive resizing" 节。

## 85. 时钟时间选择器 + 内容驱动自动适配
### (a) 日期选择
点击日历日期选择（draw 填充 M.day_rects 矩形；Panel.new on_press 回调命中测试并设置 M.sel——选中日期渲染 surface_hi chip，今天保持 primary 圆圈）。
### (b) 添加流程
打开两行底栏（m.FOOT_ADD）：日期串 + 小时步进器（−/+ 在 0-23 回绕）+ ":" + 分钟步进器（−/+ 步进 5，0-59 回绕），随后描述输入 + esc/ok；未来日期上的过去时间被拒（"time already past" toast），今天上的过去时间滚动到明天（is_today_sel 比较 sel 与今天，而非 "是否点过日期"——start_add 总是将 sel 默认为今天）。
### (c) 自动适配
build_model 由实际日历行数（cal_rows_needed）、日程行数与添加状态计算自然 H；M.need_fit 由 M.tick 消费 → Panel:fit()（增删/月份导航/添加切换）；日历列铺满实时宽度（COL_W = (W - 2*PAD)/7），日程文本紧跟测量后的时间标签起排（原固定 66px 偏移曾与 "game dev" 重叠）；手动缩放时日程行钳到页脚上方空间。
### (d) 测试
/tmp/test_clock_picker.lua（点击选日 → adding 模式绘制 → 经真实 input on_submit 闭包提交，隔离的 /tmp 日程文件不动用户数据，zh+en）+ /tmp/test_plugin_draw.lua 时钟重排 en/zh——全部通过；docs/config.md ### clock 重写（选择器流程，文件仍可手编）。

## 86. power 合并进 battery 插件（task 20261008-123039）
plugins/power.lua 移除；plugins/battery.lua 承载会话面板——头部 电量，电池状态行（pct 文本 + 全宽进度胶囊，充电时 accent 色，warn/crit 阈值），Noctalia 风格会话卡行（lock/logout/sleep/reboot/poweroff，reboot/poweroff 用 crit 色），确认底栏保留（lock 立即执行）；选项 config.power → config.battery（回退读 config.power），panel_opts/panels 条目重命名，快捷键 ctrl+alt+o → toggle_battery；电池 bar 项不变（BAT/CHG/LOW 文本，2000ms 刷新）；经 /tmp/test_battery_draw.lua zh+en 冒烟；docs/config.md 增加 battery（session menu）节。

## 87. grim 截图修复（task 20261008-122659）
core/screenshot.lua wayland 分支——先 command -v grim 预检并给出明确 "grim not found in PATH" 错误；去掉脆弱的 `grim -g '0,0 WxH'` 几何参数（改全输出捕获；固定几何在多显示器/缩放下区域落在输出外时会失败）；stderr 捕获到 /tmp/lbar-grim.err 并在失败 toast/日志中呈现而非丢弃。

## 88. 工作区 bar 项（task 20261008-122619）
新插件 plugins/workspace.lua——hyprland（HYPRLAND_INSTANCE_SIGNATURE）显示活动工作区标签（WS 前缀经 i18n），sway 回退（SWAYSOCK），其他平台隐藏（宽度 0）；1000ms 经后台子 shell 异步轮询 → /tmp/lbar-ws.json + done 标记（5s 挂起守卫）；hyprland 从 `hyprctl -j activeworkspace` 解析 name/id，sway 取 "focused":true 之前的名称；左/右键点击切换工作区（hyprctl dispatch workspace e±1 / swaymsg next_on_output/prev_on_output）；i18n 键 WS→工作区；加入 config.plugins 的 logo 之后。

## 89. 紧凑 bar（task 20261008-123126，部分完成）
### (a) 间隙收紧
bar gap 默认 10→6（core/bar.lua），config.lua gap 10→4。
### (b) cpu/mem bar 项改为纯文本
sparkline + 胶囊图形代码与 style/history 选项移除（plugins/cpu.lua、plugins/mem.lua 重写；条目 padding 从 16/8 收紧到 8/4），config cpu/mem 节精简为 interval_ms+color，docs 已更新。
### (c) 进行中
settings 长值重叠 + zenity 风格自研文件对话框 → 进行中（后续独立条目，见第 90 条）。

## 90. 设置溢出 + 自研文件对话框（task 20261008-123126 收尾）
### (a) settings.lua Options 行
所有 str/num/list 值右对齐并经 Util.utf8_truncate 做 utf8 感知截断，fit_chars 预算从标签宽度量到 chevron，长字体路径不再与标签重叠（审计发现 settings 是唯一越界者；sysinfo/launcher/music/clock 已截断）；删除过时的 cpu/mem style+history 行，保留 interval_ms/color。
### (b) 新插件 plugins/file_dialog.lua
zenity 风格选择器纯面板内实现（无外部依赖）：M.open(ctx, {title, path, kind="dir"|"file"|"any", on_select})，懒创建面板经 ctx.show_panel 路由（无 bar 项/config 条目），异步 `ls -p` 子 shell → tmpfile + DONE 标记由 M.tick 收割（注意：ls -A 包含隐藏文件；纯 -p 给目录尾随 / 并隐藏 dotfile）；目录优先可滚动列表逐行截断，".." 上级，路径文本框（Enter/OK 提交），cancel/ESC，文件点击即选，目录点击导航+暂存，尾随 "/" 剥离，on_select 经 pcall 守卫，经 need_fit/Panel:fit() 自动适配。
### (c) 设置路径行接入
font_path、music dir、music state file、schedule file、wallpaper dir 打开对话框；fallback-fonts 列表行保持内联；保存复用 save_value/cfg_set 并 skip_reload_once 后重开设置；验证：i18n_check 272 键 0 缺失，/tmp/test_file_dialog.lua + /tmp/test_settings_draw.lua zh/en，测试不触碰真实 config.lua。

## 91. UI 更新和优化（task 20261008-132806）
### (a) 工作区/wifi 实时化
plugins/workspace.lua 重写：展示全部已占用工作区（升序，焦点 primary 色），500ms 后台轮询 `hyprctl -j workspaces` + `activeworkspace`（单 tmpfile W/A 分节），sway 回退 `swaymsg -t get_workspaces -r`（按 num 排序）；改为每次 tick 收割（原 1s 槽只收一次是迟钝根因），文本+焦点签名变化才重绘，点击切换后立即重取；纯数字名渲染为裸 id。plugins/wifi.lua：bar 状态（ssid/信号）从慢 rescan（8s/面板关 60s）分离出独立 ~2s 状态任务（复用缓存 `nmcli -g IN-USE,SIGNAL,SSID device wifi list`，不做 rescan），字符串变化才重绘；rescan 节奏不变。
### (b) 音乐播放器首次播放修复
根因：init 恢复了曲目索引但没有流，toggle_pause 直走 audio_toggle_pause，而 src/audio.c:133 在 `!g_music || !g_playing` 时是 no-op。修复：toggle_pause 在引擎既未播放也未暂停时经 play_idx 起播（cur==0 依次尝试状态文件曲目→第一首→info toast）；play_idx 成功后镜像 playing/paused/pos/dur 并 bar.needs_redraw；tick 空播放列表懒 rescan（落地后重匹配状态曲目，绝不自动播放）。
### (c) 文件对话框 UX 初版
行高 lh+14、全宽圆角 hover/选中高亮、目录 primary/文件 on_var、画文件夹/纸张形状图标；路径行独立 surface_hi chip + 居中 ".." 按钮、路径尾截断 "…/code/own/lbar"；统一 PAD=20/GAP=12、list_geo 绘制与键盘共享；键盘 Up/Down（滚动跟随）/Enter/ESC；修复 `parent_dir("/tmp")` 返回 nil 导致根目录无 ".." 按钮。
### (d) 设置面板安卓化
core/ui.lua UI:toggle 重写为 Material 胶囊开关（开=primary、关=outline 描边+surface_hi，滑钮开态/按压增大，任意 w≥h 自适应，(value,changed) 语义不变，注意 ui:toggle 在 core/ui.lua 而非 panel.lua）；settings.lua 行卡片化：radius 12 圆角卡、行高≥46px、行距 8px、分组间距 ~28px、控件右对齐距卡右缘内缩 14px；自然高 size_fn 按 tab 行数计算（上限屏高 85%），切 tab 置 need_fit 由 tick 调 Panel:fit。
### (e) i18n 全量扫盲
settings bar 图标硬编码 "set" → I.t("settings")（zh「设置」）、ok/(unset)/(empty) 走 I.t；keybinds_help desc 构模期 I.t 包裹（max_desc_w 按译文测量，config.lua 英文 desc 保持为 key）；core/i18n.lua 新增 31 个快捷键 desc zh；遍历 24 个 plugins/*.lua + 全部 core/*.lua 绘制路径确认无遗漏（键帽/符号/数据串除外）；i18n_check 282 键 0 缺失。
### (f) 中文输入支持
core/text_input.lua：TI:paste 异步化（wl-paste|xclip|xsel 后台子 shell → tmpfile + DONE 标记，TI:tick 收割；去尾换行、512 字节 UTF-8 边界安全截断、失焦丢弃挂起 paste）；preedit 光标处绘制。src/backends.c：手声明 zwp_text_input_manager_v3/zwp_text_input_v3（manager destroy=0/get_text_input=1；ti enable=1…commit=7；事件 enter=0…done=5，对照官方 xml 核实），seat_caps 即建 text input，preedit/commit 经 done 语义缓冲 → ev_push_text（lbar_ev_t.text[512]，core/init.lua cdef 同步，sizeof=556 对齐）；lbar.lua 消费 type6 commit / type7 preedit；Panel:_kbd_sync/_finish_hide 调 lbar_ti_enable/disable + lbar_ti_set_cursor；无 manager 全 no-op，X11 记 "no IME support"。make lbar.so 干净；/tmp/test_text_paste.lua 16/16（含真机 ctrl+v）。

## 92. 音乐播放模式 + 遗留 bug 修复（task 20261008-134414）
### (a) 音乐播放器播放模式切换
四种模式 seq（顺序，默认）/loop（列表循环）/single（单曲）/shuffle（随机，>1 首不重复），传输行新增第 6 个模式按钮（字形 →/∞/①/⇄，fontconfig 核实 Noto fallback 覆盖；↻⟳ 不覆盖弃用），点击循环切换 + toast + 持久化 music.conf（缺 key 回退 seq）；曲终检测用 audio_finished() 一次性边沿（读后清 g_playing，天然防重复）→ on_track_end 按模式自动切歌，seq 队尾停止并镜像引擎状态，空闲绝不自动开播。
### (b) 文件对话框二次点击 + zenity 优先
修复：GTK 风格首次点击选中、点击已选中行即激活（打开目录/确认选择），连按两次即选中+激活，无时序逻辑。zenity 在 PATH 时优先：`( zenity --file-selection [--directory] --title … --filename … > out; echo $? > done ) &` 异步启动，M.tick 收割（exit 0 且非空 → pcall on_select；exit 1 取消无动作），command -v 结果缓存一次；zenity 缺失回退内置面板；M.open(ctx,{title,path,kind,on_select}) API 不变（主循环只 tick 已注册 panel，懒面板仍创建作隐藏 tick 宿主）。
### (c) 工作区点击切换
后端检测加入 niri（NIRI_SOCKET 优先，`niri msg --json workspaces` 按 is_occupied/is_active/idx 解析，idx 即 focus-workspace 参数），hyprland/sway 保留；draw 记录每个数字相对 item 的 x 命中区间，on_click(ctx,btn,lx,…) 把 lx 映射到对应 workspace 并异步派发（niri `focus-workspace N` / `hyprctl dispatch workspace N` / `swaymsg workspace number N`，全部 `&` 后台）；点击焦点数字/标签/间隙无操作，移除原循环切换。

## 93. 取色/工作区点击修复 + clock 日程编辑（task 20261008-134414 追加）
### (a) grim 取色修复
plugins/color_picker.lua 根因：capture_wayland 期望 P6 PPM 裸 RGB，但 grim 默认输出 PNG → 首字节校验失败 → "screen capture failed (install grim)" 误报（grim 实际已装）。修复：`grim -t ppm`；同时缩放感知采样——capture 记录 sx/sy（fractional scaling 1.25 下图像 2560x1600 vs 逻辑 2048x1280），pixel_at 把逻辑坐标映射进图像空间再索引。
### (b) Hyprland Lua 提供器 dispatch 兼容（workspace 数字点击修复）
根因：本机 Hyprland 用 Lua 配置提供器，`hyprctl dispatch workspace N` 把参数拼成 `hl.dispatch(workspace 1)` → Lua 语法错误静默失败（rc=7 被 >/dev/null 吞掉），点击数字后派发无效。实测确认的正确形态：`hl.dispatch(hl.dsp.focus({ workspace = N }))`（真机切换 ws2/ws1 验证）。新增 core/wm/hyprland.lua `M.dispatch_cmd(lua_expr, classic_args)`——`hyprctl eval '...' || hyprctl dispatch <classic>` 链，两种配置提供器通吃；plugins/workspace.lua focus_ws 接入。
### (c) 同根因修复其它 hyprctl dispatch 调用点
move_window：togglefloating → `hl.dispatch(hl.dsp.window.float())`（实测无参调用切换浮动）、moveactive → `hl.dsp.window.move({ x, y })`；resize_window：resizeactive → `hl.dsp.window.resize({ x, y })`（平铺窗口下效果未确证，链式回退兜底）；battery logout：exit → `hl.dsp.exit()`。均经 dispatch_cmd 双路径兼容。
### (d) clock 日程编辑
点击日程行进入预填表单（M.edit_idx，nil = 新建），提交就地更新该条目（保持文件位置/身份）；编辑行中途消失回退新建；过去条目未改动时间则保留原时间；"updated" toast + "click a schedule to edit" 提示；M.row_rects draw 填充 + Panel on_press 命中（day_rects 同款模式）。
### (e) clock 界面加大
PAD 20→24、COL_W lh+26→lh+34、ROW_H lh+10→lh+16、SCHED_GAP lh+16（日程行距独立）、FOOT_H lh+30→lh+40；自然高 size_fn 同步，Panel:fit 自适应。
### 验证
i18n 286 键 0 缺失；全部 Lua 语法通过；workspace 切换/float 切换实机验证；任务文件夹 20261008-134414 清理。

---

## 94. 设置 miuix 风格/脱层修复 + 文件对话框重做 + 文本输入多行 + wifi/music 修缮

### (a) sysmon 热重载崩溃
`attempt to redefine 'dirent'`：ffi.cdef 全局符号在插件热重载重跑时报重定义 → plugins/sysmon.lua 的 cdef 块包 pcall（签名未变，忽略重复定义）。
### (b) 设置面板脱层修复 + miuix 风格（plugins/settings.lua）
根因：滚动行可见窗口允许部分滚出行画进 tab 条带，顶部无遮挡、底部有 p.bg 遮挡 → 下滑时卡片叠盖 tab 标签。修复：绘制顺序反转——内容/scrollbar 先画，header、tab 带、页脚最后以不透明 theme.bg 覆盖，滚动内容被固定 chrome 自然裁剪到 [tab 条底, 页脚顶]。miuix 改造：tab 条改分段控件（surface_hi pill 容器 + bg 活动段 + primary 活动文字），卡片 radius 14、行高 max(46, lh+28)、行距 8、组间距 28 + hint 色组标题，页脚 pill 按钮（close=filled 主操作）。功能全保留（语言 save_enum 特判、Options 编辑弹窗、Panels 位置/外部关闭、pending_action 延迟、skip_reload_once）。
### (c) 文件对话框重做（plugins/file_dialog.lua）
优先级 zenity → pcmanfm → 自研：pcmanfm 1.x 实测无 stdout 选区能力（help 探测缓存，快速失败 log 后落自研，未来有 --pick 构建只需补分支）。自研滚动 bug 根因：draw 内"保持键盘选区可见"吸附——收割后 sel 恒 1，滚轮下滑每帧被弹回 0；修复为 draw 只钳制范围、选区跟随仅在 on_key。UI 完全照 zenity 重做：顶部可编辑位置栏（".." + Enter 导航/确认）、扁平列表文件夹在前字母序 + 细分隔线、右对齐 Cancel/OK 页脚（文件夹 OK=进入，dir 模式无选中返回当前目录）；`f:read(0)` LuaJIT 判目录误报改 `test -d`。API（M.open/on_select/_state 测试钩子）不变，调用方 settings.lua 无需改。
### (d) 文本输入多行自动扩展（core/text_input.lua + core/panel.lua）
TextInput 新增换行布局：按内容宽度贪婪词边界折行（超长词硬断、\n 强制换行），视觉行超 1 时自动向下长高（上限 max_lines=8 可配），超出纵向滚动（光标跟随）；Up/Down 视觉行移动保持目标列，行首/行尾返回 false 落回宿主（launcher 列表导航不受影响）；preedit 光标处内联渲染按宽续行；鼠标点击/拖选按 (行,列) 命中。Panel:tick 检测 input:height() 变化 → _need_fit → 同 tick 尾部 Panel:fit()（绝不在 draw 中 resize）。修复 _rebuild_cache 后未失效 _lines 的缓存 bug。IME/异步粘贴/512 字节截断/X11 全不动，全部输入框自动生效。
### (e) wifi 美化 + 底部 margin（plugins/wifi.lua）
底部 BOT_MARGIN=16 页脚恒距底缘；密码输入行 radius 12 卡片垂直居中；网络行卡片化（radius 12、active/hover surface_hi）；信号改色阶 pill（≥70 primary、≥40 warn、弱 crit）+ 连接卡同款；列表加 "wifi networks"/"scanning…" 小节标题；compute_layout 重写收敛高度公式。异步 nmcli/解析/bar item 行为零改动。
### (f) music 模式图标图形化（plugins/music_player.lua）
模式按钮 →/∞/①/⇄ 字体缺字形 → draw_mode_icon 用 p:rect 16px 盒 2px 笔画拼画（seq 箭头/loop 断口圆环+箭头/single 圆环+竖条/shuffle 交叉箭头），theme.primary 上色；模式持久化与播放逻辑不动。
### 验证
8 个改动文件语法通过；i18n 290 键 0 缺失（新增 location→位置）；stub 测试全绿——settings 三 tab+大滚动、file_dialog 滚轮/zenity 收割/pcmanfm 回落、text_input 72 断言（换行/高度/导航/粘贴/preedit）、wifi+music 33 断言（转义 SSID/滚动/四模式点击+图标 rect 数）、music_mode 回归 42 断言。

---

## 95. 文本输入崩溃/自适应面板 + clock 安卓 Material 风格时间/日期选择器

### (a) 文本输入崩溃修复（core/text_input.lua）
用户粘贴长报错文本后 `wrap_range:181 arithmetic on nil` 崩溃（Panel:tick 未 pcall，错误直接杀死主循环）。根因：wrap_range / _rowcol_of / _pos_in_row / 选择绘制共 8 处 `_prefix_w[byte]` 前缀查找无守卫——无效 UTF-8（\xC3 lead 按 2 字节跳、\255/\128 单字节）或直接 `inp.value=` 绕过 setter 时，字节位置不在 prefix 表中返回 nil 参与减法。修复：全部 `(prefix[x] or 0)` 守卫；`set_rect` 对 nil w/h 容错；_rebuild_cache 增加 `_cache_val` 值戳，`_layout` 检测值变化强制重建（堵住直接赋值绕过 _dirty 的缓存盲区）；`_sync_h`/`extra_h` 对未初始化 _base_h/text_w 早退。
### (b) 安卓式少行展开 + 面板自适应（core/text_input.lua + core/panel.lua + 7 宿主插件）
max_lines 默认 8→3（安卓风格展开若干行，超出滚动）；新增 `TI:extra_h()` 返回输入框超出基准行的像素增量；`Panel:fit` 在 size_fn 结果上加 extra_h 使面板同步长高，`Panel:tick` 重排为 fit 先于 draw（先长高再绘制，杜绝截断/盖内容）。宿主适配：launcher/clip_hist/sysmon 内容下移 in_extra，music_player 列表下移 + VROWS 收缩，file_dialog 列表区收缩，settings 滚动视口收缩 + 页脚上移，wifi 页脚/密码卡上移 + 停放矩形加宽防幻影增长。/tmp/lbar_ti_fuzz.lua 4000 迭代（粘贴报错文本/CJK/无效字节/半字符 \xC3\x28/多行/宽度抖动/直接赋值/鼠标命中）0 错误。
### (c) clock 安卓 Material 风格时间/日期选择器（plugins/clock.lua + core/i18n.lua）
视图状态机 form/time/years：添加/编辑日程的 footer 时间行点击进入 Material 转盘——24h 双圈表盘（外圈 13-23+00、内圈 1-12，atan2 扇区命中 + 半径分圈，2px 矩形链指针、选中 primary 实心圆），选完小时自动切分钟盘（外圈 00-55 步进 5、内圈 6° 细分 1 分钟精度 + ±1 微调），HH/MM 数字读出 pill 可点切换阶段；头部 Material 日期选区（年份小字可点 ⇄ ±12 年 5×5 网格、大日期"周四 10月8日"）；OK/取消回 form（取消回退进入前时间）。build_model 按视图算自然高（表盘 DIAL_D=8×lh+28），footer 高度 = 基础 + p.input:height() 超出部分（配合 (b) 自适应），表盘命中 rect draw 填充 + Panel on_press 命中。日程业务逻辑（解析/持久化/到点触发/编辑身份/过去时间校验）与全部测试钩子原样保留。i18n 新增 "%s %s %d"（zh「周X M月D日」）。
### 验证
clock picker 离线测试（三视图绘制/年份往返/转盘 14→25→内圈细调 17→+1=18/提交 conf 断言/编辑原地更新/取消回退/长文本不越界）全过；ti 73 断言、fuzz 4000、settings/file_dialog/wifi_music 33/music_mode 42 全绿；i18n 295 键 0 缺失；全部改动文件语法通过。

---

## 96. miuix 全量风格迁移 + 多面板同显单焦点 + 面板隐藏 toggle + TextInput 安卓风编辑

### (a) 多面板同时展示 + 单焦点（lbar.lua + core/panel.lua + src/backends.c，X11/Wayland 双后端）
打破"同一时刻只有一个面板"的互斥模型：点击 bar item 打开面板不再关闭其它已开面板，多个面板并存、最后点击者获得焦点（active_panel）。焦点面板独占键盘/指针 grab（ctx.sync_kbd/sync_ptr_grab 是唯一 grab 所有者，_kbd_id/_ptr_id 判转移：A→B 转移、全部关闭释放）；X11 后端事件路由按 root 坐标命中（stale a=其它面板 id 时仍按 root 位置路由到正确面板），Wayland 按 ev.a 面板 id 路由；手势（header 拖拽、移动）对非焦点面板连续可用；toast 面板弹出绝不夺焦点；popup_visible 按多面板重算；ctrl+alt+d（hide_all_windows）从"一次性关闭全部"改为 toggle 藏/恢复（隐藏后再次触发恢复原面板，toast "panels hidden"/"panels shown"，无可恢复面板时提示），方便处理完窗口后再次回看内容。修复回归：_begin_show 补 ctx.sync_kbd 调用（面板打开即建立键盘 grab，不再需要先点击）。
### (b) TextInput 安卓风编辑美化（core/text_input.lua + core/i18n.lua）
长按 450ms 选词（含 CJK）并弹出浮动工具条；双击选词、三击全选；选区两端 + 光标 teardrop 拖拽手柄（外圈 surface + 内圆 primary + 2px 连接线，hit rect 20x18，拖动实时改 anchor/cursor）；浮动工具条（34px pill、bg_focus/surface_hi 底、◀▶ 原语三角形 + Select all/Copy/Cut/Paste 译文实测宽度，放上方无空间自动翻到下方）：全选/复制/剪切/粘贴/左右折叠移动光标；ctrl+a 后显示工具条，方向键导航隐藏；copy/cut/paste 成功 toast（"Copied"/"Cut to clipboard"/"Pasted"，空剪贴板未聚焦静默）。blur 清全部新状态，_emit_change 隐藏工具条；既有 IME/异步粘贴/512 截断/多行自适应零改动。
### (c) miuix 风格迁移至全部面板（12 个插件 + core/ui.lua/panel.lua）
统一规格：PAD=20、卡片 radius 14、行高 max(46, lh+28)、行距 8、组间距 28 + hint 色组标题、hover=surface_hover、tonal=surface_hi / filled=primary pill、ui:toggle 46x26 胶囊、tab 分段控件、页脚不透明带 + 1px outline 分隔 + pill 按钮、绘制顺序反转（内容先 chrome 后）实现天然裁剪、size_fn 自然高 85% 屏高上限、破坏性操作 pending + tick pcall。分四组完成：launcher/clip_hist（行卡片 + hover 高亮 + 行尾 × 删除 + 清空/删除 toast）；sysmon/sysinfo（CPU+迷你图合并卡 + 核心 chip 网格 + 进程卡片 + 确认对话框 tonal/filled + 刷新 pill + kill toast + sysinfo 改卡片分组）；music_player/volume/pomodoro（now-playing 大卡 + 6 pill transport + 队列徽标 + 首播/暂停/切歌 toast；volume hero 百分比卡 + 静音 toggle + muted/unmuted toast；pomodoro hero 倒计时 + 分段控件）；battery/weather/keybinds_help/move_window/resize_window（电源操作卡片行危险项 crit + 会话命令 toast；weather hero 卡 + 指标行；keybinds combo pill；move/resize 新增 miuix 操作面板——方向 pill 十字键 + step/mode 信息行 + reset pill，栏图标 Move/Resize，dispatch 逐行保留）。面板总数约 22（含 toast/懒面板 file_dialog）< LBAR_POPUP_MAX=32。
### (d) toast 反馈补齐（多插件 + i18n 新键）
关键操作全量 toast：面板藏/恢复、TI 复制/剪切/粘贴、music 首播/切歌/暂停恢复、volume 静音切换、battery 会话命令成功/失败、sysmon kill 成功/失败、clip_hist 删除/清空、launcher 启动、move/resize/reset/无窗口提示、pomodoro 计时启停。i18n 增至 339 键 0 缺失（新增 panels hidden/shown、no panels to show、Select all/Copy/Cut/Paste/Copied/Cut to clipboard/Pasted/Clipboard empty、entry deleted、kill failed: pid %d、playback started、now playing: %s、timer started/paused/reset、locking…/rebooting…/powering off…、Move/Resize、window moved/resized、panel size reset、move: %d px per press 等）。
### 验证
离线多面板 harness（fake L + step 队列）wayland 17 步 / x11 30 步 PASS（非互斥展示、焦点转移、kbd grab 转移、双后端事件路由、拖拽手势、toggle 藏/恢复循环 + toast 文案断言）；ti android 测试（工具条 6 按钮命中/长按选词/手柄拖拽/翻下/blur 清理/CJK）PASS；fuzz 4000 迭代 0 错误；clock picker 回归全过；4 组 miuix stub 测试（sysmon/sysinfo、3p 冒烟 23 项、move/resize/battery/weather/keybinds 23 项）全绿；i18n 339 键 0 缺失；30 个改动 Lua 文件语法通过。

---

## 迁移说明

本文件于 2026-10-08 由项目历史 TODO 日志（第 1–90 条，按时间从旧到新）迁移整理而成，原 TODO 文件已删除。
