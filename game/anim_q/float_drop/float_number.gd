@tool
extends Node2D
## 飘数字 / 滚动数字。
## 动画 "pop"：弹出→数字从 0 滚到 value→上飘→淡出；动画 "count"：原地滚动，结束时一下放大回弹（不飘不消失）。
## 用法：实例化后设置 value / unit / color_style，再 $AnimationPlayer.play("pop")。

@export var value: int = 33120:
	set(v):
		value = v
		_refresh()
@export var prefix: String = "+":
	set(v):
		prefix = v
		_refresh()
@export var unit: String = "修为":
	set(v):
		unit = v
		_refresh()
## 0 = 修为蓝（白字蓝描边）；1 = 金色（白字橙描边，可可色投影）
@export_enum("修为蓝", "金色") var color_style: int = 0:
	set(v):
		color_style = v
		_apply_style()
## 滚动进度 0→1，由动画驱动；1 = 显示完整 value
@export_range(0.0, 1.0) var roll_t: float = 1.0:
	set(v):
		roll_t = v
		_refresh()

const STYLES := [
	{"outline": Color("2e8fd8"), "shadow": Color("1f5f8f"), "unit": Color("2e7fc4")},
	{"outline": Color("e07b24"), "shadow": Color("6b4a3a"), "unit": Color("e07b24")},
]

func _ready() -> void:
	_apply_style()
	_refresh()

func _apply_style() -> void:
	var num := get_node_or_null("Pop/Row/Num") as Label
	var u := get_node_or_null("Pop/Row/Unit") as Label
	if num == null or u == null:
		return
	var s: Dictionary = STYLES[clampi(color_style, 0, 1)]
	num.label_settings = num.label_settings.duplicate()
	num.label_settings.outline_color = s.outline
	num.label_settings.shadow_color = s.shadow
	u.label_settings = u.label_settings.duplicate()
	u.label_settings.font_color = s.unit

func _refresh() -> void:
	var num := get_node_or_null("Pop/Row/Num") as Label
	var u := get_node_or_null("Pop/Row/Unit") as Label
	if num == null:
		return
	num.text = prefix + format_int(int(round(value * roll_t)))
	if u:
		u.text = unit
		u.visible = unit != ""
	var row := get_node_or_null("Pop/Row") as Control
	if row:
		row.reset_size()
		row.position = -row.get_combined_minimum_size() * 0.5

static func format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
