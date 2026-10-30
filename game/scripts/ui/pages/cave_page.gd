class_name CavePage
extends Control
## 洞府 L0+L1 场所硬接：庭院热点 + 药园/炼丹/强化场所页（非按钮墙）。
## 数据来自 CaveView.build；写操作发 action_requested；强化复用 enhance_entry_requested。
## 设计空间 1080×2340；热区见 q_design/DONGFU_L1_V3_HOTSPOTS.md。

signal back_requested
signal enhance_entry_requested
signal action_requested(kind: String, payload: Dictionary)

const MODE_OVERVIEW := "overview"
const MODE_GARDEN := "garden"
const MODE_ALCHEMY := "alchemy"
const MODE_ENHANCE := "enhance"

## 页面区相对画布原点：洞府页顶栏为紧凑态（无修为条），约 y=160；左 24 为 PAGE_MARGIN。
const ORIGIN := Vector2(24, 160)
const DESIGN := Vector2(1080, 2340)

# L0 热区 (x,y,w,h) 画布坐标
const HS_GARDEN := Rect2(40, 820, 420, 480)
const HS_ALCHEMY := Rect2(520, 620, 500, 540)
const HS_ENHANCE := Rect2(280, 1220, 500, 420)
const HS_STONE := Rect2(40, 118, 300, 88)
const HS_WOOD := Rect2(370, 118, 300, 88)
const HS_SERVANT := Rect2(700, 118, 340, 88)
const HS_ALLOC := Rect2(36, 1836, 1008, 120)

# L1 共用 / 药园（v3：畦下移贴垄 / 种子抽屉顶 y=1580）
const HS_BACK := Rect2(30, 250, 96, 96)
const HS_UPGRADE := Rect2(700, 250, 200, 88)
const HS_CLAIM_ALL := Rect2(40, 360, 260, 72)
const HS_PLOTS := [
	Rect2(270, 960, 260, 240),
	Rect2(550, 960, 260, 240),
	Rect2(255, 1185, 270, 255),
	Rect2(550, 1185, 270, 255),
]
const HS_SEEDS := [
	Rect2(48, 1670, 320, 175),
	Rect2(388, 1670, 320, 175),
	Rect2(728, 1670, 320, 175),
]
# 炼丹（v3：托盘贴地 y≈1100；石台 SY=1400；炉火仍挂 HS_FURNACE）
const HS_FURNACE := Rect2(250, 400, 580, 580)
const HS_TRAYS := [Rect2(50, 1100, 300, 210), Rect2(730, 1115, 300, 210)]
const HS_RECIPE_ROWS := [
	Rect2(48, 1472, 984, 134),
	Rect2(48, 1620, 984, 134),
	Rect2(48, 1768, 984, 134),
]
const HS_RECIPE_CTAS := [
	Rect2(780, 1504, 220, 72),
	Rect2(780, 1652, 220, 72),
	Rect2(780, 1800, 220, 72),
]
# 强化（v3：阵心略上；符文石 y=1448；成功闪勿盖 y≥2124）
const HS_EQ_RING := [
	Rect2(70, 470, 116, 116), Rect2(250, 420, 116, 116), Rect2(470, 400, 116, 116),
	Rect2(690, 420, 116, 116), Rect2(870, 490, 116, 116), Rect2(900, 710, 116, 116),
]
const HS_ARRAY_HEART := Rect2(440, 760, 200, 200)
const HS_ENHANCE_BTN := Rect2(160, 1448, 320, 100)
const HS_ENHANCE_MAX := Rect2(580, 1448, 320, 100)

const FX_WATER := "res://anim_q/dongfu/garden_water/garden_water_fx.tscn"
const FX_FIRE := "res://anim_q/dongfu/alchemy_fire/alchemy_fire_fx.tscn"
const FX_ARRAY := "res://anim_q/dongfu/enhance_array/enhance_array_fx.tscn"

var _mode := MODE_OVERVIEW
var _view: Dictionary = {}
var _plant_slot := -1
var _bind_sig := 0
var _stage: Control
var _fx_host: Node2D
var _water_fx: Node2D
var _fire_fx: Node2D
var _array_fx: Node2D
var _title_label: Label
## 强化场所：已穿戴装备环 + 阵心选中（同行囊 BagModel / EquipModel，不另做强化系统）。
var _bag: BagModel
var _enhance_selected_id := ""


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_stage = Control.new()
	_stage.name = "CaveStage"
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_stage)
	_fx_host = Node2D.new()
	_fx_host.name = "CaveFxHost"
	_stage.add_child(_fx_host)
	# 不在 _init 加载 3 个洞府 FX（Android 启动时 PlayScreen 构造即实例化 CavePage 易闪退）；
	# bind / _render / 播放路径再 _ensure_fx。空 _fx_host 保留。
	_render()


func sheet_anchor() -> Control:
	return null


func sheet_pad() -> float:
	return 0.0


func mode() -> String:
	return _mode


func view() -> Dictionary:
	return _view


func bind(state: Dictionary, content: Dictionary) -> void:
	_view = CaveView.build(state, content)
	_bag = BagModel.from_state(state, content)
	_ensure_enhance_selection()
	# 首次 bind / 入树后再加载 FX，与改前进入洞府后的表现一致
	_ensure_fx()
	var sig := hash([_view, _mode, _plant_slot, _enhance_selected_id, _bag_sig()])
	if sig == _bind_sig:
		_sync_alchemy_fire()
		return
	_render()


