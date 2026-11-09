class_name FogMapPage
extends Control
## 迷雾秘境 · 问心谷地图页定妆换皮（对照 fog_art_delivery B/G/C/D）。
## 坐标真源不变；不做 FogBattlePage 换皮。

signal back_requested
signal toast_requested(text: String, ok: bool)
signal battle_requested(payload: Dictionary)
signal busy_changed(busy: bool)
signal loot_received
signal route_idle

const CELL := 108.0
const GRID_PAD := Vector2(48, 200)
const WALK_SEC := 0.20  # D 规范 0.15～0.25s / 格
const WALK_FPS := 12.0

const COL_SKY := Color("CDEFEA")
const COL_CREAM := Color("FFF8EC")
const COL_PARCH := Color("E8D5B5")
const COL_BROWN := Color("6B4A3A")
const COL_ACCENT := Color("FF9F43")
const COL_GRASS := Color("7CB89A")
const COL_DEEP := Color("5A9E8A")
const COL_FOG_EDGE := Color("E8F0F5")
const COL_MINT := Color("5CC9A7")

const TEX_GRASS := "res://assets/art/fog/tiles/tile_grass.png"
const TEX_PATH := "res://assets/art/fog/tiles/tile_path.png"
const TEX_POND := "res://assets/art/fog/tiles/tile_pond.png"
const TEX_ROCK := "res://assets/art/fog/tiles/tile_rock.png"
const TEX_CLOUD := "res://assets/art/fog/fog/cloud_soft.png"
const TEX_CLOUD_SM := "res://assets/art/fog/fog/cloud_soft_sm.png"
const TEX_CHEST := "res://assets/art/fog/objects/chest.png"
const TEX_CHEST_DONE := "res://assets/art/fog/objects/chest_claimed.png"
const TEX_MONSTER := "res://assets/art/fog/objects/monster.png"
const TEX_EVENT := "res://assets/art/fog/objects/event.png"
const TEX_BLOCK := "res://assets/art/fog/objects/block_rock.png"
const TEX_TOPBAR := "res://assets/art/fog/ui/topbar.png"
const TEX_PANEL := "res://assets/art/fog/ui/panel_confirm.png"
const TEX_BANNER := "res://assets/art/fog/ui/banner_empty.png"

var _view: Dictionary = {}
var _map_id := "fog_wenxin_valley"
var _grid: Control
var _map_host: Control
var _hud_explore: Label
var _hud_travel: Label
var _hud_chest: Label
var _hud_mon: Label
var _title: Label
var _busy := false
var _walk_tween: Tween
var _player_marker: Control
var _player_sprite: TextureRect
var _player_shadow: ColorRect
var _confirm: PanelContainer
var _confirm_label: Label
var _confirm_obj: Dictionary = {}
var _event_panel: PanelContainer
var _empty_banner: Control
var _walk_dir := "down"
var _walk_playing := false
var _walk_frame := 0
var _walk_accum := 0.0
var _tex_cache: Dictionary = {}
# One request ledger survives route cancellation; never erase an uncertain step.
var transport: Callable
var _route_epoch := 0
var _route_target := Vector2i(-1,-1)
var _route_snapshot: Array = []
var _runner_running := false
var _pending_step: Dictionary = {}
var _step_token := ""
var _confirm_epoch := -1
var _confirm_action: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	FogLevelTiles.ensure_loaded()
	_build()
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): stop_route()
	)


func _process(delta: float) -> void:
	if not _walk_playing:
		return
	_walk_accum += delta
	var step := 1.0 / WALK_FPS
	while _walk_accum >= step:
		_walk_accum -= step
		_walk_frame = (_walk_frame % 4) + 1  # 1..4
		_apply_walk_frame("walk")


func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		var img := Image.new()
		var err := img.load(path)
		if err == OK:
			tex = ImageTexture.create_from_image(img)
	_tex_cache[path] = tex
	return tex


func _style_cream(radius: float = 24.0, border_w: float = 3.0, fill: Color = COL_CREAM) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = COL_BROWN
	s.set_border_width_all(int(border_w))
	s.set_corner_radius_all(int(radius))
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _build() -> void:
	# 页面青绿底（对照 G / B 系列）
	var bg := ColorRect.new()
	bg.name = "FogSky"
	bg.color = COL_SKY
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	_build_top_bar()
	_build_map_host()
	_build_player()
	_build_confirm()
	_build_event_panel()
	_build_empty_banner()
	_build_back()


