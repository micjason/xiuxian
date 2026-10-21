class_name UiTokens
extends RefCounted
## 游戏端设计令牌（唯一的颜色、字号、间距、圆角来源）。
## 画布宽度固定 1080（stretch = canvas_items + keep_width），基准高度 2340（≈ iPhone X / 主流安卓 19.5:9）；
## 更矮的屏（16:9）高度缩到 1920，更长的屏（20:9+）高度增加，多出来的高度全部给内容区。
## 代码里不要写死 1920 / 2340，用视口实际大小。换算（以 411dp 宽的常见 Android 手机为例）：1 画布像素 ≈ 0.38dp，
## 所以 40px 字 ≈ 15dp，32px ≈ 12dp，128px 的触控目标 ≈ 49dp。其他机型比例不同，按宽度等比缩放。
## 规则：业务脚本只引用这里的常量或 MainTheme 的主题变体，不再写 Color(...) 字面量。

## 基准画布（只用于窗口还没布局好时的兜底，实际尺寸永远以视口为准）。
const BASE_SIZE := Vector2(1080, 2340)

# ---- Q 版（明亮 Q 萌，2026-10-20 成鹏确认的设计稿 /workspace/q_design/）：奶油色卡片、可可色描边、橙色主按钮、薄荷绿次按钮 ----
# 原来的墨色主题已经换掉；常量名保留，调用方不用改。文字一律深色（可可棕），白字只用在带描边的标题上。
const Q_COCOA := Color("6b4a3a")  # 所有描边、标题字描边
const Q_CREAM := Color("fff8ec")  # 面板底
const Q_CARD := Color("fcebd0")  # 面板里的小卡片
const Q_CARD_LINE := Color("f4e4c9")
const Q_TRACK := Color("f1e2c6")  # 进度条底
const Q_SKY := Color("bce7e0")  # 页面底色（青绿）
const Q_SHEET := Color("9fd8ce")  # 修炼页下半截的薄荷色托盘
const Q_ORANGE := Color("ff9f43")
const Q_ORANGE_LIGHT := Color("ffc27a")
const Q_ORANGE_DARK := Color("e07b24")
const Q_MINT := Color("5cc9a7")
const Q_MINT_LIGHT := Color("86e3c6")
const Q_MINT_DARK := Color("3da383")
const Q_RED := Color("ff5a5f")
const Q_GOLD := Color("ffc94a")
const Q_TEAL_DARK := Color("1f8f84")
const Q_BLUE := Color("5aaeff")
const Q_BLUE_DARK := Color("2070b0")
const Q_GREY := Color("d9cfc4")
const Q_WHITE := Color("ffffff")

# ---- 背景与表面 ----
const BG_ABYSS := Q_SKY
const INK := Color("4a3a33")
const SURFACE := Color(1.0, 0.973, 0.925, 0.98)  # 卡片 #FFF8EC
const SURFACE_SOLID := Q_CREAM
const SURFACE_INNER := Color("fdf0da")  # 内嵌区
const SURFACE_FOOTER := Q_CARD_LINE
const SURFACE_DOCK := Color("f9e4c4")  # 底部页签栏
const SCRIM := Color(0.16, 0.11, 0.09, 0.55)

# ---- 边线 ----
const BORDER := Q_COCOA
const BORDER_SUBTLE := Color("b89a80")
const BORDER_FAINT := Color("e3d2ba")

# ---- 强调色（GOLD 系列现在是“橙棕色文字强调”，主按钮底色用 PRIMARY_*） ----
const GOLD := Color("a04a08")
const GOLD_HOVER := Color("8f4206")
const GOLD_PRESSED := Color("e07b24")
const GOLD_BORDER := Q_COCOA
const ON_GOLD := Color("3a2418")
const PRIMARY_FILL := Q_ORANGE
const PRIMARY_HOVER := Color("ffb060")
const PRIMARY_PRESSED := Color("f08a30")
const ON_PRIMARY := Color("3a2418")  # 橙色按钮上的深色字，对比度 7:1
const JADE := Color("1f7458")
const JADE_DEEP := Q_MINT_DARK
const JADE_FILL := Q_MINT

# ---- 文字 ----
const TEXT := Color("4a3a33")  # 主文字（深可可）
const TEXT_MUTED := Color("6e5a4e")  # 次要文字，在奶油卡片上 6.1:1
const TEXT_DISABLED := Color("9a8a80")
const TEXT_ON_DARK := Q_WHITE  # 带可可描边的白字（标题、按钮大字）

