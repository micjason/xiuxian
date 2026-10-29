class_name CavePage
extends VBoxContainer
## 洞府页（Q 版设计稿 q_cave，从修炼页右侧「洞府」入口进入）：浮岛建筑地图 + 选中建筑的详情。
## 建筑和数值只取现有配置 CaveView（等级、每小时产出，原型阶段的展示数据，服务器还没有洞府系统）。
## 设计稿里有、配置里没有的建筑（静室）照样显示，标「暂未开放」，点了提示「功能暂未开放」；
## 「升级」也还没有，点了同样提示。配置里有、设计稿地图上没位置的（藏经阁、炼器室）列在详情下方的小标签里。
## 详情底部的「强化」是临时入口（信号 enhance_entry_requested），洞府经营总览第三张卡会换掉它。

signal back_requested
## 总览第三张卡（强化）按下。洞府经营会换掉这页地图；新总览只要发出同名无参信号即可。
signal enhance_entry_requested

const ORIGIN := Vector2(24, 250)
## 地图上的建筑：设计稿位置 + 精灵图 + 对应 CaveView 的 id（空 = 配置里没有，展示用）。
const MAP := [
	{"key": "field", "cave_id": "field", "name": "灵田", "sprite": "bd_field", "rect": Rect2(40, 420, 400, 374)},
	{"key": "alchemy", "cave_id": "alchemy", "name": "丹房", "sprite": "bd_alchemy", "rect": Rect2(680, 430, 300, 402)},
	{"key": "array", "cave_id": "array", "name": "聚灵阵", "sprite": "bd_array", "rect": Rect2(64, 1000, 380, 415)},
	{"key": "retreat", "cave_id": "", "name": "静室", "sprite": "bd_hut", "rect": Rect2(676, 1074, 320, 404)},
]

var _map: Control
var _map_content: Control
const MAP_H := 1290.0
var _detail: PanelContainer
var _detail_body: VBoxContainer
var _selected := "array"
var _buttons: Dictionary = {}
var _upgrade: Button
## 临时强化钮。经营总览第三张卡落地后删掉，信号名保持 enhance_entry_requested。
var _enhance_entry: Button


func _init() -> void:
	add_theme_constant_override("separation", 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map = Control.new()
	_map.name = "CaveMap"
	_map.custom_minimum_size = Vector2(0, 760)
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.clip_contents = false
	add_child(_map)
	## 地图按设计稿坐标摆（1032×MAP_H）；矮屏（如 1080×1920）整体等比缩小居中，不压到详情卡和底栏。
	_map_content = Control.new()
	_map_content.name = "MapContent"
	_map_content.size = Vector2(1032, MAP_H)
	_map_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.add_child(_map_content)
	_map.resized.connect(_fit_map)
	_build_header()
	for spec in MAP:
		_build_building(spec)
	var card := QKit.panel(UiTokens.Q_CREAM, 34, 26, 20)
	_detail = card.panel
	_detail.name = "BuildingDetail"
	_detail.custom_minimum_size = Vector2(0, 340)
	add_child(_detail)
	_detail_body = card.body
	var orb_room := Control.new()
	orb_room.custom_minimum_size = Vector2(0, 110)
	orb_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb_room)
	_render_detail()


func _fit_map() -> void:
	var k := clampf(minf(_map.size.y / MAP_H, _map.size.x / 1032.0), 0.3, 1.0)
	_map_content.scale = Vector2(k, k)
	_map_content.position = Vector2((_map.size.x - 1032.0 * k) / 2.0, 0)


func _place(node: Control, rect: Rect2) -> void:
	node.position = rect.position - ORIGIN
	node.size = rect.size
	_map_content.add_child(node)


func _build_header() -> void:
	var back := Button.new()
	back.name = "BackButton"
	back.focus_mode = Control.FOCUS_NONE
	var tex := ArtLib.qui("btn_back")
	for key in ["normal", "hover", "pressed", "disabled"]:
		if tex != null:
			var box := StyleBoxTexture.new()
			box.texture = tex
			back.add_theme_stylebox_override(key, box)
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if tex == null:
		back.text = "‹"
	back.tooltip_text = "返回修炼"
	back.pressed.connect(func() -> void: back_requested.emit())
	_place(back, Rect2(30, 258, 96, 102))
	var ribbon := QKit.ribbon("洞府", 48, 160, true)
	ribbon.name = "CaveTitle"
	_place(ribbon, Rect2(540 - (ribbon.custom_minimum_size.x / 2.0), 200, ribbon.custom_minimum_size.x, 122))


func _cave_def(cave_id: String) -> Dictionary:
	for building in CaveView.buildings():
		if str(building.get("id", "")) == cave_id:
			return building
	return {}