func _build_top_bar() -> void:
	var top := PanelContainer.new()
	top.name = "FogTop"
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 20
	top.offset_right = -20
	top.offset_top = 28
	top.offset_bottom = 148
	var tex := _tex(TEX_TOPBAR)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		sb.content_margin_top = 12
		sb.content_margin_bottom = 12
		top.add_theme_stylebox_override("panel", sb)
	else:
		top.add_theme_stylebox_override("panel", _style_cream(22, 3, COL_PARCH))
	add_child(top)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	top.add_child(row)

	_title = Label.new()
	_title.name = "FogTitle"
	_title.text = "问心谷"
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", COL_BROWN)
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_title)

	var travel_pack: Dictionary = _make_collect_pill("FogTravelPill", "游历", "FogTravel")
	row.add_child(travel_pack["pill"])
	_hud_travel = travel_pack["label"] as Label

	var chest_pack: Dictionary = _make_collect_pill("FogChestPill", "箱", "FogChestCollect")
	row.add_child(chest_pack["pill"])
	_hud_chest = chest_pack["label"] as Label

	var mon_pack: Dictionary = _make_collect_pill("FogMonPill", "怪", "FogMonCollect")
	row.add_child(mon_pack["pill"])
	_hud_mon = mon_pack["label"] as Label
	_hud_explore = Label.new()
	_hud_explore.name = "FogExplore"
	_hud_explore.position = Vector2(36, 158)
	_hud_explore.add_theme_font_size_override("font_size", 28)
	_hud_explore.add_theme_color_override("font_color", COL_BROWN)
	_hud_explore.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_explore)


func _make_collect_pill(pill_name: String, prefix: String, label_name: String) -> Dictionary:
	var pill := PanelContainer.new()
	pill.name = pill_name
	pill.add_theme_stylebox_override("panel", _style_cream(999, 3, COL_CREAM))
	var h := HBoxContainer.new()
	h.name = "Row"
	h.add_theme_constant_override("separation", 8)
	pill.add_child(h)
	var tag := Label.new()
	tag.text = prefix
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", COL_BROWN)
	h.add_child(tag)
	var lab := Label.new()
	lab.name = label_name
	lab.text = "0/0"
	lab.add_theme_font_size_override("font_size", 30)
	lab.add_theme_color_override("font_color", COL_BROWN)
	h.add_child(lab)
	return {"pill": pill, "label": lab}


func _build_map_host() -> void:
	_map_host = Control.new()
	_map_host.name = "FogMapHost"
	_map_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_host.offset_top = 220
	_map_host.offset_bottom = -160
	_map_host.offset_left = 0
	_map_host.offset_right = 0
	_map_host.clip_contents = true
	add_child(_map_host)

	_grid = Control.new()
	_grid.name = "FogGrid"
	_grid.position = GRID_PAD
	_map_host.add_child(_grid)


func _build_player() -> void:
	_player_marker = Control.new()
	_player_marker.name = "FogPlayer"
	_player_marker.size = Vector2(CELL * 0.85, CELL * 0.95)
	_player_marker.z_index = 8
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(_player_marker)

	_player_shadow = ColorRect.new()
	_player_shadow.name = "FogShadow"
	_player_shadow.color = Color(0, 0, 0, 0.28)
	_player_shadow.size = Vector2(CELL * 0.42, CELL * 0.14)
	_player_shadow.position = Vector2(CELL * 0.22, CELL * 0.78)
	_player_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_child(_player_shadow)

	_player_sprite = TextureRect.new()
	_player_sprite.name = "FogPlayerSprite"
	_player_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_sprite.size = Vector2(CELL * 0.78, CELL * 0.78)
	_player_sprite.position = Vector2(CELL * 0.04, CELL * 0.02)
	_player_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_child(_player_sprite)
	_apply_walk_frame("idle")


func _walk_tex(dir: String, frame: String) -> Texture2D:
	return _tex("res://assets/art/fog/walk/%s_%s.png" % [dir, frame])


