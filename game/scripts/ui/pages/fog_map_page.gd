class_name FogMapPage
extends Control
## 迷雾秘境 P0 灰盒：扁格子 + 游历点 + 箱/怪收集 + 落地走 + 确认开战。
## 坐标 x 右 y 下；美术定妆前用色块。

signal back_requested
signal toast_requested(text: String, ok: bool)
signal battle_requested(payload: Dictionary)
signal busy_changed(busy: bool)

const CELL := 96.0
const ORIGIN := Vector2(48, 220)

var _view: Dictionary = {}
var _map_id := "fog_wenxin_valley"
var _grid: Control
var _hud_travel: Label
var _hud_chest: Label
var _hud_mon: Label
var _title: Label
var _busy := false
var _walk_tween: Tween
var _player_marker: Control
var _confirm: PanelContainer
var _confirm_label: Label
var _confirm_obj: Dictionary = {}
var _event_panel: PanelContainer
var _pending_battle: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var top := HBoxContainer.new()
	top.name = "FogTop"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 24
	top.offset_bottom = 120
	top.add_theme_constant_override("separation", 16)
	add_child(top)

	var back := Button.new()
	back.name = "FogBack"
	back.text = "返回"
	back.custom_minimum_size = Vector2(140, 72)
	back.pressed.connect(func() -> void: back_requested.emit())
	top.add_child(back)

	_title = Label.new()
	_title.name = "FogTitle"
	_title.text = "问心谷"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 40)
	top.add_child(_title)

	_hud_travel = Label.new()
	_hud_travel.name = "FogTravel"
	_hud_travel.text = "游历 0/20"
	_hud_travel.add_theme_font_size_override("font_size", 32)
	top.add_child(_hud_travel)

	_hud_chest = Label.new()
	_hud_chest.name = "FogChestCollect"
	_hud_chest.text = "箱 0/3"
	_hud_chest.add_theme_font_size_override("font_size", 32)
	top.add_child(_hud_chest)

	_hud_mon = Label.new()
	_hud_mon.name = "FogMonCollect"
	_hud_mon.text = "怪 0/3"
	_hud_mon.add_theme_font_size_override("font_size", 32)
	top.add_child(_hud_mon)

	_grid = Control.new()
	_grid.name = "FogGrid"
	_grid.position = ORIGIN
	add_child(_grid)

	_player_marker = ColorRect.new()
	_player_marker.name = "FogPlayer"
	_player_marker.color = Color(0.95, 0.85, 0.35, 1)
	_player_marker.size = Vector2(CELL * 0.55, CELL * 0.55)
	_player_marker.z_index = 5
	_grid.add_child(_player_marker)

	# 脚下影子
	var shadow := ColorRect.new()
	shadow.name = "FogShadow"
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.size = Vector2(CELL * 0.5, CELL * 0.18)
	shadow.position = Vector2(CELL * 0.025, CELL * 0.42)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_child(shadow)

	_build_confirm()
	_build_event_panel()