# ---- 语义色 ----
const SUCCESS := Color("257542")
const WARNING := Color("9a5306")
const DANGER := Color("be2c34")
const INFO := Color("24689f")

# ---- 装备稀有度：凡 / 良 / 精 / 珍 / 绝（白 绿 蓝 紫 橙，5 档；红已去掉）。COLORS 是文字色（奶油底上 ≥4.5），FILLS 是格子底色 ----
## 品质名字以服务器品质表为准（/content/current 的 globals.qualities，Catalog.apply 会覆盖这里）；这里只是拿到内容前的默认值。
static var RARITY_NAMES: Array[String] = ["凡品", "良品", "精品", "珍品", "绝品"]
const RARITY_COLORS: Array[Color] = [
	Color("646a76"),
	Color("257542"),
	Color("24689f"),
	Color("7440c8"),
	Color("9a5306"),
]
const RARITY_FILLS: Array[Color] = [
	Color("c9ced6"),
	Color("7ed36a"),
	Color("5aaeff"),
	Color("b57cff"),
	Color("ffa43a"),
]

# ---- 五行（技能/Boss 属性标识，仅作点缀，不单独承载信息） ----
const ELEMENT_METAL := Color("8a7c70")
const ELEMENT_WOOD := Color("3c9a4e")
const ELEMENT_WATER := Color("2e7fc4")
const ELEMENT_FIRE := Color("e0573a")
const ELEMENT_EARTH := Color("b07a2e")

# ---- 文字战报语义色（同时配符号，色觉障碍也能分辨） ----
const REPORT_DAMAGE_DEALT := Color("9a5306")  # 我方造成伤害  「−」
const REPORT_DAMAGE_TAKEN := Color("be2c34")  # 我方受到伤害  「−」
const REPORT_HEAL := Color("257542")  # 治疗          「＋」
const REPORT_CRIT := Color("8a5a00")  # 暴击          「★」
const REPORT_BUFF := Color("24689f")  # 增益状态      「▲」
const REPORT_DEBUFF := Color("7440c8")  # 减益/控制状态  「▼」
const REPORT_SYSTEM := Color("a04a08")  # 回合标题、系统提示
const REPORT_MISS := Color("6e5a4e")  # 闪避/未命中

# ---- 字号（画布像素；最小 32） ----
const FS_HUGE := 80  # 境界名
const FS_DISPLAY := 64  # 登录标题
const FS_VALUE := 72  # 修为等核心数值
const FS_H1 := 56  # 页面标题
const FS_H2 := 48  # 区块标题、关卡名
const FS_HERO := 52  # 大按钮
const FS_BODY_L := 44  # 重点正文
const FS_BODY := 40  # 正文、按钮
const FS_CAPTION := 36  # 说明
const FS_MICRO := 32  # 最小字号，不得再小

# ---- 间距（8px 基线） ----
const SP_1 := 8
const SP_2 := 16
const SP_3 := 24
const SP_4 := 32
const SP_5 := 48
const PAGE_MARGIN := 24  # 页面左右边距
const CARD_PADDING := 24

# ---- 圆角 ----
const R_SM := 12
const R_MD := 20
const R_LG := 32
const R_PILL := 999

# ---- 尺寸 ----
const H_TOUCH := 128  # 最小触控高度（≈49dp）
const H_CTA := 144  # 主操作按钮
const H_TAB := 160  # 底部页签
const H_BAR := 36  # 进度条
const H_HEADER := 112  # 顶部战力条区域
const TAP_GAP := 16  # 相邻可点控件最小间距


## WCAG 相对亮度对比度，供主题测试和调色使用。
static func contrast(foreground: Color, background: Color) -> float:
	var lf := _luminance(foreground)
	var lb := _luminance(background)
	var light := maxf(lf, lb)
	var dark := minf(lf, lb)
	return (light + 0.05) / (dark + 0.05)


static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


## 物品格子的底色（Q 版亮色）。
static func rarity_fill(rarity: int) -> Color:
	return RARITY_FILLS[clampi(rarity, 0, RARITY_FILLS.size() - 1)]


static func _luminance(color: Color) -> float:
	return 0.2126 * _channel(color.r) + 0.7152 * _channel(color.g) + 0.0722 * _channel(color.b)


static func _channel(value: float) -> float:
	return value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)