func _apply_walk_frame(mode: String) -> void:
	var frame := "idle"
	if mode == "walk":
		frame = str(_walk_frame)
	var t := _walk_tex(_walk_dir, frame)
	if t == null and _walk_dir != "down":
		t = _walk_tex("down", frame)
	if t == null:
		t = _walk_tex("down", "idle")
	_player_sprite.texture = t
	# 落地感：走帧时影子略压扁脉动
	if mode == "walk":
		var pulse := 1.0 + 0.08 * sin(float(_walk_frame) * 1.2)
		_player_shadow.scale = Vector2(pulse, 0.85)
	else:
		_player_shadow.scale = Vector2.ONE


func _start_walk_anim(dx: int, dy: int) -> void:
	if dx > 0:
		_walk_dir = "right"
	elif dx < 0:
		_walk_dir = "left"
	elif dy < 0:
		_walk_dir = "up"
	else:
		_walk_dir = "down"
	_walk_frame = 1
	_walk_accum = 0.0
	_walk_playing = true
	_apply_walk_frame("walk")


func _stop_walk_anim() -> void:
	_walk_playing = false
	_walk_frame = 0
	_apply_walk_frame("idle")


func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.name = "FogConfirm"
	_confirm.visible = false
	_confirm.z_index = 30
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.custom_minimum_size = Vector2(640, 280)
	_confirm.offset_left = -320
	_confirm.offset_right = 320
	_confirm.offset_top = -140
	_confirm.offset_bottom = 140
	var tex := _tex(TEX_PANEL)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.content_margin_left = 36
		sb.content_margin_right = 36
		sb.content_margin_top = 28
		sb.content_margin_bottom = 28
		_confirm.add_theme_stylebox_override("panel", sb)
	else:
		var s := _style_cream(28, 4, COL_CREAM)
		s.border_color = Color("C9A85A")
		_confirm.add_theme_stylebox_override("panel", s)
	add_child(_confirm)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	_confirm.add_child(v)
	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.add_theme_font_size_override("font_size", 34)
	_confirm_label.add_theme_color_override("font_color", COL_BROWN)
	v.add_child(_confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(220, 76)
	_skin_btn(cancel, false)
	cancel.pressed.connect(stop_route)
	row.add_child(cancel)
	var ok := Button.new()
	_confirm_action = ok
	ok.text = "开战"
	ok.custom_minimum_size = Vector2(220, 76)
	_skin_btn(ok, true)
	ok.pressed.connect(_on_confirm_fight)
	row.add_child(ok)


func _skin_btn(b: Button, primary: bool) -> void:
	var fill := COL_ACCENT if primary else COL_PARCH
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = COL_BROWN
	s.set_border_width_all(3)
	s.set_corner_radius_all(18)
	b.add_theme_stylebox_override("normal", s)
	var s2 := s.duplicate() as StyleBoxFlat
	s2.bg_color = fill.lightened(0.08)
	b.add_theme_stylebox_override("hover", s2)
	var s3 := s.duplicate() as StyleBoxFlat
	s3.bg_color = fill.darkened(0.08)
	b.add_theme_stylebox_override("pressed", s3)
	b.add_theme_color_override("font_color", COL_BROWN)
	b.add_theme_font_size_override("font_size", 32)


func _build_event_panel() -> void:
	_event_panel = PanelContainer.new()
	_event_panel.name = "FogEvent"
	_event_panel.visible = false
	_event_panel.z_index = 30
	_event_panel.set_anchors_preset(Control.PRESET_CENTER)
	_event_panel.custom_minimum_size = Vector2(680, 360)
	_event_panel.offset_left = -340
	_event_panel.offset_right = 340
	_event_panel.offset_top = -180
	_event_panel.offset_bottom = 180
	var s := _style_cream(28, 4, COL_CREAM)
	s.border_color = Color("C9A85A")
	s.content_margin_left = 32
	s.content_margin_right = 32
	s.content_margin_top = 28
	s.content_margin_bottom = 28
	_event_panel.add_theme_stylebox_override("panel", s)
	add_child(_event_panel)


func _build_empty_banner() -> void:
	_empty_banner = PanelContainer.new()
	_empty_banner.name = "FogTravelEmpty"
	_empty_banner.visible = false
	_empty_banner.z_index = 25
	_empty_banner.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_empty_banner.offset_left = -340
	_empty_banner.offset_right = 340
	_empty_banner.offset_top = -320
	_empty_banner.offset_bottom = -140
	var tex := _tex(TEX_BANNER)
	if tex != null:
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.content_margin_left = 28
		sb.content_margin_right = 28
		sb.content_margin_top = 24
		sb.content_margin_bottom = 24
		_empty_banner.add_theme_stylebox_override("panel", sb)
	else:
		_empty_banner.add_theme_stylebox_override("panel", _style_cream(24, 4, COL_CREAM))
	var lab := Label.new()
	lab.name = "FogEmptyLabel"
	lab.text = "游历点已用尽，明日再来"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 36)
	lab.add_theme_color_override("font_color", COL_BROWN)
	_empty_banner.add_child(lab)
	add_child(_empty_banner)