## 强化阵当前选中的已穿戴装备 id（空 = 未选）；play_screen.open_enhance_entry 优先用它。
func selected_enhance_id() -> String:
	return _enhance_selected_id


func _bag_sig() -> int:
	if _bag == null:
		return 0
	var rows: Array = []
	for item in _bag.items:
		rows.append([item.get("id"), item.get("enhance"), item.get("equipped"), item.get("equipped_slot_id")])
	return hash([rows, _bag.enhance_exp, _bag.uses_essence])


func _ensure_enhance_selection() -> void:
	if _bag == null:
		_enhance_selected_id = ""
		return
	if not _enhance_selected_id.is_empty() and not _bag.find(_enhance_selected_id).is_empty():
		return
	_enhance_selected_id = EquipModel.worn_enhance_target(_bag)
	if not _enhance_selected_id.is_empty():
		return
	# 无可强化时仍预选第一件已穿戴（阵心有展示；强化按钮仍走行囊入口）
	var slots := EquipModel.slots_of(_bag)
	for slot in SlotConfig.core():
		var item: Dictionary = slots.get(str(slot.get("id", "")), {})
		if not item.is_empty():
			_enhance_selected_id = str(item.get("id", ""))
			return
	_enhance_selected_id = ""


func _ensure_fx() -> void:
	# _init → _render 时尚未进树：跳过，避免启动期加载 3 个 FX 场景
	if not is_inside_tree():
		return
	if _fx_host == null or not is_instance_valid(_fx_host):
		_fx_host = Node2D.new()
		_fx_host.name = "CaveFxHost"
		_stage.add_child(_fx_host)
	_water_fx = _attach_fx(_water_fx, FX_WATER, "GardenWaterFx", Vector2.ZERO)
	_fire_fx = _attach_fx(_fire_fx, FX_FIRE, "AlchemyFireFx", _design_center(HS_FURNACE))
	_array_fx = _attach_fx(_array_fx, FX_ARRAY, "EnhanceArrayFx", _design_center(HS_ARRAY_HEART))
	# enhance_array_fx 自带 autoplay_idle；勿在 @onready 未就绪时强播


func _attach_fx(existing: Node2D, path: String, node_name: String, at: Vector2) -> Node2D:
	var node := existing
	if node != null and not is_instance_valid(node):
		node = null
	if node == null:
		if not ResourceLoader.exists(path):
			push_warning("CavePage FX missing: %s" % path)
			return null
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("CavePage FX load failed: %s" % path)
			return null
		node = packed.instantiate() as Node2D
		if node == null:
			push_warning("CavePage FX not Node2D: %s" % path)
			return null
		node.name = node_name
	if node.get_parent() != _fx_host:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_fx_host.add_child(node)
	if node_name != "GardenWaterFx":
		node.position = at
	return node


func _design_to_local(p: Vector2) -> Vector2:
	return p - ORIGIN


func _design_rect(r: Rect2) -> Rect2:
	return Rect2(_design_to_local(r.position), r.size)


func _design_center(r: Rect2) -> Vector2:
	return _design_to_local(r.get_center())


func _clear_stage() -> void:
	for child in _stage.get_children():
		if child == _fx_host:
			continue
		_stage.remove_child(child)
		child.queue_free()


func _on_back() -> void:
	if _mode == MODE_OVERVIEW:
		back_requested.emit()
		return
	_plant_slot = -1
	_mode = MODE_OVERVIEW
	_render()


func _render() -> void:
	_bind_sig = hash([_view, _mode, _plant_slot, _enhance_selected_id, _bag_sig()])
	_clear_stage()
	_ensure_fx()
	match _mode:
		MODE_GARDEN:
			_render_garden()
		MODE_ALCHEMY:
			_render_alchemy()
		MODE_ENHANCE:
			_render_enhance()
		_:
			_render_overview()
	_sync_alchemy_fire()
	_fx_host.move_to_front()


func _bg(name: String) -> void:
	var tex: Texture2D = ArtLib.bg(name)
	if tex == null:
		return
	var node := TextureRect.new()
	node.name = "SceneBg"
	node.texture = tex
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 铺满设计画布相对页面区：从画布 (0,0) 起，盖住顶栏下至底栏上的可视区
	node.position = _design_to_local(Vector2(0, 0))
	node.size = DESIGN
	_stage.add_child(node)


func _hotspot(name: String, rect: Rect2, on_press: Callable, label_text: String = "", kind: String = "ghost") -> Button:
	var btn := Button.new()
	btn.name = name
	btn.focus_mode = Control.FOCUS_NONE
	var local := _design_rect(rect)
	btn.position = local.position
	btn.size = local.size
	btn.custom_minimum_size = local.size
	if label_text.is_empty():
		btn.flat = true
		btn.modulate = Color(1, 1, 1, 0.01)
		btn.text = ""
	else:
		btn.text = label_text
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1.0, 0.973, 0.925, 0.88) if kind != "o" else Color("ff9f43")
		style.border_color = UiTokens.Q_COCOA
		style.set_border_width_all(3)
		style.set_corner_radius_all(28 if kind != "stone" else 18)
		style.content_margin_left = 12
		style.content_margin_right = 12
		btn.add_theme_stylebox_override("normal", style)
		var pressed := style.duplicate() as StyleBoxFlat
		pressed.bg_color = pressed.bg_color.darkened(0.08)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("disabled", style)
		btn.add_theme_color_override("font_color", UiTokens.TEXT if kind != "o" else Color.WHITE)
		btn.add_theme_font_size_override("font_size", 28)
	btn.pressed.connect(on_press)
	_stage.add_child(btn)
	return btn


