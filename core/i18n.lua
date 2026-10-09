-- core/i18n.lua — lightweight i18n: en / zh string tables, gettext-style
-- lookup with English source strings as keys. Language comes from
-- config.lang ("auto" | "en" | "zh"); auto detects from $LANG.
--
-- Generic framework rules:
--   * I.t(key, ...) is the single entry point for EVERY user-visible
--     string — panel titles, row labels, buttons, statuses, toasts and
--     bar item labels alike. Keys are the exact English source strings;
--     missing keys fall back to the key itself, so lookups never break.
--   * Bar item labels stay compact in zh (bar width is tight).
--   * tools/i18n_check.lua verifies every literal I.t key has a zh entry.
local M = {}

M.lang = "en"

local tables = {}

tables.en = setmetatable({}, {
	__index = function(_, k)
		return k
	end,
})

-- explicit English for a key whose source string is a format pattern
tables.en["%s %s %d"] = "%s %s %d"

tables.zh = {
	-- ------------------------------------------------------- panel headers
	["System Info"] = "系统信息",
	["System Monitor"] = "系统监视器",
	["settings"] = "设置",
	["power"] = "电源",
	["battery"] = "电量",
	["wifi"] = "Wi-Fi",
	["Apps"] = "应用",
	["music player"] = "音乐播放器",
	["volume"] = "音量",
	["UI Components"] = "UI 组件",
	["UI demo"] = "UI 例子",
	["Clock"] = "时钟",
	["lbar"] = "lbar",
	["wallpaper"] = "壁纸",
	["Color Picker"] = "取色器",
	["Keybinds"] = "快捷键",
	["Weather"] = "天气",
	["clipboard history"] = "剪贴板历史",
	["Clipboard"] = "剪贴板",
	["Pomodoro"] = "番茄钟",

	-- ---------------------------------------------------------- common
	["ok"] = "确定",
	["cancel"] = "取消",
	["confirm"] = "确认",
	["close"] = "关闭",
	["kill"] = "结束",
	["clear"] = "清空",
	["none"] = "无",
	["scanning…"] = "扫描中…",
	["(none)"] = "（无）",
	["disconnected"] = "已断开",
	["pomodoro"] = "番茄钟",
	["time already past"] = "该时间已过去",
	["description"] = "事项描述",

	-- ------------------------------------------------------ sysinfo rows
	["Host"] = "主机",
	["OS"] = "操作系统",
	["Kernel"] = "内核",
	["Uptime"] = "运行时间",
	["Packages"] = "软件包",
	["Shell"] = "Shell",
	["Resolution"] = "分辨率",
	["DE/WM"] = "桌面/WM",
	["Locale"] = "区域",
	["Processor"] = "处理器",
	["CPU"] = "CPU",
	["GPU"] = "显卡",
	["Memory"] = "内存",
	["Disk"] = "磁盘",
	["Local IP"] = "本机 IP",
	["User"] = "用户",
	["live refresh · 2s"] = "实时刷新 · 2秒",
	["hardware"] = "硬件",

	-- ------------------------------------------------------ bar items
	["mon"] = "监控",
	["info"] = "信息",
	["wall"] = "壁纸",
	["Clip"] = "剪贴",
	["Keys"] = "按键",
	["Pick"] = "取色",
	["UI"] = "UI",
	["BAT"] = "电",
	["LOW"] = "低",
	["CHG"] = "充",
	["WS"] = "工作区",
	["MEM"] = "内",
	["pomo"] = "番茄",
	["♪ music"] = "♪ 音乐",
	["wifi ×"] = "Wi-Fi ×",
	["wifi -"] = "Wi-Fi —",
	["wttr…"] = "天气…",

	-- ------------------------------------------------------ cpu / mem bars
	-- ("CPU" kept compact on purpose; the sysinfo row uses "Processor")

	-- ------------------------------------------------------ sysmon panel
	["mem"] = "内存",
	["swap"] = "交换",
	["load"] = "负载",
	["uptime"] = "运行时间",
	["up %s"] = "已运行 %s",
	["%dd %dh"] = "%d天%d时",
	["%dh %dm"] = "%d时%d分",
	["%dd %dh %dm"] = "%d天%d时%d分",
	["%dm"] = "%d分",
	["PID"] = "PID",
	["NAME"] = "名称",
	["CPU%"] = "CPU%",
	["MEM%"] = "内存%",
	["kill %d %s?"] = "结束进程 %d %s？",
	["%d processes · ctrl+f search · ctrl+k kill"] = "%d 个进程 · ctrl+f 搜索 · ctrl+k 结束",
	["filter %d / %d · ctrl+f search · ctrl+k kill"] = "筛选 %d / %d · ctrl+f 搜索 · ctrl+k 结束",
	["ctrl+f search process or pid"] = "ctrl+f 搜索进程或 PID",
	["SIGTERM sent to pid %d"] = "已向进程 %d 发送 SIGTERM",
	["kill failed: pid %d"] = "结束进程 %d 失败",
	["cores"] = "核心",
	["memory"] = "内存",
	["processes"] = "进程",
	["refreshed"] = "已刷新",
	["procfs"] = "procfs",
	["procfs + probe"] = "procfs + 探测",

	-- -------------------------------------------------- music player panel
	["prev track"] = "上一首",
	["next track"] = "下一首",
	["-10s"] = "-10秒",
	["+10s"] = "+10秒",
	["play"] = "播放",
	["pause"] = "暂停",
	["queue"] = "队列",
	["vol"] = "音量",
	["ready"] = "就绪",
	["playing"] = "播放中",
	["paused"] = "已暂停",
	["stopped"] = "已停止",
	["no track selected"] = "未选择曲目",
	["ctrl+f search"] = "ctrl+f 搜索",
	["filter %d / %d"] = "筛选 %d / %d",
	["audio unavailable"] = "音频不可用",
	["sequential"] = "顺序播放",
	["loop"] = "循环播放",
	["single"] = "单曲",
	["shuffle"] = "随机播放",
	["play mode: %s"] = "播放模式：%s",
	["playback started"] = "开始播放",
	["now playing: %s"] = "正在播放：%s",

	-- ---------------------------------------------------------- wifi
	["wifi disabled"] = "Wi-Fi 已关闭",
	["enable wifi below"] = "在下方开启 Wi-Fi",
	["not connected"] = "未连接",
	["%s · no network"] = "%s · 无网络",
	["no wifi device"] = "无 Wi-Fi 设备",
	["wifi off"] = "关闭 Wi-Fi",
	["wifi on"] = "开启 Wi-Fi",
	["disconnect"] = "断开",
	["rescan"] = "重新扫描",
	["no networks — try rescan"] = "没有网络 — 请尝试重新扫描",
	["click network to connect · secured asks password"] = "点击网络连接 · 加密网络需输入密码",
	["wifi password"] = "Wi-Fi 密码",
	["connecting to %s…"] = "正在连接 %s…",
	["connected: %s"] = "已连接：%s",
	["connect failed: %s"] = "连接失败：%s",
	["connect timeout: %s"] = "连接超时：%s",

	-- ------------------------------------------------------ wallpaper
	["prev"] = "上一张",
	["next"] = "下一张",
	["random"] = "随机",
	["refresh"] = "刷新",
	["no images found in %s"] = "未在以下目录找到图片：%s",
	["set config.wallpaper.dir and hit refresh"] = "设置 config.wallpaper.dir 后点击刷新",
	["%d files · tool: %s · click to set"] = "%d 个文件 · 工具：%s · 点击设为壁纸",
	["no wallpaper tool found (swww/feh/nitrogen/...)"] = "未找到壁纸设置工具 (swww/feh/nitrogen/...)",
	["wallpaper: %s"] = "壁纸：%s",
	["set wallpaper failed (%s) — check lbar log"] = "设置壁纸失败 (%s) — 请查看 lbar 日志",

	-- ---------------------------------------------------------- clock
	["Su"] = "日",
	["Mo"] = "一",
	["Tu"] = "二",
	["We"] = "三",
	["Th"] = "四",
	["Fr"] = "五",
	["Sa"] = "六",
	["Mon"] = "周一",
	["Tue"] = "周二",
	["Wed"] = "周三",
	["Thu"] = "周四",
	["Fri"] = "周五",
	["Sat"] = "周六",
	["Sun"] = "周日",
	["Jan"] = "1月",
	["Feb"] = "2月",
	["Mar"] = "3月",
	["Apr"] = "4月",
	["May"] = "5月",
	["Jun"] = "6月",
	["Jul"] = "7月",
	["Aug"] = "8月",
	["Sep"] = "9月",
	["Oct"] = "10月",
	["Nov"] = "11月",
	["Dec"] = "12月",
	["%d-%02d"] = "%d年%02d月",
	["%s %s %d"] = "%s %s%d日", -- "Thu Oct 8" / "周四 10月8日"

	-- -------------------------------------------------------- weather
	["feels"] = "体感",
	["humidity"] = "湿度",
	["wind"] = "风",
	["storm"] = "雷",
	["snow"] = "雪",
	["rain"] = "雨",
	["fog"] = "雾",
	["cloud"] = "云",
	["clear"] = "晴",
	["waiting data"] = "等待数据",
	["just updated"] = "刚刚更新",
	["updated %d min ago"] = "%d 分钟前更新",
	["updated %d h ago"] = "%d 小时前更新",
	["unknown location"] = "未知位置",
	["fetching…"] = "获取中…",
	["manual city: %s"] = "手动指定城市：%s",
	["auto-locate, first fetch ~1-2s"] = "自动定位，首次获取约 1-2 秒",
	["parse failed"] = "解析失败",
	["weather fetch failed"] = "天气获取失败",
	["details"] = "详情",

	-- ------------------------------------------------------- launcher
	["no matching apps, press Enter to run as command"] = "没有匹配的应用，按回车作为命令运行",
	["configure apps in config.lua launcher.entries"] = "请在 config.lua 的 launcher.entries 中配置应用",
	["search apps…"] = "搜索应用…",
	["ran: %s"] = "已运行：%s",

	-- ----------------------------------------------------- clip history
	["clipboard is empty, go copy something"] = "剪贴板是空的，先去复制点什么吧",
	["no matching entries"] = "没有匹配的条目",
	["filter history"] = "筛选历史",
	["copied"] = "已复制",
	["copy failed"] = "复制失败",
	["clipboard history cleared"] = "剪贴板历史已清空",
	["entry deleted"] = "已删除条目",

	-- -------------------------------------------------------- ui demo
	["controls"] = "控件",
	["lists"] = "列表",
	["inventory"] = "清单",
	["buttons"] = "按钮",
	["Filled"] = "填充",
	["Tonal"] = "色调",
	["Text"] = "文本",
	["chip alpha"] = "胶囊 alpha",
	["chip beta"] = "胶囊 beta",
	["chip gamma"] = "胶囊 gamma",
	["chip: %s"] = "胶囊：%s",
	["slider  %.0f%%"] = "滑块  %.0f%%",
	["toggles"] = "开关",
	["bluetooth"] = "蓝牙",
	["do not disturb"] = "勿扰模式",
	["%s on"] = "%s 已开启",
	["%s off"] = "%s 已关闭",
	["text field  (click, then type)"] = "输入框（点击后输入）",
	["type here…"] = "在此输入…",
	["list"] = "列表",
	["item one - click me"] = "项目一 - 点击我",
	["item two - hover me"] = "项目二 - 悬停我",
	["item three - selected"] = "项目三 - 已选中",
	["selected: %s"] = "已选择：%s",
	["scrollbar  (drag the thumb)"] = "滚动条（拖动滑块）",
	["row alpha"] = "行 alpha",
	["row beta"] = "行 beta",
	["row gamma"] = "行 gamma",
	["row delta"] = "行 delta",
	["row epsilon"] = "行 epsilon",
	["row zeta"] = "行 zeta",
	["widgets"] = "部件",
	["buttons (filled / tonal / text) · chips · labels"] = "按钮（填充 / 色调 / 文本）· 胶囊 · 标签",
	["slider · progress · toggle · text field"] = "滑块 · 进度条 · 开关 · 输入框",
	["list · scrollbar · card · divider"] = "列表 · 滚动条 · 卡片 · 分隔线",
	["toast notifications · panel header · close"] = "通知气泡 · 面板标题栏 · 关闭",
	["panels  (keybind or click the bar item)"] = "面板（快捷键或点击栏图标）",
	["filled button clicked"] = "已点击填充按钮",
	["tonal button clicked"] = "已点击色调按钮",
	["text button clicked"] = "已点击文本按钮",

	-- ---------------------------------------------------- color picker
	["Copy"] = "复制",

	-- -------------------------------------------------- keybinds help
	["no keybinds in config.lua"] = "config.lua 中暂无快捷键",
	["%d keybinds · %d groups"] = "%d 个快捷键 · %d 组",

	-- ------------------------------------------------------- pomodoro
	["focus"] = "专注",
	["break"] = "休息",
	["start"] = "开始",
	["reset"] = "重置",
	["completed %d"] = "已完成 %d 个",
	["pomodoro #%d done, take a break"] = "番茄钟 #%d 完成，休息一下",
	["break over, next pomodoro"] = "休息结束，开始下一个番茄钟",
	["timer started"] = "计时开始",
	["timer paused"] = "计时已暂停",
	["timer reset"] = "计时已重置",

	-- --------------------------------------------------------- volume
	["VOL -"] = "音 -",
	["MUTE"] = "静音",
	["VOL %d%%"] = "音 %d%%",
	["mute"] = "静音",
	["muted"] = "已静音",
	["unmuted"] = "已取消静音",

	-- ---------------------------------------------------------- power
	["lock"] = "锁屏",
	["logout"] = "注销",
	["sleep"] = "睡眠",
	["reboot"] = "重启",
	["shut down"] = "关机",
	["confirm: %s?"] = "确认：%s？",
	["lock runs at once · others ask first"] = "锁屏立即执行 · 其他操作需确认",
	["logout: unsupported session"] = "注销：不支持的会话类型",
	["locking…"] = "锁屏中…",
	["logging out…"] = "注销中…",
	["suspending…"] = "睡眠中…",
	["rebooting…"] = "重启中…",
	["powering off…"] = "关机中…",
	["%s failed"] = "%s 失败",

	-- ----------------------------------------------------------- logo
	["backend"] = "后端",
	["screen"] = "屏幕",
	["engine"] = "引擎",
	["font"] = "字体",
	["plugins"] = "插件",
	["Theme"] = "主题",
	["Reload"] = "重载",
	["Quit"] = "退出",

	-- ------------------------------------------------------- hide all
	["closed %d panel(s)"] = "已关闭 %d 个面板",
	["no open panels"] = "没有打开的面板",
	["panels hidden"] = "面板已隐藏",
	["panels shown"] = "面板已恢复",
	["no panels to show"] = "没有可恢复的面板",

	-- ------------------------------------------------- text input tools
	["Select all"] = "全选",
	["Copy"] = "复制",
	["Cut"] = "剪切",
	["Paste"] = "粘贴",
	["Copied"] = "已复制",
	["Cut to clipboard"] = "已剪切",
	["Pasted"] = "已粘贴",
	["Clipboard empty"] = "剪贴板为空",

	-- -------------------------------------------------- settings panel
	["themes"] = "主题",
	["options"] = "选项",
	["panels"] = "面板",
	["mode"] = "模式",
	["dark mode"] = "深色模式",
	["light mode"] = "浅色模式",
	["dark themes"] = "深色主题",
	["light themes"] = "浅色主题",
	["bar"] = "栏",
	["fonts"] = "字体",
	["paths"] = "路径",
	["cpu item"] = "CPU 项",
	["mem item"] = "内存项",
	["network"] = "网络",
	["misc"] = "杂项",
	["launcher"] = "启动器",
	["position"] = "位置",
	["height"] = "高度",
	["padding"] = "内边距",
	["gap"] = "间距",
	["bar margin"] = "栏边距",
	["corner style"] = "圆角风格",
	["font path"] = "字体路径",
	["font size"] = "字体大小",
	["fallback fonts (;)"] = "回退字体 (;)",
	["music dir"] = "音乐目录",
	["music state file"] = "音乐状态文件",
	["style"] = "样式",
	["interval ms"] = "间隔 (毫秒)",
	["history"] = "历史样本",
	["color by load"] = "按负载着色",
	["interface"] = "网卡",
	["refresh sec"] = "刷新 (秒)",
	["dir"] = "目录",
	["depth"] = "扫描深度",
	["set cmd ($f)"] = "设置命令 ($f)",
	["lock cmd"] = "锁屏命令",
	["logout cmd"] = "注销命令",
	["confirm actions"] = "操作需确认",
	["use dmenu_path"] = "使用 dmenu_path",
	["work min"] = "工作时长 (分)",
	["break min"] = "休息时长 (分)",
	["clip max items"] = "剪贴板条数",
	["weather units"] = "天气单位",
	["weather refresh sec"] = "天气刷新 (秒)",
	["move step px"] = "移动步长 (px)",
	["move mode"] = "移动模式",
	["resize step px"] = "调整步长 (px)",
	["language"] = "语言",
	["schedule"] = "日程",
	["add"] = "添加",
	["no schedule"] = "暂无日程",
	["click a schedule to edit"] = "点击日程可编辑",
	["update"] = "更新",
	["updated"] = "已更新",
	["alarm: %s"] = "闹钟：%s",
	["invalid schedule format"] = "无法解析日程（示例：2026-10-09 07:30 内容）",
	["schedule file"] = "日程文件",
	["panel"] = "面板",
	["keep open"] = "外部点击保持",
	["edit %s"] = "编辑 %s",
	["click a value to edit · saved to config.lua"] = "点击数值编辑 · 保存至 config.lua",
	["reload"] = "重载",
	["new value"] = "新值",
	["(unset)"] = "(未设置)",
	["(empty)"] = "(空)",
	["not a number: %s"] = "不是数字：%s",
	["saved"] = "已保存",
	["saved — reload to apply"] = "已保存 — 重载后生效",
	["saved — reloading…"] = "已保存 — 重载中…",

	-- ------------------------------------------------------ file dialog
	["open file"] = "打开文件",
	["path"] = "路径",
	["location"] = "位置",
	["empty folder"] = "空文件夹",
	["parent folder"] = "上级目录",

	-- ---------------------------------------------------- common toasts
	["theme: %s"] = "主题：%s",
	["mode: %s"] = "模式：%s",
	["auto reload on"] = "自动重载已开启",
	["auto reload off"] = "自动重载已关闭",
	["config reloaded"] = "配置已重载",
	["font reloaded: %s"] = "字体已重载：%s",
	["font reload failed: %s"] = "字体重载失败：%s",
	["reload failed: %s"] = "重载失败：%s",

	-- ------------------------------- keybinds_help groups (config-provided)
	["system"] = "系统",
	["windows"] = "窗口",
	["other"] = "其他",

	-- -------------------------------- keybinds_help descs (config-provided)
	["keybind help (this panel)"] = "快捷键帮助（本面板）",
	["app launcher"] = "应用启动器",
	["screen color picker"] = "屏幕取色器",
	["pomodoro timer"] = "番茄钟计时器",
	["weather panel"] = "天气面板",
	["system info"] = "系统信息",
	["system monitor"] = "系统监视器",
	["ui component demo"] = "UI 组件演示",
	["clock panel"] = "时钟面板",
	["volume panel"] = "音量面板",
	["settings panel"] = "设置面板",
	["wallpaper picker"] = "壁纸选择器",
	["wifi networks"] = "Wi-Fi 网络",
	["battery + power menu"] = "电量与电源菜单",
	["toggle dark / light theme"] = "切换深色 / 浅色主题",
	["dump visible panel screenshot to /tmp"] = "将可见面板截图保存到 /tmp",
	["debug mode: toasts stay on screen"] = "调试模式：通知驻留屏幕",
	["full screen shot (panel/toast tagged) to ~/Pictures/lbar"] = "全屏截图（标记面板/通知）至 ~/Pictures/lbar",
	["hide / restore all panels"] = "隐藏 / 恢复所有面板",
	["move window left"] = "窗口左移",
	["move window right"] = "窗口右移",
	["move window up"] = "窗口上移",
	["move window down"] = "窗口下移",
	["window wider"] = "窗口加宽",
	["window narrower"] = "窗口收窄",
	["window taller"] = "窗口加高",
	["window shorter"] = "窗口缩短",
	["reset panel size and position"] = "重置面板大小和位置",
	["hot reload config and plugins"] = "热重载配置与插件",
	["toggle auto reload"] = "切换自动重载",
	["quit lbar"] = "退出 lbar",

	-- --------------------------------------- move_window / resize_window
	["Move"] = "移动",
	["Resize"] = "缩放",
	["move window"] = "移动窗口",
	["resize window"] = "调整窗口",
	["direction"] = "方向",
	["window moved"] = "窗口已移动",
	["window resized"] = "窗口已调整",
	["no window to move"] = "没有可移动的窗口",
	["no window to resize"] = "没有可调整的窗口",
	["panel size reset"] = "面板已重置",
	["no panel to reset"] = "没有可重置的面板",
	["reset panel"] = "重置面板",
	["move: %d px per press"] = "移动：每次 %d 像素",
	["resize: %d px per press"] = "调整：每次 %d 像素",
}

function M.detect()
	local l = os.getenv("LANG") or os.getenv("LC_ALL") or ""
	if l:find("^zh") then
		return "zh"
	end
	return "en"
end

function M.init(ctx)
	local lang = (ctx and ctx.config and ctx.config.lang) or "auto"
	if lang == "auto" then
		lang = M.detect()
	end
	if not tables[lang] then
		lang = "en"
	end
	M.lang = lang
	return lang
end

-- t("key", ...) — lookup with fallback to English, then the key itself;
-- extra args are passed through string.format
function M.t(key, ...)
	local b = tables[M.lang] or tables.en
	local s = b[key] or tables.en[key] or key
	if select("#", ...) > 0 then
		local ok, r = pcall(string.format, s, ...)
		if ok then
			return r
		end
	end
	return s
end

M.tr = M.t

-- exposed for tooling (tests + tools/i18n_check.lua); read-only use
M._tables = tables

return M