func _build_back() -> void:
	var back := Button.new()
	back.name = "FogBack"
	back.text = "返回"
	back.custom_minimum_size = Vector2(160, 80)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 36
	back.offset_top = -120
	back.offset_right = 196
	back.offset_bottom = -40
	_skin_btn(back, false)
	back.pressed.connect(func() -> void: stop_route(); back_requested.emit())
	add_child(back)
	var stop := Button.new()
	stop.name = "FogStop"
	stop.text = "停止行走"
	stop.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stop.offset_left = -256
	stop.offset_right = -36
	stop.offset_top = -120
	stop.offset_bottom = -40
	_skin_btn(stop, false)
	stop.pressed.connect(stop_route)
	add_child(stop)


func bind_fog(payload: Dictionary) -> void:
	_view = FogMapView.from_payload(payload)
	if _view.is_empty():
		return
	_map_id = str(_view.get("map_id", _map_id))
	if _title:
		_title.text = str(_view.get("name", "问心谷"))
	_hud_explore.text = "探索 %d/%d" % [int(_view.get("explore_revealed", 0)), int(_view.get("explore_total", 0))]
	var travel := int(_view.get("travel", 0))
	var travel_max := int(_view.get("travel_max", 20))
	if _hud_travel:
		_hud_travel.text = "%d/%d" % [travel, travel_max]
	if _hud_chest:
		_hud_chest.text = "%d/%d" % [int(_view.get("chests_opened", 0)), int(_view.get("chests_total", 3))]
	if _hud_mon:
		_hud_mon.text = "%d/%d" % [int(_view.get("monsters_defeated", 0)), int(_view.get("monsters_total", 3))]
	if _empty_banner:
		_empty_banner.visible = travel <= 0
	_rebuild_grid()
	_snap_player()


func map_id() -> String:
	return _map_id


