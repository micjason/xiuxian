class_name CavePage
extends Control
## 洞府 L0+L1 场所硬接：庭院热点 + 药园/炼丹/强化场所页（非按钮墙）。
## 数据来自 CaveView.build；写操作发 action_requested；强化复用 enhance_entry_requested。
## 设计空间 1080×2340；热区见 q_design/DONGFU_A_FINAL_NOTES.md · DONGFU_L1_V2_HOTSPOTS.md。

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

# L1 共用 / 药园
const HS_BACK := Rect2(30, 250, 96, 96)
const HS_UPGRADE := Rect2(700, 250, 200, 88)
const HS_CLAIM_ALL := Rect2(40, 360, 260, 72)
const HS_PLOTS := [
	Rect2(120, 560, 380, 320),
	Rect2(580, 560, 380, 320),
	Rect2(120, 1000, 380, 320),
	Rect2(580, 1000, 380, 320),
]
const HS_SEEDS := [
	Rect2(48, 1540, 320, 220),
	Rect2(388, 1540, 320, 220),
	Rect2(728, 1540, 320, 220),
]
# 炼丹
const HS_FURNACE := Rect2(250, 400, 580, 580)
const HS_TRAYS := [Rect2(20, 860, 280, 260), Rect2(780, 860, 280, 260)]
const HS_RECIPE_CTAS := [
	Rect2(780, 1304, 220, 80),
	Rect2(780, 1489, 220, 80),
	Rect2(780, 1674, 220, 80),
]
# 强化
const HS_EQ_RING := [
	Rect2(70, 470, 116, 116), Rect2(250, 420, 116, 116), Rect2(470, 400, 116, 116),
	Rect2(690, 420, 116, 116), Rect2(870, 490, 116, 116), Rect2(900, 710, 116, 116),
]
const HS_ARRAY_HEART := Rect2(440, 800, 200, 200)
const HS_ENHANCE_BTN := Rect2(140, 1400, 360, 120)
const HS_ENHANCE_MAX := Rect2(560, 1400, 360, 120)

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
	_ensure_fx()
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
	var sig := hash([_view, _mode, _plant_slot])
	if sig == _bind_sig:
		_sync_alchemy_fire()
		return
	_render()


func _ensure_fx() -> void:
	if _water_fx == null and ResourceLoader.exists(FX_WATER):
		_water_fx = (load(FX_WATER) as PackedScene).instantiate()
		_water_fx.name = "GardenWaterFx"
		_fx_host.add_child(_water_fx)
	if _fire_fx == null and ResourceLoader.exists(FX_FIRE):
		_fire_fx = (load(FX_FIRE) as PackedScene).instantiate()
		_fire_fx.name = "AlchemyFireFx"
		_fire_fx.position = _design_center(HS_FURNACE)
		_fx_host.add_child(_fire_fx)
	if _array_fx == null and ResourceLoader.exists(FX_ARRAY):
		_array_fx = (load(FX_ARRAY) as PackedScene).instantiate()
		_array_fx.name = "EnhanceArrayFx"
		_array_fx.position = _design_center(HS_ARRAY_HEART)
		if _array_fx.has_method("play_idle"):
			_array_fx.call("play_idle")
		_fx_host.add_child(_array_fx)


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
	_bind_sig = hash([_view, _mode, _plant_slot])
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
	var slot := int(plot.get("slot", 0))
	var status := str(plot.get("status", "empty"))
	var line := str(plot.get("line", ""))
	var wrap := PanelContainer.new()
	wrap.name = "Plot_%d" % slot
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(rect)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	match status:
		"ready":
			style.bg_color = Color(1.0, 0.82, 0.35, 0.55)
			style.border_color = UiTokens.Q_ORANGE
		"growing":
			style.bg_color = Color(0.45, 0.72, 0.55, 0.40)
			style.border_color = UiTokens.Q_MINT_DARK
		_:
			style.bg_color = Color(0.42, 0.32, 0.22, 0.28)
			style.border_color = Color(0.55, 0.42, 0.30, 0.7)
	style.set_border_width_all(3)
	style.set_corner_radius_all(120)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	wrap.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(col)
	var title := Label.new()
	title.text = str(plot.get("title", "地块"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiTokens.TEXT)
	col.add_child(title)
	var body := Label.new()
	match status:
		"empty":
			body.text = "点击种植" if _plant_slot != slot else "选择下方种子"
		"ready":
			body.text = "可收 · %s" % line
		_:
			body.text = line
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 24)
	body.add_theme_color_override("font_color", UiTokens.TEXT_MUTED)
	col.add_child(body)
	if status == "ready":
		var dot := QKit.reddot(26)
		dot.position = Vector2(local.size.x - 40, 12)
		wrap.add_child(dot)
	_stage.add_child(wrap)
	# 透明热区盖在畦上
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
	var local := _design_rect(Rect2(0, 1420, 1080, 520))
	drawer.position = local.position
	drawer.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.42, 0.30, 0.20, 0.55)
	style.border_color = UiTokens.Q_COCOA
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	drawer.add_theme_stylebox_override("panel", style)
	_stage.add_child(drawer)
	var hint := Label.new()
	hint.text = "种子袋 · 先点空畦再选种" if _plant_slot < 0 else "为地块 %d 选种子" % (_plant_slot + 1)
	hint.position = _design_to_local(Vector2(48, 1440))
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
	if _water_fx == null:
		return
	var idx := clampi(slot, 0, HS_PLOTS.size() - 1)
	var at := _design_center(HS_PLOTS[idx])
	if _water_fx.has_method("play_water"):
		_water_fx.call("play_water", at)


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
	var wrap := PanelContainer.new()
	wrap.name = "AlchemyJob_%s" % (str(job.get("id", "")) if not job.is_empty() else str(index))
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local := _design_rect(rect)
	wrap.position = local.position
	wrap.size = local.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.38, 0.22, 0.72)
	style.border_color = UiTokens.Q_COCOA
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	wrap.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(col)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.97, 0.92))
	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 22)
	body.add_theme_color_override("font_color", Color(1, 0.97, 0.92, 0.85))
	if locked:
		title.text = "未解锁"
		body.text = "升级炼丹房"
	elif job.is_empty():
		title.text = "空闲托盘"
		body.text = "点选下方配方"
	else:
		title.text = str(job.get("outputName", "丹药"))
		body.text = str(job.get("line", ""))
		if str(job.get("status", "")) == "ready":
			var dot := QKit.reddot(24)
			wrap.add_child(dot)
	col.add_child(title)
	col.add_child(body)
	_stage.add_child(wrap)
	_hotspot("TrayTap_%d" % index, rect, func() -> void: _on_tray_tap(job, locked))