func _chip(text: String, rect: Rect2, name: String = "Chip") -> Label:
	var wrap := PanelContainer.new()
	wrap.name = name
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(rect)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.973, 0.925, 0.92)
	style.border_color = UiTokens.Q_COCOA
	style.set_border_width_all(2)
	style.set_corner_radius_all(24)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	wrap.add_theme_stylebox_override("panel", style)
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", UiTokens.TEXT)
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	wrap.add_child(lab)
	_stage.add_child(wrap)
	return lab


func _place_chip(text: String, rect: Rect2, name: String = "PlaceChip", warm: bool = false) -> void:
	## 场所底缘小牌：半透木色，不挡场景。
	var wrap := PanelContainer.new()
	wrap.name = name
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(rect)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.62, 0.28, 0.82) if warm else Color(0.28, 0.18, 0.12, 0.62)
	style.border_color = Color(UiTokens.Q_ORANGE, 0.9) if warm else Color(UiTokens.Q_COCOA, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(18)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	wrap.add_theme_stylebox_override("panel", style)
	var lab := Label.new()
	lab.text = text
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 22)
	lab.add_theme_color_override("font_color", Color(1, 0.97, 0.92, 0.96))
	lab.autowrap_mode = TextServer.AUTOWRAP_OFF
	wrap.add_child(lab)
	_stage.add_child(wrap)


func _status_capsule(card: Dictionary, rect: Rect2) -> void:
	var subtitle := str(card.get("subtitle", ""))
	if subtitle.is_empty():
		return
	var cap := Rect2(rect.position.x + 24, rect.position.y + rect.size.y - 72, rect.size.x - 48, 56)
	_chip(subtitle, cap, "Status_%s" % str(card.get("id", "")))
	if int(card.get("claimable", 0)) > 0 or bool(card.get("can_upgrade", false)):
		var dot := QKit.reddot(28)
		dot.name = "ClaimDot_%s" % str(card.get("id", ""))
		dot.position = _design_to_local(Vector2(rect.position.x + rect.size.x - 56, rect.position.y + 16))
		_stage.add_child(dot)


# ───────── L0 庭院 ─────────

func _render_overview() -> void:
	_bg("dongfu_l0")
	_render_resource_pills()
	if not bool(_view.get("available", false)):
		_chip(str(_view.get("hint", "洞府配置尚未发布")), Rect2(120, 900, 840, 120), "UnavailableHint")
		return
	var cards: Dictionary = {}
	for c in _view.get("cards", []):
		if typeof(c) == TYPE_DICTIONARY:
			cards[str((c as Dictionary).get("id", ""))] = c
	_hotspot("Enter_garden", HS_GARDEN, func() -> void: _enter_facility("garden"))
	_status_capsule(cards.get("garden", {}), HS_GARDEN)
	_hotspot("Enter_alchemy", HS_ALCHEMY, func() -> void: _enter_facility("alchemy"))
	_status_capsule(cards.get("alchemy", {}), HS_ALCHEMY)
	_hotspot("Enter_enhance", HS_ENHANCE, func() -> void: _enter_facility("enhance"))
	_status_capsule(cards.get("enhance", {"subtitle": "可强化"}), HS_ENHANCE)
	_render_alloc_bar()


func _render_resource_pills() -> void:
	var stones := int(_view.get("spiritStones", 0))
	var wood := int(_view.get("woodCount", 0))
	var wood_name := str(_view.get("woodName", "灵木"))
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	var total := int(_view.get("servantTotal", 0))
	var used := int(alloc.get("garden", 0)) + int(alloc.get("alchemy", 0))
	_resource_pill("StonePill", HS_STONE, "icons/res_stone", OfflineView.grouped(float(stones)))
	_resource_pill("WoodPill", HS_WOOD, "icons/icon_lingmu", "%s %d" % [wood_name, wood])
	_resource_pill("ServantPill", HS_SERVANT, "icons/icon_lingpu", "灵仆 %d/%d" % [used, total])


func _resource_pill(name: String, rect: Rect2, icon_path: String, text: String) -> void:
	var wrap := PanelContainer.new()
	wrap.name = name
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(rect)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.973, 0.925, 0.94)
	style.border_color = UiTokens.Q_COCOA
	style.set_border_width_all(3)
	style.set_corner_radius_all(44)
	style.content_margin_left = 18
	style.content_margin_right = 18
	wrap.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = null
	if ArtLib.has_q(icon_path + ".png"):
		tex = ArtLib.q(icon_path)
	elif icon_path.ends_with("res_stone") and ArtLib.has_q("icons/res_stone.png"):
		tex = ArtLib.q("icons/res_stone")
	icon.texture = tex
	row.add_child(icon)
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 28)
	lab.add_theme_color_override("font_color", UiTokens.TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lab)
	_stage.add_child(wrap)


func _render_alloc_bar() -> void:
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	var garden := int(alloc.get("garden", 0))
	var alchemy := int(alloc.get("alchemy", 0))
	var total := int(_view.get("servantTotal", 0))
	var idle := maxi(0, total - garden - alchemy)
	var wrap := PanelContainer.new()
	wrap.name = "ServantAllocation"
	var local := _design_rect(HS_ALLOC)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.973, 0.925, 0.94)
	style.border_color = UiTokens.Q_COCOA
	style.set_border_width_all(3)
	style.set_corner_radius_all(28)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	wrap.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(row)
	row.add_child(_alloc_side("药园", "garden", garden, idle))
	var mid := Label.new()
	mid.text = "闲置 %d" % idle
	mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_theme_font_size_override("font_size", 28)
	mid.add_theme_color_override("font_color", UiTokens.TEXT_MUTED)
	mid.custom_minimum_size = Vector2(180, 0)
	row.add_child(mid)
	row.add_child(_alloc_side("炼丹", "alchemy", alchemy, idle))
	_stage.add_child(wrap)