func _tile_texture(kind: String) -> Texture2D:
	match kind:
		"path":
			return _tex(TEX_PATH)
		"water":
			return _tex(TEX_POND)
		"rock":
			return _tex(TEX_ROCK)
		_:
			return _tex(TEX_GRASS)


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		if child == _player_marker:
			continue
		child.queue_free()
	var rows := int(_view.get("rows", 12))
	var cols := int(_view.get("cols", 8))
	# 居中网格
	var grid_w := cols * CELL
	var host_w := size.x if size.x > 1.0 else 1080.0
	_grid.position = Vector2(maxf(24.0, (host_w - grid_w) * 0.5), 24.0)

	for y in range(rows):
		for x in range(cols):
			var revealed: bool = FogMapView.is_revealed(_view, x, y)
			var blocked: bool = FogMapView.is_blocked(_view, x, y)
			var tile_kind: String = FogLevelTiles.tile_at(x, y)
			var cell := Control.new()
			cell.name = "Cell_%d_%d" % [x, y]
			cell.position = Vector2(x * CELL, y * CELL)
			cell.size = Vector2(CELL - 2, CELL - 2)
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			_grid.add_child(cell)
			_grid.move_child(cell, 0)

			if revealed:
				var ground := TextureRect.new()
				ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				ground.stretch_mode = TextureRect.STRETCH_SCALE
				ground.size = cell.size
				ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var gt := _tile_texture(tile_kind)
				if gt != null:
					ground.texture = gt
				else:
					var fallback := ColorRect.new()
					fallback.size = cell.size
					fallback.color = COL_GRASS if not blocked else COL_DEEP
					fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
					cell.add_child(fallback)
				cell.add_child(ground)
				# 已开区亮度略抬一档（对照 G）
				ground.modulate = Color(1.06, 1.05, 1.03, 1.0)
				if blocked and tile_kind == "rock":
					var blk := TextureRect.new()
					blk.texture = _tex(TEX_BLOCK)
					blk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					blk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					blk.size = Vector2(CELL * 0.7, CELL * 0.7)
					blk.position = Vector2(CELL * 0.12, CELL * 0.1)
					blk.mouse_filter = Control.MOUSE_FILTER_IGNORE
					cell.add_child(blk)
			else:
				# 软边白/冷青雾 —— 禁止黑遮罩
				var fog_base := ColorRect.new()
				fog_base.size = cell.size
				fog_base.color = Color(COL_FOG_EDGE.r, COL_FOG_EDGE.g, COL_FOG_EDGE.b, 0.92)
				fog_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(fog_base)
				var cloud := TextureRect.new()
				cloud.texture = _tex(TEX_CLOUD if (x + y) % 2 == 0 else TEX_CLOUD_SM)
				cloud.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				cloud.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				cloud.size = cell.size + Vector2(8, 8)
				cloud.position = Vector2(-4, -4)
				cloud.modulate = Color(1, 1, 1, 0.95)
				cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cell.add_child(cloud)

			var xx := x
			var yy := y
			cell.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_on_cell(xx, yy)
			)

	for obj in _view.get("objects", []):
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var o := obj as Dictionary
		var ox := int(o.get("x", -1))
		var oy := int(o.get("y", -1))
		if not FogMapView.is_revealed(_view, ox, oy):
			continue
		var kind := str(o.get("kind", ""))
		if kind == "exit" or str(o.get("id", "")) == "m_guard" or bool(o.get("isExit", false)):
			var gate := PanelContainer.new()
			gate.name = "Exit_%s" % str(o.get("id", ""))
			gate.position = Vector2(ox * CELL + 3, oy * CELL + 2)
			gate.size = Vector2(CELL - 6, CELL - 4)
			gate.z_index = 5
			gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gate.add_theme_stylebox_override("panel", _style_cream(12, 4, COL_MINT))
			var caption := Label.new()
			caption.text = "谷口\n已通过" if bool(o.get("passed", o.get("defeated", false))) else "出口\n谷口"
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", 26)
			caption.add_theme_color_override("font_color", COL_BROWN)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gate.add_child(caption)
			_grid.add_child(gate)
			continue
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size = Vector2(CELL * 0.72, CELL * 0.72)
		icon.position = Vector2(ox * CELL + CELL * 0.12, oy * CELL + CELL * 0.08)
		icon.z_index = 4
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if kind == "chest":
			icon.texture = _tex(TEX_CHEST_DONE) if bool(o.get("opened", false)) else _tex(TEX_CHEST)
		elif kind == "monster":
			if bool(o.get("defeated", false)):
				continue
			icon.texture = _tex(TEX_MONSTER)
		elif kind == "event":
			if bool(o.get("done", false)):
				continue
			icon.texture = _tex(TEX_EVENT)
		else:
			continue
		_grid.add_child(icon)
	_grid.move_child(_player_marker, -1)


func _snap_player() -> void:
	var pos: Variant = _view.get("pos", {})
	if typeof(pos) != TYPE_DICTIONARY:
		return
	var x := int(pos.get("x", 0))
	var y := int(pos.get("y", 0))
	_player_marker.position = Vector2(x * CELL + CELL * 0.08, y * CELL + CELL * 0.02)
	_stop_walk_anim()


func stop_route() -> void:
	_route_epoch += 1
	_route_target = Vector2i(-1,-1)
	_route_snapshot = []
	_confirm_obj = {}
	if _confirm: _confirm.hide()
	if _event_panel: _event_panel.hide()


func _exit_tree() -> void:
	stop_route()


func prepare_open() -> bool:
	while _busy: await busy_changed
	# An explicit new entrance waits for an old response, then resolves uncertainty.
	if _runner_running: await route_idle
	if not _pending_step.is_empty():
		_runner_running = true
		var ok := await _reconcile_pending()
		_runner_running = false
		route_idle.emit()
		return ok
	return true


func _on_cell(x: int, y: int) -> void:
	if _busy or not is_visible_in_tree(): return
	var target := Vector2i(x,y)
	if target == _route_target: return
	stop_route()
	if str(_view.get("protocol","")) != "fog-step-v1":
		toast_requested.emit("自动行走需要新版服务端，请更新后再试",false)
		return
	var snapshot: Array = _view.get("revealed",[]).duplicate(true)
	var plan := FogRoute.plan(_view,target,snapshot)
	if not bool(plan.get("ok",false)):
		toast_requested.emit(str(plan.get("error","目标不可达")),false)
		return
	_route_target = target
	_route_snapshot = snapshot
	_run_route()