func _on_tray_tap(job: Dictionary, locked: bool) -> void:
	if locked:
		action_requested.emit("toast", {"text": "升级炼丹房可解锁队列"})
		return
	if job.is_empty():
		action_requested.emit("toast", {"text": "先选下方配方"})
		return
	if str(job.get("status", "")) == "ready":
		if _fire_fx != null and _fire_fx.has_method("play_claim"):
			_fire_fx.call("play_claim")
		action_requested.emit("alchemy_claim", {"jobId": str(job.get("id", ""))})
	else:
		action_requested.emit("toast", {"text": str(job.get("line", "炼制中"))})


func _render_recipe_cta(index: int, recipe: Dictionary, queue_full: bool) -> void:
	if recipe.is_empty():
		return
	var can := bool(recipe.get("canCraft", false)) and not queue_full
	var label := "开始炼制" if index == 0 and can else ("入队" if can else ("不足" if not bool(recipe.get("canCraft", false)) else "队列满"))
	# 配方行说明
	var row_y := 1260 + index * 185
	_chip("%s · %s" % [str(recipe.get("title", "")), str(recipe.get("costLine", ""))], Rect2(48, row_y, 700, 80), "Recipe_%s" % str(recipe.get("recipeSlug", index)))
	var cta := _hotspot("RecipeCta_%d" % index, HS_RECIPE_CTAS[index], func() -> void:
		if not can:
			action_requested.emit("toast", {"text": "材料不足" if not bool(recipe.get("canCraft", false)) else "炼丹队列已满"})
			return
		if _fire_fx != null and _fire_fx.has_method("set_alchemy_on"):
			_fire_fx.call("set_alchemy_on", true)
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
	if _fire_fx == null or not _fire_fx.has_method("set_alchemy_on"):
		return
	var on := false
	if _mode == MODE_ALCHEMY:
		for job in _view.get("alchemy", []):
			if typeof(job) == TYPE_DICTIONARY and str((job as Dictionary).get("status", "")) == "crafting":
				on = true
				break
	_fire_fx.call("set_alchemy_on", on)
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
	for i in range(HS_EQ_RING.size()):
		_chip("槽", HS_EQ_RING[i], "EqRing_%d" % i)
	_chip("选中装备", HS_ARRAY_HEART, "ArrayHeart")
	_chip("消耗炼器精粹（同行囊）", Rect2(120, 1280, 840, 88), "EnhanceCost")
	var btn := _hotspot("EnhanceBtn", HS_ENHANCE_BTN, _emit_enhance, "强化", "stone")
	btn.modulate = Color(1, 1, 1, 1)
	_style_rune(btn, true)
	var btn2 := _hotspot("EnhanceMax", HS_ENHANCE_MAX, _emit_enhance, "一键强化", "stone")
	btn2.modulate = Color(1, 1, 1, 1)
	_style_rune(btn2, true)
	if _array_fx != null:
		_array_fx.position = _design_center(HS_ARRAY_HEART)
		_array_fx.visible = true


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
	if _array_fx != null and _array_fx.has_method("play_enhance_success"):
		_array_fx.call("play_enhance_success", _design_center(HS_ARRAY_HEART))
	enhance_entry_requested.emit()
