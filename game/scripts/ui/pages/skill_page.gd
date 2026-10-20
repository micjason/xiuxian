class_name SkillPage
extends VBoxContainer
## 功法页（Q 版设计稿 q_techniques）：
## 上面「已装备功法」面板：攻击 / 防御 / 生命三个功法位（这三类功法还没有：展示，点了提示暂未开放）+ 当前功法加成；
## 下面「功法列表」：后台配置的心法（真实名字、等级、修炼加成、状态：修炼中 / 已习得 / 未获得）。
## 「升级」「切换」按钮照设计显示，客户端还没接功法升级 / 切换接口，点了提示暂未开放；不发任何服务器请求。

## 上面三个功法位（设计稿 攻击 / 防御 / 生命）。
const EQUIP_SLOTS := [
	{"id": "atk", "name": "攻击", "chip": "red", "book": "book_atk"},
	{"id": "def", "name": "防御", "chip": "blue", "book": "book_def"},
	{"id": "hp", "name": "生命", "chip": "green", "book": "book_hp"},
]

var _view: Dictionary = {}
var _selected := ""
var _equipped: PanelContainer
var _bonus: Label
var _list: VBoxContainer
var _count: Label
var _hint: Label
var _slot_buttons: Array[Button] = []


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_equipped()
	var head := UiKit.hbox(UiTokens.SP_2)
	head.add_child(QKit.title("功法列表", 40, UiTokens.TEXT))
	var note := UiKit.label("心法同时只生效 1 本", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(note)
	_count = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.name = "LearnedCount"
	head.add_child(_count)
	add_child(head)
	var scroll := ScrollContainer.new()
	scroll.name = "SkillScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := UiKit.vbox(16)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	_list = UiKit.vbox(16)
	_list.name = "SkillList"
	column.add_child(_list)
	_hint = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(_hint)
	var orb_room := Control.new()
	orb_room.custom_minimum_size = Vector2(0, 96)
	orb_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb_room)