func _alloc_side(title: String, key: String, value: int, idle: int) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var lab := Label.new()
	lab.text = "%s %d" % [title, value]
	lab.add_theme_font_size_override("font_size", 28)
	lab.add_theme_color_override("font_color", UiTokens.TEXT)
	lab.custom_minimum_size = Vector2(140, 0)
	box.add_child(lab)
	var minus := QKit.button("-", "m", 56, 28)
	minus.name = "AllocMinus_%s" % key
	minus.custom_minimum_size = Vector2(72, 72)
	minus.disabled = value <= 0
	minus.pressed.connect(func() -> void: _shift_allocation(key, -1))
	box.add_child(minus)
	var plus := QKit.button("+", "o", 56, 28)
	plus.name = "AllocPlus_%s" % key
	plus.custom_minimum_size = Vector2(72, 72)
	plus.disabled = idle <= 0
	plus.pressed.connect(func() -> void: _shift_allocation(key, 1))
	box.add_child(plus)
	return box


func _shift_allocation(key: String, delta: int) -> void:
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	var garden := int(alloc.get("garden", 0))
	var alchemy := int(alloc.get("alchemy", 0))
	if key == "garden":
		garden += delta
	else:
		alchemy += delta
	action_requested.emit("dongfu_allocate", {"garden": garden, "alchemy": alchemy})


func _enter_facility(id: String) -> void:
	match id:
		"garden":
			if not bool(_view.get("available", false)):
				action_requested.emit("toast", {"text": str(_view.get("hint", "洞府尚未开放"))})
				return
			_plant_slot = -1
			_mode = MODE_GARDEN
			_render()
		"alchemy":
			if not bool(_view.get("available", false)):
				action_requested.emit("toast", {"text": str(_view.get("hint", "洞府尚未开放"))})
				return
			_mode = MODE_ALCHEMY
			_render()
		"enhance":
			_mode = MODE_ENHANCE
			_ensure_enhance_selection()
			_render()
		_:
			pass


# ───────── L1 药园 ─────────

func _render_garden() -> void:
	_bg("dongfu_garden_l1")
	_hotspot("BackButton", HS_BACK, _on_back, "←", "ghost")
	var level := int(_view.get("gardenLevel", 1))
	_title_label = _chip("药园 Lv%d" % level, Rect2(140, 250, 420, 88), "CaveTitle")
	var upgrades: Dictionary = _view.get("upgrades", {}) if typeof(_view.get("upgrades", {})) == TYPE_DICTIONARY else {}
	var g_up: Dictionary = upgrades.get("garden", {}) if typeof(upgrades.get("garden", {})) == TYPE_DICTIONARY else {}
	var up := _hotspot("Upgrade_garden", HS_UPGRADE, func() -> void: action_requested.emit("dongfu_upgrade", {"facility": "garden"}), "升级", "o")
	up.disabled = not bool(g_up.get("canUpgrade", false))
	var claimable := int((_view.get("claimable", {}) as Dictionary).get("plots", 0))
	var claim_all := _hotspot("GardenClaimAll", HS_CLAIM_ALL, func() -> void: action_requested.emit("garden_claim", {}), "一键领取", "o")
	claim_all.disabled = claimable <= 0
	var garden_pct := int(round(float((_view.get("timeScale", {}) as Dictionary).get("garden", 1.0)) * 100.0))
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	_chip("灵仆 %d · 成熟 %d%%" % [int(alloc.get("garden", 0)), garden_pct], Rect2(320, 362, 300, 68), "GardenServantHint")

	var plots: Array = _view.get("plots", [])
	for i in range(mini(4, maxi(plots.size(), HS_PLOTS.size()))):
		var rect: Rect2 = HS_PLOTS[i]
		var plot: Dictionary = plots[i] if i < plots.size() and typeof(plots[i]) == TYPE_DICTIONARY else {"slot": i, "status": "empty", "line": "空畦 · 点击种植", "title": "地块 %d" % (i + 1)}
		_render_plot_ridge(plot, rect)

	_render_seed_drawer()