func _request_fog(path: String, body: Dictionary) -> Dictionary:
	if transport.is_valid(): return await transport.call(path,body)
	if not body.has("stepId"): return await PlayerApi.post_action(path,body)
	return await ApiClient.request_json(HTTPClient.METHOD_POST,path,body,PlayerApi.token(),str(body.get("stepId","")))


func _reconcile_pending() -> bool:
	if _step_token != PlayerApi.token():
		_pending_step = {}
		stop_route()
		return false
	var result := await _request_fog("/api/v1/me/fog/%s/reconcile" % _map_id.uri_encode(),_pending_step.duplicate(true))
	if _step_token != PlayerApi.token(): return false
	if not _is_terminal(result):
		toast_requested.emit("上一步状态未确认，请联网后重试，暂不能继续行走",false)
		return false
	_pending_step = {}
	bind_fog(result)
	return true


func _is_terminal(result: Dictionary) -> bool:
	var step: Dictionary = result.get("step",{})
	var fog: Dictionary = result.get("fog",{})
	return int(result.get("code",0)) == 200 and str(fog.get("protocol","")) == "fog-step-v1" and str(step.get("id","")) == str(_pending_step.get("stepId","")) and str(step.get("status","")) in ["committed","cancelled","rejected"]


func _run_route() -> void:
	if _runner_running: return
	_runner_running = true
	await _walk_route()
	_runner_running = false
	route_idle.emit()


func _walk_route() -> void:
	if not _pending_step.is_empty():
		if not await _reconcile_pending():
			stop_route()
			return
	while _route_target != Vector2i(-1,-1) and is_visible_in_tree():
		var epoch := _route_epoch
		var plan := FogRoute.plan(_view,_route_target,_route_snapshot)
		if not bool(plan.get("ok",false)):
			toast_requested.emit(str(plan.get("error","目标不可达")),false)
			stop_route()
			return
		var path: Array = plan.get("path",[])
		if path.is_empty():
			var obj: Dictionary = plan.get("object",{})
			_route_target = Vector2i(-1,-1)
			if not obj.is_empty() and epoch == _route_epoch: _prompt_object(obj,epoch)
			return
		if int(_view.get("travel",0)) <= 0:
			toast_requested.emit("游历点已用尽，明日再来",false)
			stop_route()
			return
		var next: Vector2i = path[0]
		var from: Dictionary = _view.get("pos",{}).duplicate(true)
		_pending_step = {"protocol":"fog-step-v1","stepId":"fog-%d-%d-%d" % [Time.get_ticks_usec(),randi(),randi()],"expectedRevision":str(_view.get("revision","")),"expectedFrom":from,"x":next.x,"y":next.y}
		_step_token = PlayerApi.token()
		var result := await _request_fog("/api/v1/me/fog/%s/move" % _map_id.uri_encode(),_pending_step.duplicate(true))
		if _step_token != PlayerApi.token():
			_pending_step = {}
			stop_route()
			return
		if not _is_terminal(result):
			stop_route()
			toast_requested.emit("网络中断，上一步可能已落地；再次选择前须确认状态",false)
			return
		_pending_step = {}
		var status := str(result.get("step",{}).get("status",""))
		var actual: Dictionary = result.get("fog",{}).get("pos",{})
		var old_marker := _player_marker.position
		bind_fog(result) # Commit authority BEFORE animating; never predict or roll back.
		if status != "committed" or int(actual.get("x",-1)) != next.x or int(actual.get("y",-1)) != next.y:
			stop_route()
			toast_requested.emit(str(result.get("step",{}).get("error","位置已变化，请重新选择目标")),false)
			return
		if not is_visible_in_tree(): return
		_player_marker.position = old_marker
		_start_walk_anim(next.x-int(from.get("x",0)),next.y-int(from.get("y",0)))
		_walk_tween = create_tween()
		_walk_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_walk_tween.tween_property(_player_marker,"position",Vector2(next.x*CELL+CELL*0.08,next.y*CELL+CELL*0.02),WALK_SEC)
		await _walk_tween.finished
		_stop_walk_anim()
		if epoch == _route_epoch:
			for remaining in path.slice(1):
				if not FogRoute.passable(_view, remaining, _route_target):
					stop_route()
					toast_requested.emit("前方物件阻路，已停下，请确认后再走",false)
					return
		# Re-plan only inside the latest intent's original snapshot, never new fog.


