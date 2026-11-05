class_name FogBattlePage
extends Control
## 异空间站桩战灰盒：播服务器 log；P0 仅 ×2 加速（无跳过）。

signal back_requested
signal finished(result: Dictionary)

var _result: Dictionary = {}
var _log: Array = []
var _idx := 0
var _clock := 0.0
var _speed := 1.0
var _playing := false
var _title: Label
var _feed: RichTextLabel
var _hp_me: Label
var _hp_enemy: Label
var _speed_btn: Button
var _done_btn: Button
var _me_hp := 1.0
var _enemy_hp := 1.0
var _me_max := 1.0
var _enemy_max := 1.0

func _ready() -> void:
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.14, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_title = Label.new()
	_title.position = Vector2(40, 40)
	_title.add_theme_font_size_override("font_size", 42)
	_title.text = "异空间"
	add_child(_title)

	_hp_me = Label.new()
	_hp_me.position = Vector2(40, 120)
	_hp_me.add_theme_font_size_override("font_size", 32)
	add_child(_hp_me)

	_hp_enemy = Label.new()
	_hp_enemy.position = Vector2(40, 170)
	_hp_enemy.add_theme_font_size_override("font_size", 32)
	add_child(_hp_enemy)

	_feed = RichTextLabel.new()
	_feed.position = Vector2(40, 260)
	_feed.size = Vector2(1000, 1200)
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	add_child(_feed)

	_speed_btn = Button.new()
	_speed_btn.text = "倍速 ×1"
	_speed_btn.position = Vector2(780, 2000)
	_speed_btn.custom_minimum_size = Vector2(200, 80)
	_speed_btn.pressed.connect(_toggle_speed)
	add_child(_speed_btn)

	_done_btn = Button.new()
	_done_btn.text = "回秘境"
	_done_btn.visible = false
	_done_btn.position = Vector2(520, 2000)
	_done_btn.custom_minimum_size = Vector2(200, 80)
	_done_btn.pressed.connect(func() -> void:
		finished.emit(_result)
		back_requested.emit()
	)
	add_child(_done_btn)


func open_battle(result: Dictionary) -> void:
	_result = result
	_log = result.get("log", []) if typeof(result.get("log", [])) == TYPE_ARRAY else []
	_idx = 0
	_clock = 0.0
	_playing = true
	_done_btn.visible = false
	_feed.clear()
	var mon: Dictionary = result.get("monster", {}) if typeof(result.get("monster", {})) == TYPE_DICTIONARY else {}
	var player: Dictionary = result.get("player", {}) if typeof(result.get("player", {})) == TYPE_DICTIONARY else {}
	_title.text = "异空间 · %s" % str(mon.get("name", "敌"))
	_me_max = float(player.get("hp", 1))
	_enemy_max = float(mon.get("hp", 1))
	_me_hp = _me_max
	_enemy_hp = _enemy_max
	_refresh_hp()
	_feed.append_text("站桩开战（服务器权威）\n")


func _toggle_speed() -> void:
	_speed = 2.0 if _speed < 1.5 else 1.0
	_speed_btn.text = "倍速 ×2" if _speed > 1.5 else "倍速 ×1"


func _process(delta: float) -> void:
	if not visible or not _playing:
		return
	_clock += delta * _speed
	while _idx < _log.size():
		var ev: Variant = _log[_idx]
		if typeof(ev) != TYPE_DICTIONARY:
			_idx += 1
			continue
		var e := ev as Dictionary
		var t := float(e.get("t", 0))
		if t > _clock:
			break
		_apply_event(e)
		_idx += 1
	if _idx >= _log.size() and _playing:
		_playing = false
		var win := bool(_result.get("win", false))
		_feed.append_text("\n%s\n" % ("胜利" if win else "败北"))
		var gained: Array = _result.get("gained", [])
		if not gained.is_empty():
			for g in gained:
				if typeof(g) == TYPE_DICTIONARY:
					_feed.append_text("掉落 %s×%d\n" % [str(g.get("displayName", "?")), int(g.get("quantity", 1))])
		_done_btn.visible = true


func _apply_event(e: Dictionary) -> void:
	var side := str(e.get("side", ""))
	var dmg := float(e.get("damage", 0))
	var after := float(e.get("targetHpAfter", 0))
	if side == "player":
		_enemy_hp = after
		_feed.append_text("[color=#9f9]我方造成 %.0f[/color]\n" % dmg)
	else:
		_me_hp = after
		_feed.append_text("[color=#f99]敌方造成 %.0f[/color]\n" % dmg)
	_refresh_hp()


func _refresh_hp() -> void:
	_hp_me.text = "我  %.0f / %.0f" % [_me_hp, _me_max]
	_hp_enemy.text = "敌  %.0f / %.0f" % [_enemy_hp, _enemy_max]