func _build_equipped() -> void:
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", -40)
	add_child(holder)
	var ribbon := QKit.ribbon("已装备功法", 40, 220, false)
	ribbon.z_index = 1
	holder.add_child(ribbon)
	var card := QKit.panel(UiTokens.Q_CREAM, 34, 24, 20)
	_equipped = card.panel
	_equipped.name = "EquippedPanel"
	holder.add_child(_equipped)
	var body := card.body as VBoxContainer
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 30)
	body.add_child(top_pad)
	var well := QKit.inset(Color("bfe8dd"), 30, 16, 14)
	body.add_child(well.panel)
	var row := UiKit.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	well.body.add_child(row)
	for spec in EQUIP_SLOTS:
		var cell := UiKit.vbox(6)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(cell)
		var chip := QKit.tag(str(spec.name), str(spec.chip), 30, 18)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(chip)
		var button := Button.new()
		button.name = "EquipSlot_%s" % str(spec.id)
		button.focus_mode = Control.FOCUS_NONE
		button.flat = true
		button.custom_minimum_size = Vector2(170, 176)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var tex: Texture2D = ArtLib.q("items/" + str(spec.book)) if ArtLib.has_q("items/%s.png" % str(spec.book)) else null
		var slot := QKit.slot(tex, -1, 170, "", "", Color.WHITE, true)
		slot.set_anchors_preset(Control.PRESET_FULL_RECT)
		button.add_child(slot)
		LockedFeature.wire(button, "skill_slot_" + str(spec.id))
		cell.add_child(button)
		_slot_buttons.append(button)
		cell.add_child(QKit.title("暂未开放", 32, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var bonus_bar := QKit.inset(UiTokens.Q_CARD, 31, 22, 8)
	bonus_bar.panel.custom_minimum_size = Vector2(0, 62)
	body.add_child(bonus_bar.panel)
	_bonus = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_bonus.name = "BonusLine"
	bonus_bar.body.add_child(_bonus)


## 下半薄荷底板从「已装备功法」面板上沿开始（设计稿 368）。
func sheet_anchor() -> Control:
	return _equipped


func sheet_pad() -> float:
	return 8.0


func bind(state: Dictionary, content: Dictionary) -> void:
	_view = SkillView.build(state, content)
	if _selected.is_empty() or not _has(_selected):
		_selected = str((_view.selected as Dictionary).get("slug", ""))
	_render()


func view() -> Dictionary:
	return _view


func selected_slug() -> String:
	return _selected


func select(slug: String) -> void:
	if _has(slug):
		_selected = slug
		_render()


func equip_slot_buttons() -> Array[Button]:
	return _slot_buttons


func _has(slug: String) -> bool:
	for card in _view.get("cards", []):
		if str(card.slug) == slug:
			return true
	return false


func _render() -> void:
	UiKit.clear(_list)
	var cards: Array = _view.get("cards", [])
	_count.text = "已习得 %d/%d" % [int(_view.get("learned_count", 0)), int(_view.get("total_count", 0))]
	_bonus.text = "功法加成：修炼速度 +%s%%" % SkillView._pct(float(_view.get("actual_bonus_percent", 0.0)) * 100.0)
	if cards.is_empty():
		_list.add_child(UiKit.wrap_label("后台还没有配置带修炼加成的功法。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
		return
	for card in cards:
		_list.add_child(_card(card))
	_hint.text = "功法升级、切换还没开放"


## 一张功法卡（设计稿 1008×158）：书格 124、《名字》、「心法」类型、Lv、加成；右侧 升级 / 切换 / 未获得，右上角状态。
func _card(card: Dictionary) -> Control:
	var status := str(card.status)
	var locked := status == "locked"
	var running := status == "running"
	var holder := Control.new()
	holder.name = "Skill_%s" % str(card.slug)
	holder.custom_minimum_size = Vector2(0, 166)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var cut := "card_current_gold" if running else ("card_locked" if locked else "card_apricot")
	panel.add_theme_stylebox_override("panel", QKit.cut_box(cut, 20, 10) if ArtLib.qui(cut) != null else QSkin.custom(UiTokens.Q_CARD, UiTokens.Q_COCOA, 4, 28, 6, 20, 10))
	holder.add_child(panel)
	var select_area := QKit.hit_area(panel)
	select_area.pressed.connect(select.bind(str(card.slug)))
	var row := UiKit.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var tex: Texture2D = ArtLib.q("items/book_other") if ArtLib.has_q("items/book_other.png") else ArtLib.icon("cat_scroll")
	row.add_child(QKit.slot(tex, -1 if locked else 1, 124, "", "", Color.WHITE, locked))
	var info := UiKit.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)
	var line := UiKit.hbox(10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(line)
	var title := QKit.title("《%s》" % str(card.name), 40, UiTokens.TEXT_MUTED if locked else UiTokens.TEXT)
	line.add_child(title)
	line.add_child(QKit.tag("心法", "grey" if locked else "mint", 30, 12))
	if not locked and int(card.get("level", 0)) > 0:
		line.add_child(QKit.title("Lv.%d" % int(card.level), 36, UiTokens.Q_ORANGE))
	info.add_child(UiKit.label(str(card.bonus_text) + (" · 离线同样生效" if not locked else ""), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	if locked:
		row.add_child(QKit.lock_row("未获得", 32))
	elif running:
		var up := QKit.button("升级", "o", 100, 40, 30)
		up.name = "UpgradeButton"
		up.custom_minimum_size.x = 196
		up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		LockedFeature.wire(up, "skill_upgrade")
		row.add_child(up)
	else:
		var swap := QKit.button("切换", "m", 100, 40)
		swap.name = "SwitchButton"
		swap.custom_minimum_size.x = 196
		swap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		LockedFeature.wire(swap, "skill_switch")
		row.add_child(swap)
	if running:
		var corner := QKit.tag("修炼中", "orange", 30, 14)
		corner.name = "StatusCorner"
		corner.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		corner.offset_left = -176
		corner.offset_right = -40
		corner.offset_top = -14
		corner.offset_bottom = 30
		holder.add_child(corner)
	return holder
