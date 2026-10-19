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

# ---- 背景与表面（墨色底，青玉绿的深色表面） ----
const BG_ABYSS := Color("090c0e")
const INK := Color("07090b")
const SURFACE := Color(0.086, 0.129, 0.122, 0.92)  # 卡片 #16211F
const SURFACE_SOLID := Color("16211f")
const SURFACE_INNER := Color(0.047, 0.078, 0.074, 0.9)  # 内嵌区 #0C1413
const SURFACE_FOOTER := Color(0.04, 0.055, 0.053, 0.78)
const SURFACE_DOCK := Color(0.04, 0.05, 0.05, 0.94)
const SCRIM := Color(0.02, 0.03, 0.03, 0.72)

# ---- 边线 ----
const BORDER := Color(0.42, 0.5, 0.36, 0.7)
const BORDER_SUBTLE := Color(0.24, 0.34, 0.3, 0.85)
const BORDER_FAINT := Color(0.18, 0.24, 0.22, 0.7)

# ---- 品牌色：金 / 青玉 ----
const GOLD := Color("dbbd70")
const GOLD_HOVER := Color("eed48a")
const GOLD_PRESSED := Color("b39448")
const GOLD_BORDER := Color("856a2e")
const ON_GOLD := Color("1f1a0e")  # 金色按钮上的文字，对比度 9.5:1
const JADE := Color("add6b8")
const JADE_DEEP := Color("4f8069")
const JADE_FILL := Color("75ad85")

# ---- 文字 ----
const TEXT := Color("ede8d6")  # 主文字（象牙）
const TEXT_MUTED := Color("94a39c")  # 次要文字，在 SURFACE 上 6.3:1
const TEXT_DISABLED := Color("7b8984")

# ---- 语义色 ----
const SUCCESS := Color("7bd39a")
const WARNING := Color("e8b04e")
const DANGER := Color("ee7d70")  # 朱砂（深色底上提亮，保证 4.5:1）
const INFO := Color("86bde0")

# ---- 装备稀有度：凡 / 良 / 精 / 珍 / 绝 / 仙（白 绿 蓝 紫 橙 红） ----
const RARITY_NAMES: Array[String] = ["凡品", "良品", "精品", "珍品", "绝品", "仙品"]
const RARITY_COLORS: Array[Color] = [
	Color("bcc4bf"),
	Color("66c48a"),
	Color("62a7ea"),
	Color("b890f2"),
	Color("f2a24c"),
	Color("f26b5c"),
]

# ---- 五行（技能/Boss 属性标识，仅作点缀，不单独承载信息） ----
const ELEMENT_METAL := Color("e3e0cf")
const ELEMENT_WOOD := Color("78c78d")
const ELEMENT_WATER := Color("6fb4e6")
const ELEMENT_FIRE := Color("f27a58")
const ELEMENT_EARTH := Color("d1a35f")

# ---- 文字战报语义色（同时配符号，色觉障碍也能分辨） ----
const REPORT_DAMAGE_DEALT := Color("f2a24c")  # 我方造成伤害  「−」
const REPORT_DAMAGE_TAKEN := Color("ee7d70")  # 我方受到伤害  「−」
const REPORT_HEAL := Color("7bd39a")  # 治疗          「＋」
const REPORT_CRIT := Color("ffd36b")  # 暴击          「★」
const REPORT_BUFF := Color("86bde0")  # 增益状态      「▲」
const REPORT_DEBUFF := Color("b890f2")  # 减益/控制状态  「▼」
const REPORT_SYSTEM := Color("dbbd70")  # 回合标题、系统提示
const REPORT_MISS := Color("94a39c")  # 闪避/未命中

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


static func _luminance(color: Color) -> float:
	return 0.2126 * _channel(color.r) + 0.7152 * _channel(color.g) + 0.0722 * _channel(color.b)


static func _channel(value: float) -> float:
	return value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4)