func _build_building(spec: Dictionary) -> void:
	var rect: Rect2 = spec.rect
	var def := _cave_def(str(spec.cave_id))
	var button := Button.new()
	button.name = "Building_%s" % str(spec.key)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_place(button, rect)
	var art := TextureRect.new()
	art.texture = ArtLib.q("sprites/" + str(spec.sprite)) if ArtLib.has_q("sprites/%s.png" % str(spec.sprite)) else null
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -60
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	# 名牌：Lv（配置有才显示）+ 名字
	var plate := PanelContainer.new()
	plate.name = "NamePlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold := str(spec.key) == _selected
	var cut := "plate_label_gold_66" if gold else "plate_label_cream_66"
	plate.add_theme_stylebox_override("panel", QKit.cut_box(cut, 18, 0) if ArtLib.qui(cut) != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 33, 4, 18, 0))
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	if not def.is_empty():
		row.add_child(QKit.tag(CaveView.level_text(def), "mint", 30, 12))
	row.add_child(QKit.title(str(def.get("name", spec.name)), 38, UiTokens.TEXT))
	plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	plate.offset_top = -78
	plate.offset_bottom = -8
	button.add_child(plate)
	var sub := UiKit.label(_output_short(def) if not def.is_empty() else "暂未开放", UiTokens.FS_MICRO, UiTokens.TEXT if not def.is_empty() else UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "Output"
	sub.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.9))
	sub.add_theme_constant_override("outline_size", 8)
	sub.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub.offset_top = 0
	sub.offset_bottom = 44
	button.add_child(sub)
	if def.is_empty():
		LockedFeature.wire(button, "cave_" + str(spec.key))
	else:
		button.pressed.connect(func() -> void:
			_selected = str(spec.key)
			_refresh_plates()
			_render_detail())
	_buttons[str(spec.key)] = button


static func _output_short(def: Dictionary) -> String:
	return "%s +%d/时" % [str(def.get("output_name", "")), int(def.get("per_hour", 0))]


func _refresh_plates() -> void:
	for key in _buttons:
		var plate := (_buttons[key] as Control).get_node("NamePlate") as PanelContainer
		var cut := "plate_label_gold_66" if key == _selected else "plate_label_cream_66"
		if ArtLib.qui(cut) != null:
			plate.add_theme_stylebox_override("panel", QKit.cut_box(cut, 18, 0))


## 下半薄荷底板从详情面板上沿开始（设计稿 1590）。
func sheet_anchor() -> Control:
	return _detail


func sheet_pad() -> float:
	return 8.0


func building_button(key: String) -> Button:
	return _buttons.get(key, null)


func upgrade_button() -> Button:
	return _upgrade


func enhance_entry_button() -> Button:
	return _enhance_entry


func selected_building() -> String:
	return _selected


func _render_detail() -> void:
	UiKit.clear(_detail_body)
	var spec: Dictionary = {}
	for entry in MAP:
		if str(entry.key) == _selected:
			spec = entry
	var def := _cave_def(str(spec.get("cave_id", "")))
	var row := UiKit.hbox(22)
	_detail_body.add_child(row)
	var tex: Texture2D = ArtLib.q("sprites/" + str(spec.sprite)) if ArtLib.has_q("sprites/%s.png" % str(spec.sprite)) else null
	row.add_child(QKit.slot(tex, 2, 170))
	var info := UiKit.vbox(10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(12)
	info.add_child(head)
	head.add_child(QKit.title(str(def.get("name", spec.get("name", ""))), 46, UiTokens.TEXT))
	head.add_child(QKit.tag(CaveView.level_text(def), "cream", 30, 16))
	info.add_child(UiKit.label("洞府建筑 · 等级与产出为展示数据", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", QKit.cut_box("info_bar_blue_62", 24, 0) if ArtLib.qui("info_bar_blue_62") != null else QSkin.custom(Color("dff1fb"), UiTokens.Q_COCOA, 3, 31, 0, 24, 0))
	bar.custom_minimum_size = Vector2(0, 62)
	var output := QKit.title(CaveView.output_text(def), 34, UiTokens.TEXT)
	output.name = "OutputLine"
	bar.add_child(output)
	info.add_child(bar)
	var foot := UiKit.hbox(12)
	_detail_body.add_child(foot)
	var others: Array[String] = []
	for building in CaveView.buildings():
		var mapped := false
		for entry in MAP:
			if str(entry.cave_id) == str(building.id):
				mapped = true
		if not mapped:
			others.append("%s %s" % [str(building.name), CaveView.level_text(building)])
	var note := UiKit.label("其他建筑：" + "、".join(others) if not others.is_empty() else "", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.clip_text = true
	foot.add_child(note)
	_enhance_entry = QKit.button("强化", "m", 100, 44)
	_enhance_entry.name = "EnhanceEntry"
	_enhance_entry.custom_minimum_size.x = 220
	_enhance_entry.tooltip_text = "去背包强化已穿戴的装备"
	_enhance_entry.pressed.connect(func() -> void: enhance_entry_requested.emit())
	foot.add_child(_enhance_entry)
	_upgrade = QKit.button("升级", "o", 100, 44)
	_upgrade.name = "UpgradeButton"
	_upgrade.custom_minimum_size.x = 290
	LockedFeature.wire(_upgrade, "cave_upgrade")
	foot.add_child(_upgrade)