func _render_plot_ridge(plot: Dictionary, rect: Rect2) -> void:
	## v3：勿用大椭圆盖作物。空畦=中心虚线小坑；生长/成熟=贴作物旁小 chip。
	var slot := int(plot.get("slot", 0))
	var status := str(plot.get("status", "empty"))
	var line := str(plot.get("line", ""))
	var selected := _plant_slot == slot
	var local := _design_rect(rect)
	if status == "empty":
		# 虚线小坑：热区中心一小圈，不盖整垄
		var pit_sz := Vector2(minf(local.size.x, local.size.y) * 0.42, minf(local.size.x, local.size.y) * 0.34)
		var pit := Panel.new()
		pit.name = "PlotPit_%d" % slot
		pit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pit.position = local.position + (local.size - pit_sz) * 0.5
		pit.size = pit_sz
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.42, 0.32, 0.22, 0.18 if selected else 0.10)
		style.border_color = Color(UiTokens.Q_ORANGE, 0.90) if selected else Color(0.55, 0.42, 0.30, 0.55)
		style.set_border_width_all(3 if selected else 2)
		style.set_corner_radius_all(int(minf(pit_sz.x, pit_sz.y) * 0.48))
		pit.add_theme_stylebox_override("panel", style)
		_stage.add_child(pit)
		_place_chip("选择下方种子" if selected else "点击种植", Rect2(
			rect.position.x + rect.size.x * 0.12,
			rect.position.y + rect.size.y * 0.55,
			rect.size.x * 0.76,
			44
		), "PlotChip_%d" % slot, false)
	else:
		# 生长/成熟：仅小状态 chip，不画满格椭圆卡
		var chip_text := "可收" if status == "ready" else (line if not line.is_empty() else "生长中")
		var chip_w := minf(rect.size.x * 0.72, 180.0)
		_place_chip(chip_text, Rect2(
			rect.position.x + (rect.size.x - chip_w) * 0.5,
			rect.position.y + 8,
			chip_w,
			44
		), "PlotChip_%d" % slot, status == "ready")
		if status == "ready":
			var glow := Panel.new()
			glow.name = "PlotReadyGlow_%d" % slot
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var gsz := Vector2(local.size.x * 0.55, local.size.y * 0.45)
			glow.position = local.position + (local.size - gsz) * 0.5
			glow.size = gsz
			var gs := StyleBoxFlat.new()
			gs.bg_color = Color(1.0, 0.72, 0.25, 0.12)
			gs.border_color = Color(UiTokens.Q_ORANGE, 0.55)
			gs.set_border_width_all(2)
			gs.set_corner_radius_all(int(minf(gsz.x, gsz.y) * 0.48))
			glow.add_theme_stylebox_override("panel", gs)
			_stage.add_child(glow)
			var dot := QKit.reddot(22)
			dot.position = local.position + Vector2(local.size.x * 0.72, local.size.y * 0.18)
			_stage.add_child(dot)
	# 透明热区盖在畦上；浇水 FX 用 HS_PLOTS 中心
	_hotspot("PlotTap_%d" % slot, rect, func() -> void: _on_plot_tap(slot, status))


func _on_plot_tap(slot: int, status: String) -> void:
	match status:
		"empty":
			_plant_slot = slot
			_render()
		"ready":
			action_requested.emit("garden_claim", {"slot": slot})
		_:
			action_requested.emit("toast", {"text": "还在生长中"})


func _render_seed_drawer() -> void:
	var seeds: Array = _view.get("seeds", [])
	var drawer := PanelContainer.new()
	drawer.name = "SeedPicker"
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(Rect2(0, 1580, 1080, 360))
	drawer.position = local.position
	drawer.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.42, 0.30, 0.20, 0.28)
	style.border_color = Color(UiTokens.Q_COCOA, 0.35)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	drawer.add_theme_stylebox_override("panel", style)
	_stage.add_child(drawer)
	var hint := Label.new()
	hint.text = "种子袋 · 先点空畦再选种" if _plant_slot < 0 else "为地块 %d 选种子" % (_plant_slot + 1)
	hint.position = _design_to_local(Vector2(48, 1600))
	hint.size = Vector2(900, 40)
	hint.add_theme_font_size_override("font_size", 26)
	hint.add_theme_color_override("font_color", Color(1, 0.97, 0.92, 0.95))
	_stage.add_child(hint)
	for i in range(HS_SEEDS.size()):
		var rect: Rect2 = HS_SEEDS[i]
		var seed: Dictionary = seeds[i] if i < seeds.size() and typeof(seeds[i]) == TYPE_DICTIONARY else {}
		var have := int(seed.get("have", 0))
		var label := str(seed.get("name", "空袋")) if not seed.is_empty() else "—"
		var btn := _hotspot("SeedBag_%d" % i, rect, func() -> void: _on_seed_tap(seed), "%s\n×%d" % [label, have] if not seed.is_empty() else "—", "ghost")
		btn.disabled = seed.is_empty() or have <= 0
		btn.modulate = Color(1, 1, 1, 1)
		var bag_style := StyleBoxFlat.new()
		bag_style.bg_color = Color(0.92, 0.82, 0.62, 0.92)
		bag_style.border_color = UiTokens.Q_COCOA
		bag_style.set_border_width_all(3)
		bag_style.set_corner_radius_all(22)
		btn.add_theme_stylebox_override("normal", bag_style)
		btn.add_theme_stylebox_override("pressed", bag_style)
		btn.add_theme_stylebox_override("hover", bag_style)
		btn.add_theme_stylebox_override("disabled", bag_style)
		btn.add_theme_color_override("font_color", UiTokens.TEXT if have > 0 else UiTokens.TEXT_MUTED)
		btn.add_theme_font_size_override("font_size", 26)


func _on_seed_tap(seed: Dictionary) -> void:
	if seed.is_empty():
		return
	if _plant_slot < 0:
		action_requested.emit("toast", {"text": "先点一块空畦"})
		return
	if int(seed.get("have", 0)) <= 0:
		action_requested.emit("toast", {"text": "行囊里没有这颗种子"})
		return
	var slot := _plant_slot
	var slug := str(seed.get("seedSlug", ""))
	_plant_slot = -1
	_play_water_at_slot(slot)
	action_requested.emit("garden_plant", {"slot": slot, "seedSlug": slug})


func _play_water_at_slot(slot: int) -> void:
	_ensure_fx()
	if _water_fx == null:
		return
	var idx := clampi(slot, 0, HS_PLOTS.size() - 1)
	var at := _design_center(HS_PLOTS[idx])
	_water_fx.visible = true
	if _water_fx.has_method("play_water"):
		if _water_fx.is_node_ready():
			_water_fx.call("play_water", at)
		else:
			_water_fx.call_deferred("play_water", at)


