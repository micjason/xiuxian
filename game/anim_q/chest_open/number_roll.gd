@tool
extends Node2D
## 收益数字滚动：roll_t 0→1 时，文字从 prefix+0 滚到 prefix+value（千分位）。由 chest_open 的 "open" 动画驱动。

@export var value: int = 33120:
	set(v):
		value = v
		_refresh()
@export var prefix: String = "+":
	set(v):
		prefix = v
		_refresh()
@export_range(0.0, 1.0) var roll_t: float = 1.0:
	set(v):
		roll_t = v
		_refresh()

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	var l := get_node_or_null("Pop/Num") as Label
	if l == null:
		return
	var s := str(absi(int(round(value * roll_t))))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	l.text = prefix + out
