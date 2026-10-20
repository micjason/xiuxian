class_name BattleReport
extends RichTextLabel
## 文字战报控件：按事件类型着色，并且每类事件都带符号，不只靠颜色区分。
## 服务端给出战报行后，调用 add_round / add_line / add_result 追加即可。
## 战报数据协议还没有定，这里只负责呈现；当前主界面尚未接入。

enum Kind { PLAIN, DAMAGE_DEALT, DAMAGE_TAKEN, HEAL, CRIT, BUFF, DEBUFF, MISS, WIN, LOSE }

const SYMBOLS := {
	Kind.DAMAGE_DEALT: "−",
	Kind.DAMAGE_TAKEN: "−",
	Kind.HEAL: "＋",
	Kind.CRIT: "★ 大招 −",
	Kind.BUFF: "▲",
	Kind.DEBUFF: "▼",
	Kind.MISS: "○",
}


func _ready() -> void:
	bbcode_enabled = true
	scroll_active = true
	scroll_following = true
	selection_enabled = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_font_size_override("normal_font_size", UiTokens.FS_CAPTION)
	add_theme_font_size_override("bold_font_size", UiTokens.FS_CAPTION)
	add_theme_constant_override("line_separation", LINE_GAP)
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", empty)
	_snap_box = empty
	resized.connect(_snap_view_height)
	_snap_view_height.call_deferred()


const LINE_GAP := 10
var _snap_box: StyleBoxEmpty


## 让可视高度正好是整数行：多出来的零头放到底部的内边距里，这样跟随滚动时第一行不会被切掉一半（v8 验收意见）。
func line_pitch() -> float:
	var font := get_theme_font("normal_font")
	if font == null:
		return 0.0
	return font.get_height(UiTokens.FS_CAPTION) + float(LINE_GAP)


func _snap_view_height() -> void:
	if _snap_box == null:
		return
	var pitch := line_pitch()
	if pitch <= 1.0 or size.y <= pitch:
		_snap_box.content_margin_bottom = 0.0
		return
	_snap_box.content_margin_bottom = fmod(size.y, pitch)


func add_round(number: int) -> void:
	append_text(format_round(number) + "\n")


## amount 为 0 时只显示文字；不为 0 时在文字前加带符号、着色的数值。
func add_line(kind: Kind, text: String, amount: int = 0) -> void:
	append_text(format_line(kind, text, amount) + "\n")


func add_result(won: bool, text: String) -> void:
	append_text(format_line(Kind.WIN if won else Kind.LOSE, text, 0) + "\n")


static func format_round(number: int) -> String:
	return "[color=#%s][b]—— 第 %d 回合 ——[/b][/color]" % [UiTokens.REPORT_SYSTEM.to_html(false), number]


static func format_line(kind: Kind, text: String, amount: int = 0) -> String:
	var safe := escape(text)
	var color := color_of(kind)
	if kind == Kind.PLAIN:
		return safe
	if kind == Kind.WIN or kind == Kind.LOSE:
		return "[color=#%s][b]%s[/b][/color]" % [color.to_html(false), safe]
	var head := str(SYMBOLS.get(kind, ""))
	if amount != 0:
		head += _format_amount(amount)
	var bold := kind == Kind.CRIT
	var head_markup := "[color=#%s]%s[/color]" % [color.to_html(false), head]
	if bold:
		head_markup = "[b]%s[/b]" % head_markup
	if kind in [Kind.BUFF, Kind.DEBUFF, Kind.MISS] or amount == 0:
		return "%s [color=#%s]%s[/color]" % [head_markup, color.to_html(false), safe]
	return "%s %s" % [head_markup, safe]


static func color_of(kind: Kind) -> Color:
	match kind:
		Kind.DAMAGE_DEALT:
			return UiTokens.REPORT_DAMAGE_DEALT
		Kind.DAMAGE_TAKEN:
			return UiTokens.REPORT_DAMAGE_TAKEN
		Kind.HEAL:
			return UiTokens.REPORT_HEAL
		Kind.CRIT:
			return UiTokens.REPORT_CRIT
		Kind.BUFF:
			return UiTokens.REPORT_BUFF
		Kind.DEBUFF:
			return UiTokens.REPORT_DEBUFF
		Kind.MISS:
			return UiTokens.REPORT_MISS
		Kind.WIN:
			return UiTokens.SUCCESS
		Kind.LOSE:
			return UiTokens.DANGER
		_:
			return UiTokens.TEXT


## BBCode 里 [ 会被当成标签开头，名字里带方括号时要转义。
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _format_amount(amount: int) -> String:
	var value := absi(amount)
	if value >= 100_000_000:
		return "%.2f亿" % (float(value) / 100_000_000.0)
	if value >= 10_000:
		return "%.1f万" % (float(value) / 10_000.0)
	return str(value)