# ───────── L1 炼丹 ─────────

func _render_alchemy() -> void:
	_bg("dongfu_alchemy_l1")
	_hotspot("BackButton", HS_BACK, _on_back, "←", "ghost")
	var level := int(_view.get("alchemyLevel", 1))
	_chip("炼丹 Lv%d" % level, Rect2(140, 250, 420, 88), "CaveTitle")
	var upgrades: Dictionary = _view.get("upgrades", {}) if typeof(_view.get("upgrades", {})) == TYPE_DICTIONARY else {}
	var a_up: Dictionary = upgrades.get("alchemy", {}) if typeof(upgrades.get("alchemy", {})) == TYPE_DICTIONARY else {}
	var up := _hotspot("Upgrade_alchemy", HS_UPGRADE, func() -> void: action_requested.emit("dongfu_upgrade", {"facility": "alchemy"}), "升级", "o")
	up.disabled = not bool(a_up.get("canUpgrade", false))

	# 丹炉地标（展示）
	if ArtLib.has_q("sprites/bd_alchemy_landmark.png"):
		var furnace := TextureRect.new()
		furnace.name = "FurnaceLandmark"
		furnace.texture = ArtLib.q("sprites/bd_alchemy_landmark")
		furnace.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		furnace.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		furnace.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fr := _design_rect(HS_FURNACE)
		furnace.position = fr.position
		furnace.size = fr.size
		_stage.add_child(furnace)

	var jobs: Array = _view.get("alchemy", [])
	var queue_len := int(_view.get("alchemyQueueLength", 2))
	for i in range(HS_TRAYS.size()):
		var rect: Rect2 = HS_TRAYS[i]
		var job: Dictionary = jobs[i] if i < jobs.size() and typeof(jobs[i]) == TYPE_DICTIONARY else {}
		_render_alchemy_tray(i, rect, job, i >= queue_len)

	var recipes: Array = _view.get("recipes", [])
	var queue_full := jobs.size() >= queue_len
	for i in range(HS_RECIPE_CTAS.size()):
		var recipe: Dictionary = recipes[i] if i < recipes.size() and typeof(recipes[i]) == TYPE_DICTIONARY else {}
		_render_recipe_cta(i, recipe, queue_full)


func _render_alchemy_tray(index: int, rect: Rect2, job: Dictionary, locked: bool) -> void:
	## 空/锁托盘：低透明木描边，不盖场景托盘；忙/可领：紧凑状态 chip。
	var local := _design_rect(rect)
	var outline := Panel.new()
	outline.name = "TrayOutline_%d" % index
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.position = local.position
	outline.size = local.size
	var style := StyleBoxFlat.new()
	var ready := (not job.is_empty()) and str(job.get("status", "")) == "ready"
	if locked or job.is_empty():
		style.bg_color = Color(0.42, 0.30, 0.18, 0.10)
		style.border_color = Color(0.55, 0.40, 0.26, 0.45)
		style.set_border_width_all(2)
	elif ready:
		style.bg_color = Color(1.0, 0.72, 0.25, 0.16)
		style.border_color = Color(UiTokens.Q_ORANGE, 0.85)
		style.set_border_width_all(3)
	else:
		style.bg_color = Color(0.55, 0.30, 0.15, 0.12)
		style.border_color = Color(0.85, 0.45, 0.22, 0.55)
		style.set_border_width_all(2)
	style.set_corner_radius_all(28)
	outline.add_theme_stylebox_override("panel", style)
	_stage.add_child(outline)
	var chip_text := ""
	if locked:
		chip_text = "未解锁"
	elif job.is_empty():
		chip_text = "点选配方"
	elif ready:
		chip_text = "可领 · %s" % str(job.get("outputName", "丹药"))
	else:
		chip_text = "%s · %s" % [str(job.get("outputName", "丹药")), str(job.get("line", "炼制中"))]
	_place_chip(chip_text, Rect2(
		rect.position.x + 16,
		rect.position.y + rect.size.y - 72,
		rect.size.x - 32,
		56
	), "TrayChip_%d" % index, ready)
	if ready:
		var dot := QKit.reddot(24)
		dot.position = local.position + Vector2(local.size.x - 36, 10)
		_stage.add_child(dot)
	_hotspot("TrayTap_%d" % index, rect, func() -> void: _on_tray_tap(job, locked))


func _on_tray_tap(job: Dictionary, locked: bool) -> void:
	if locked:
		action_requested.emit("toast", {"text": "升级炼丹房可解锁队列"})
		return
	if job.is_empty():
		action_requested.emit("toast", {"text": "先选下方配方"})
		return
	if str(job.get("status", "")) == "ready":
		_ensure_fx()
		if _fire_fx != null and _fire_fx.has_method("play_claim"):
			_fire_fx.visible = true
			if _fire_fx.is_node_ready():
				_fire_fx.call("play_claim")
			else:
				_fire_fx.call_deferred("play_claim")
		action_requested.emit("alchemy_claim", {"jobId": str(job.get("id", ""))})
	else:
		action_requested.emit("toast", {"text": str(job.get("line", "炼制中"))})