func _prompt_object(obj: Dictionary, epoch: int) -> void:
	if epoch != _route_epoch or not is_visible_in_tree(): return
	var kind := str(obj.get("kind",""))
	if kind == "event":
		_show_event(obj)
		return
	_confirm_obj = obj
	_confirm_epoch = epoch
	_confirm_action.text = "开箱" if kind == "chest" else "开战"
	_confirm_label.text = "打开这个宝箱？" if kind == "chest" else ("探索已满，挑战出口「谷口护卫」？" if kind == "exit" else "遭遇「%s」，确认进入异空间开战？" % str(obj.get("name","妖物")))
	_confirm.show()


func _on_confirm_fight() -> void:
	_confirm.hide()
	if _confirm_obj.is_empty() or _confirm_epoch != _route_epoch or not is_visible_in_tree() or _busy: return
	var obj := _confirm_obj
	_confirm_obj = {}
	if str(obj.get("kind","")) == "chest": _do_interact(str(obj.get("id","")))
	else: _do_battle(str(obj.get("id","")))


func _show_event(o: Dictionary) -> void:
	var epoch := _route_epoch
	for c in _event_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_event_panel.add_child(v)
	var title := Label.new()
	title.text = str(o.get("title", "事件"))
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", COL_BROWN)
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
		b.custom_minimum_size = Vector2(0, 76)
		_skin_btn(b, str(od.get("id", "")) == "A")
		var oid := str(od.get("id", ""))
		var effect := str(od.get("effect", "none"))
		b.pressed.connect(func() -> void:
			if epoch != _route_epoch or not is_visible_in_tree() or _busy: return
			_event_panel.visible = false
			if effect == "battle" or oid == "A":
				if await _do_interact(str(o.get("id", "")), oid) and epoch == _route_epoch and is_visible_in_tree():
					_do_battle(str(o.get("id", "")))
			else:
				_do_interact(str(o.get("id", "")), oid)
		)
		v.add_child(b)
	_event_panel.visible = true


func _do_interact(object_id: String, option_id: String = "") -> bool:
	var session := PlayerApi.token()
	var epoch := _route_epoch
	_set_busy(true)
	var body := {"objectId": object_id}
	if not option_id.is_empty():
		body["optionId"] = option_id
	var result: Dictionary = await _request_fog("/api/v1/me/fog/%s/interact" % _map_id.uri_encode(), body)
	_set_busy(false)
	if session != PlayerApi.token(): return false
	if epoch != _route_epoch or not is_visible_in_tree():
		if result.has("fog"): bind_fog(result)
		return false
	if int(result.get("code", 0)) != 200:
		toast_requested.emit(PlayerApi.error_message(result), false)
		return false
	var gained: Array = result.get("gained", [])
	if not gained.is_empty():
		var parts: PackedStringArray = []
		for g in gained:
			if typeof(g) == TYPE_DICTIONARY:
				parts.append("%s×%d" % [str(g.get("displayName", g.get("itemSlug", "?"))), int(g.get("quantity", 1))])
		toast_requested.emit("获得 " + "、".join(parts), true)
	bind_fog(result)
	if not gained.is_empty():
		loot_received.emit()

	return true

func _do_battle(object_id: String) -> void:
	var session := PlayerApi.token()
	var epoch := _route_epoch
	for obj in _view.get("objects", []):
		if str(obj.get("id", "")) == object_id and (object_id == "m_guard" or str(obj.get("kind", "")) == "exit" or bool(obj.get("isExit", false))):
			if not bool(_view.get("explore_full", false)):
				toast_requested.emit("还要再探索一下才能走这个出口", false)
				return
	_set_busy(true)
	var result: Dictionary = await _request_fog("/api/v1/me/combat/start", {"source": "fog", "mapId": _map_id, "objectId": object_id})
	_set_busy(false)
	if session != PlayerApi.token() or epoch != _route_epoch or not is_visible_in_tree(): return
	if int(result.get("code", 0)) != 200:
		toast_requested.emit(PlayerApi.error_message(result), false)
		return
	battle_requested.emit(result)
	if result.has("fog"):
		bind_fog(result)


func _set_busy(v: bool) -> void:
	_busy = v
	busy_changed.emit(v)


func sheet_anchor() -> Control:
	return null