func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.name = "FogConfirm"
	_confirm.visible = false
	_confirm.z_index = 20
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.custom_minimum_size = Vector2(560, 240)
	add_child(_confirm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	_confirm.add_child(v)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.add_theme_font_size_override("font_size", 34)
	v.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(200, 72)
	cancel.pressed.connect(func() -> void: _confirm.visible = false; _confirm_obj = {})
	row.add_child(cancel)
	var ok := Button.new()
	ok.text = "开战"
	ok.custom_minimum_size = Vector2(200, 72)
	ok.pressed.connect(_on_confirm_fight)
	row.add_child(ok)


func _build_event_panel() -> void:
	_event_panel = PanelContainer.new()
	_event_panel.name = "FogEvent"
	_event_panel.visible = false
	_event_panel.z_index = 20
	_event_panel.set_anchors_preset(Control.PRESET_CENTER)
	_event_panel.custom_minimum_size = Vector2(640, 320)
	add_child(_event_panel)


func bind_fog(payload: Dictionary) -> void:
	_view = FogMapView.from_payload(payload)
	if _view.is_empty():
		return
	_map_id = str(_view.get("map_id", _map_id))
	_title.text = str(_view.get("name", "问心谷"))
	_hud_travel.text = "游历 %d/%d" % [int(_view.get("travel", 0)), int(_view.get("travel_max", 20))]
	_hud_chest.text = "箱 %d/%d" % [int(_view.get("chests_opened", 0)), int(_view.get("chests_total", 3))]
	_hud_mon.text = "怪 %d/%d" % [int(_view.get("monsters_defeated", 0)), int(_view.get("monsters_total", 3))]
	_rebuild_grid()
	_snap_player()


func map_id() -> String:
	return _map_id


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		if child == _player_marker:
			continue
		child.queue_free()
	var rows := int(_view.get("rows", 12))
	var cols := int(_view.get("cols", 8))
	for y in range(rows):
		for x in range(cols):
			var cell := Button.new()
			cell.name = "Cell_%d_%d" % [x, y]
			cell.position = Vector2(x * CELL, y * CELL)
			cell.size = Vector2(CELL - 4, CELL - 4)
			cell.focus_mode = Control.FOCUS_NONE
			var revealed := FogMapView.is_revealed(_view, x, y)
			var blocked := FogMapView.is_blocked(_view, x, y)
			if not revealed:
				cell.modulate = Color(0.35, 0.38, 0.45, 1)
				cell.text = "雾"
			elif blocked:
				cell.modulate = Color(0.45, 0.4, 0.35, 1)
				cell.text = "障"
			else:
				cell.modulate = Color(0.55, 0.72, 0.5, 1)
				cell.text = ""
			var xx := x
			var yy := y
			cell.pressed.connect(func() -> void: _on_cell(xx, yy))
			_grid.add_child(cell)
			_grid.move_child(cell, 0)
	# objects on top of cells
	for obj in _view.get("objects", []):
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var o := obj as Dictionary
		var ox := int(o.get("x", -1))
		var oy := int(o.get("y", -1))
		if not FogMapView.is_revealed(_view, ox, oy):
			continue
		var kind := str(o.get("kind", ""))
		var mark := Label.new()
		mark.position = Vector2(ox * CELL + 8, oy * CELL + 20)
		mark.add_theme_font_size_override("font_size", 28)
		mark.z_index = 3
		if kind == "chest":
			mark.text = "空箱" if bool(o.get("opened", false)) else "箱"
			mark.modulate = Color(1, 0.9, 0.3) if not bool(o.get("opened", false)) else Color(0.7, 0.7, 0.7)
		elif kind == "monster":
			if bool(o.get("defeated", false)):
				continue
			mark.text = str(o.get("name", "怪"))
			mark.modulate = Color(1, 0.45, 0.4)
		elif kind == "event":
			if bool(o.get("done", false)):
				continue
			mark.text = "?"
			mark.modulate = Color(0.6, 0.85, 1)
		else:
			continue
		_grid.add_child(mark)
	_grid.move_child(_player_marker, -1)


func _snap_player() -> void:
	var pos: Variant = _view.get("pos", {})
	if typeof(pos) != TYPE_DICTIONARY:
		return
	var x := int(pos.get("x", 0))
	var y := int(pos.get("y", 0))
	_player_marker.position = Vector2(x * CELL + CELL * 0.2, y * CELL + CELL * 0.15)


func _on_cell(x: int, y: int) -> void:
	if _busy:
		return
	var pos: Dictionary = _view.get("pos", {}) if typeof(_view.get("pos", {})) == TYPE_DICTIONARY else {}
	var px := int(pos.get("x", 0))
	var py := int(pos.get("y", 0))
	# object on this cell?
	for obj in _view.get("objects", []):
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var o := obj as Dictionary
		if int(o.get("x", -1)) != x or int(o.get("y", -1)) != y:
			continue
		if not FogMapView.is_revealed(_view, x, y):
			continue
		var kind := str(o.get("kind", ""))
		var manh: int = absi(x - px) + absi(y - py)
		if manh > 1:
			toast_requested.emit("先走到旁边", false)
			return
		if kind == "monster" and not bool(o.get("defeated", false)):
			_confirm_obj = o
			_confirm_label.text = "遭遇「%s」，确认进入异空间开战？" % str(o.get("name", "怪"))
			_confirm.visible = true
			return
		if kind == "chest" and not bool(o.get("opened", false)):
			_do_interact(str(o.get("id", "")))
			return
		if kind == "event" and not bool(o.get("done", false)):
			_show_event(o)
			return
	# move if adjacent walkable
	if abs(x - px) + abs(y - py) != 1:
		return
	if FogMapView.is_blocked(_view, x, y):
		toast_requested.emit("此路不通", false)
		return
	_do_move(x, y)


func _on_confirm_fight() -> void:
	_confirm.visible = false
	if _confirm_obj.is_empty():
		return
	var id := str(_confirm_obj.get("id", ""))
	_confirm_obj = {}
	_do_battle(id)


func _show_event(o: Dictionary) -> void:
	for c in _event_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_event_panel.add_child(v)
	var title := Label.new()
	title.text = str(o.get("title", "事件"))
	title.add_theme_font_size_override("font_size", 36)
	v.add_child(title)
	var opts: Array = o.get("options", [])
	if opts.is_empty():
		opts = [{"id": "A", "label": "上前理论"}, {"id": "B", "label": "转身离开"}]
	for opt in opts:
		if typeof(opt) != TYPE_DICTIONARY:
			continue
		var od := opt as Dictionary
		var b := Button.new()
		b.text = str(od.get("label", od.get("id", "?")))
		b.custom_minimum_size = Vector2(0, 72)
		var oid := str(od.get("id", ""))
		var effect := str(od.get("effect", "none"))
		b.pressed.connect(func() -> void:
			_event_panel.visible = false
			if effect == "battle" or oid == "A":
				_do_interact(str(o.get("id", "")), oid)
				_do_battle(str(o.get("id", "")))
			else:
				_do_interact(str(o.get("id", "")), oid)
		)
		v.add_child(b)
	_event_panel.visible = true


func _do_move(x: int, y: int) -> void:
	_set_busy(true)
	var result := await PlayerApi.post_action("/api/v1/me/fog/%s/move" % _map_id.uri_encode(), {"x": x, "y": y})
	_set_busy(false)
	if int(result.get("code", 0)) != 200:
		var msg := PlayerApi.error_message(result)
		if msg.is_empty():
			msg = "无法移动"
		toast_requested.emit(msg, false)
		return
	# 落地走 2～4 帧感：短 tween
	var target := Vector2(x * CELL + CELL * 0.2, y * CELL + CELL * 0.15)
	if _walk_tween:
		_walk_tween.kill()
	_walk_tween = create_tween()
	_walk_tween.tween_property(_player_marker, "position", target, 0.28)
	await _walk_tween.finished
	bind_fog(result)


func _do_interact(object_id: String, option_id: String = "") -> void:
	_set_busy(true)
	var body := {"objectId": object_id}
	if not option_id.is_empty():
		body["optionId"] = option_id
	var result := await PlayerApi.post_action("/api/v1/me/fog/%s/interact" % _map_id.uri_encode(), body)
	_set_busy(false)
	if int(result.get("code", 0)) != 200:
		toast_requested.emit(PlayerApi.error_message(result), false)
		return
	var gained: Array = result.get("gained", [])
	if not gained.is_empty():
		var parts: PackedStringArray = []
		for g in gained:
			if typeof(g) == TYPE_DICTIONARY:
				parts.append("%s×%d" % [str(g.get("displayName", g.get("itemSlug", "?"))), int(g.get("quantity", 1))])
		toast_requested.emit("获得 " + "、".join(parts), true)
	bind_fog(result)


func _do_battle(object_id: String) -> void:
	_set_busy(true)
	var result := await PlayerApi.post_action("/api/v1/me/fog/%s/battle" % _map_id.uri_encode(), {"objectId": object_id})
	_set_busy(false)
	if int(result.get("code", 0)) != 200:
		toast_requested.emit(PlayerApi.error_message(result), false)
		return
	# 把战斗包交给外壳播异空间（含 ×2）
	battle_requested.emit(result)
	# 回图时外壳会再 bind；此处先用回包装进度
	if result.has("fog"):
		bind_fog(result)


func _set_busy(v: bool) -> void:
	_busy = v
	busy_changed.emit(v)


func sheet_anchor() -> Control:
	return null