func _render_recipe_cta(index: int, recipe: Dictionary, queue_full: bool) -> void:
	if recipe.is_empty():
		return
	var can := bool(recipe.get("canCraft", false)) and not queue_full
	var label := "开始炼制" if index == 0 and can else ("入队" if can else ("不足" if not bool(recipe.get("canCraft", false)) else "队列满"))
	# 配方行说明（v3 石台 SY=1400：1472/1620/1768）
	var row: Rect2 = HS_RECIPE_ROWS[index] if index < HS_RECIPE_ROWS.size() else Rect2(48, 1472 + index * 148, 984, 134)
	_chip("%s · %s" % [str(recipe.get("title", "")), str(recipe.get("costLine", ""))], Rect2(row.position.x, row.position.y + 20, 700, 72), "Recipe_%s" % str(recipe.get("recipeSlug", index)))
	var cta := _hotspot("RecipeCta_%d" % index, HS_RECIPE_CTAS[index], func() -> void:
		if not can:
			action_requested.emit("toast", {"text": "材料不足" if not bool(recipe.get("canCraft", false)) else "炼丹队列已满"})
			return
		_ensure_fx()
		if _fire_fx != null and _fire_fx.has_method("set_alchemy_on"):
			_fire_fx.visible = true
			if _fire_fx.is_node_ready():
				_fire_fx.call("set_alchemy_on", true)
			else:
				_fire_fx.call_deferred("set_alchemy_on", true)
		action_requested.emit("alchemy_start", {"recipeSlug": str(recipe.get("recipeSlug", ""))})
	, label, "stone")
	cta.disabled = not can
	cta.modulate = Color(1, 1, 1, 1)
	var st := StyleBoxFlat.new()
	st.bg_color = UiTokens.Q_ORANGE if can else UiTokens.Q_GREY
	st.border_color = UiTokens.Q_COCOA
	st.set_border_width_all(3)
	st.set_corner_radius_all(16)
	cta.add_theme_stylebox_override("normal", st)
	cta.add_theme_stylebox_override("pressed", st)
	cta.add_theme_stylebox_override("hover", st)
	cta.add_theme_stylebox_override("disabled", st)
	cta.add_theme_color_override("font_color", Color.WHITE)
	cta.add_theme_font_size_override("font_size", 26)


func _sync_alchemy_fire() -> void:
	_ensure_fx()
	var on := false
	if _mode == MODE_ALCHEMY:
		for job in _view.get("alchemy", []):
			if typeof(job) == TYPE_DICTIONARY and str((job as Dictionary).get("status", "")) == "crafting":
				on = true
				break
	if _fire_fx != null and _fire_fx.has_method("set_alchemy_on"):
		if _fire_fx.is_node_ready():
			_fire_fx.call("set_alchemy_on", on)
		else:
			_fire_fx.call_deferred("set_alchemy_on", on)
	if _fire_fx != null:
		_fire_fx.visible = _mode == MODE_ALCHEMY
	if _water_fx != null:
		_water_fx.visible = _mode == MODE_GARDEN or _mode == MODE_OVERVIEW
	if _array_fx != null:
		_array_fx.visible = _mode == MODE_ENHANCE


# ───────── L1 强化（场所壳，规则仍走行囊强化） ─────────

func _render_enhance() -> void:
	_bg("dongfu_enhance_l1")
	_hotspot("BackButton", HS_BACK, _on_back, "←", "ghost")
	_chip("强化阵", Rect2(400, 248, 280, 88), "CaveTitle")
	if ArtLib.has_q("sprites/bd_array_formation.png"):
		var arr := TextureRect.new()
		arr.name = "ArrayLandmark"
		arr.texture = ArtLib.q("sprites/bd_array_formation")
		arr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hr := _design_rect(Rect2(290, 560, 500, 500))
		arr.position = hr.position
		arr.size = hr.size
		_stage.add_child(arr)
	var worn := EquipModel.slots_of(_bag) if _bag != null else {}
	var core := SlotConfig.core()
	for i in range(mini(HS_EQ_RING.size(), core.size())):
		var slot_cfg: Dictionary = core[i]
		var slot_id := str(slot_cfg.get("id", ""))
		var item: Dictionary = worn.get(slot_id, {}) if typeof(worn.get(slot_id, {})) == TYPE_DICTIONARY else {}
		_ring_cell(i, slot_cfg, item)
	_render_array_heart()
	_render_enhance_cost()
	var btn := _hotspot("EnhanceBtn", HS_ENHANCE_BTN, _emit_enhance, "强化", "stone")
	btn.modulate = Color(1, 1, 1, 1)
	_style_rune(btn, true)
	var btn2 := _hotspot("EnhanceMax", HS_ENHANCE_MAX, _emit_enhance, "一键强化", "stone")
	btn2.modulate = Color(1, 1, 1, 1)
	_style_rune(btn2, true)
	if _array_fx != null:
		_array_fx.position = _design_center(HS_ARRAY_HEART)
		# 成功闪锚在阵心，勿盖底栏 y≥2124
		_array_fx.visible = true
		if _array_fx.position.y > 2124.0 - ORIGIN.y:
			_array_fx.position.y = 2124.0 - ORIGIN.y


func _ring_cell(index: int, slot_cfg: Dictionary, item: Dictionary) -> void:
	var rect: Rect2 = HS_EQ_RING[index]
	var local := _design_rect(rect)
	var selected := (not item.is_empty()) and str(item.get("id", "")) == _enhance_selected_id
	var btn := Button.new()
	btn.name = "EqRing_%d" % index
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = true
	btn.text = ""
	btn.position = local.position
	btn.size = local.size
	btn.custom_minimum_size = local.size
	btn.clip_contents = true
	var rarity := int(item.get("rarity", -1)) if not item.is_empty() else -1
	var art := KitStyle.icon_for(item) if not item.is_empty() else {"texture": null, "tint": false}
	var tex: Texture2D = art.get("texture", null) as Texture2D
	if tex == null and item.is_empty():
		var slot_tex := ArtLib.icon(ArtLib.slot_icon_name(str(slot_cfg.get("id", ""))))
		tex = slot_tex
	var tint := Color.WHITE
	if bool(art.get("tint", false)) and not item.is_empty():
		tint = UiTokens.rarity_color(rarity).darkened(0.15)
	elif item.is_empty():
		tint = Color(UiTokens.TEXT_DISABLED, 0.55)
	var level := ("+%d" % int(item.get("enhance", 0))) if not item.is_empty() and int(item.get("enhance", 0)) > 0 else ""
	var slot_view := QKit.slot(tex, rarity, int(local.size.x), "", level, tint, false)
	slot_view.name = "EqRingArt_%d" % index
	slot_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(slot_view)
	if item.is_empty():
		var glyph := Label.new()
		glyph.text = str(slot_cfg.get("glyph", "·"))
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 36)
		glyph.add_theme_color_override("font_color", UiTokens.TEXT_DISABLED)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(glyph)
	if selected:
		var ring := Panel.new()
		ring.name = "EqRingSel_%d" % index
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(1, 1, 1, 0)
		st.border_color = UiTokens.Q_ORANGE
		st.set_border_width_all(4)
		st.set_corner_radius_all(18)
		ring.add_theme_stylebox_override("panel", st)
		btn.add_child(ring)
	var item_id := str(item.get("id", ""))
	var slot_id := str(slot_cfg.get("id", ""))
	btn.pressed.connect(func() -> void: _on_ring_tap(slot_id, item_id))
	_stage.add_child(btn)


func _on_ring_tap(_slot_id: String, item_id: String) -> void:
	if item_id.is_empty():
		action_requested.emit("toast", {"text": "该部位未穿戴装备"})
		return
	if _enhance_selected_id == item_id:
		return
	_enhance_selected_id = item_id
	_render()


func _render_array_heart() -> void:
	var item := _bag.find(_enhance_selected_id) if _bag != null and not _enhance_selected_id.is_empty() else {}
	if item.is_empty():
		_chip("选中装备", HS_ARRAY_HEART, "ArrayHeart")
		return
	var local := _design_rect(HS_ARRAY_HEART)
	var wrap := Control.new()
	wrap.name = "ArrayHeart"
	wrap.position = local.position
	wrap.size = local.size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := KitStyle.icon_for(item)
	var tex: Texture2D = art.get("texture", null) as Texture2D
	var rarity := int(item.get("rarity", 0))
	var tint := UiTokens.rarity_color(rarity).darkened(0.1) if bool(art.get("tint", false)) else Color.WHITE
	var level := ("+%d" % int(item.get("enhance", 0))) if int(item.get("enhance", 0)) > 0 else ""
	var slot_view := QKit.slot(tex, rarity, int(minf(local.size.x, local.size.y)), "", level, tint, false)
	slot_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	slot_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(slot_view)
	var name_lab := Label.new()
	name_lab.text = str(item.get("name", ""))
	name_lab.position = Vector2(0, local.size.y - 4)
	name_lab.size = Vector2(local.size.x, 40)
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.add_theme_font_size_override("font_size", 24)
	name_lab.add_theme_color_override("font_color", UiTokens.TEXT)
	name_lab.add_theme_color_override("font_outline_color", Color(1, 0.973, 0.925, 0.95))
	name_lab.add_theme_constant_override("outline_size", 6)
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(name_lab)
	_stage.add_child(wrap)


func _render_enhance_cost() -> void:
	var item := _bag.find(_enhance_selected_id) if _bag != null and not _enhance_selected_id.is_empty() else {}
	if item.is_empty():
		_chip("点选环上已穿戴装备", Rect2(120, 1280, 840, 88), "EnhanceCost")
		return
	var unit := "炼器精粹" if _bag.uses_essence else "强化经验"
	var have := int(_bag.enhance_exp)
	var need := int(item.get("enhance_cost", 0))
	var level := int(item.get("enhance", 0))
	var can := BagModel.can_enhance(item)
	var text := "%s %d/%d · +%d→+%d" % [unit, have, need, level, level + 1] if can else "%s · 已达上限或需突破" % str(item.get("name", "装备"))
	_chip(text, Rect2(120, 1280, 840, 88), "EnhanceCost")


func _style_rune(btn: Button, enabled: bool) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color("ff9f43") if enabled else UiTokens.Q_GREY
	st.border_color = UiTokens.Q_COCOA
	st.set_border_width_all(4)
	st.set_corner_radius_all(18)
	btn.add_theme_stylebox_override("normal", st)
	btn.add_theme_stylebox_override("pressed", st)
	btn.add_theme_stylebox_override("hover", st)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 32)


func _emit_enhance() -> void:
	_ensure_fx()
	if _array_fx != null and _array_fx.has_method("play_enhance_success"):
		var at := _design_center(HS_ARRAY_HEART)
		# 成功闪勿盖底栏（设计 y≥2124）
		at.y = minf(at.y, 2124.0 - ORIGIN.y - 40.0)
		_array_fx.visible = true
		_array_fx.position = at
		if _array_fx.is_node_ready():
			_array_fx.call("play_enhance_success", at)
		else:
			_array_fx.call_deferred("play_enhance_success", at)
	enhance_entry_requested.emit()
