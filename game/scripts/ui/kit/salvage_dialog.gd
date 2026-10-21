class_name SalvageDialog
extends Control
## 分解装备弹窗（SPEC_Q §17.2，设计稿 q_salvage / q_salvage_selected；紫/橙二次确认 §17.9 q_salvage_confirm_rare）。
## 居中弹窗（不是底部面板），底图压暗 0.45。坐标按 1080×2340 稿、相对弹窗框左上角（稿上框 60,307，960×1666）；
## 行囊没满时不显示满包提示条，下面整体上移 126、框变矮 126。选择逻辑全在 SalvageModel。
## 只管界面：确认后发 decompose_requested(ids)，外壳（play_screen）调接口，成功后调 after_decompose 刷新（弹窗不关）。

signal decompose_requested(ids: Array)
signal toast_requested(text: String, good: bool)
signal closed

const FRAME_X := 60.0
const FRAME_W := 960.0
const FRAME_H_FULL := 1666.0
const STRIP_H := 126.0
const CELL := 150.0
const COL_GAP := 24.0
const ROW_PITCH := 186.0
const COLS := 5
const VISIBLE_ROWS := 4
const QUALITY_KEYS := ["white", "green", "blue", "purple", "orange"]
const QUALITY_WORDS := ["白", "绿", "蓝", "紫", "橙"]
const GREY := Color("b8a799")
const LABEL_GREY := Color("9a8b7e")
const OK_GREEN := Color("3c9a4e")
const PICK_ORANGE := Color("e07b24")
const RED := Color("d93a3f")
const NUM_FILL := Color("ffe27a")
const NUM_EDGE := Color("e07b24")

var model: SalvageModel = SalvageModel.new()
## 测试里关掉动画：确认后立即发信号。
var animate := true
var _full := false
var _used := 0
var _capacity := 0
var _inset := Vector4.ZERO

var _dim: ColorRect
var _frame: Panel
var _ribbon: Control
var _close: Button
var _hint: Control
var _strip: Panel
var _strip_text: Label
var _chips_well: Panel
var _chips: Array[Button] = []
var _grid_well: Panel
var _count_label: RichTextLabel
var _scroll: ScrollContainer
var _grid: Control
var _cells: Dictionary = {}
var _more_hint: Control
var _summary: Panel
var _sel_label: Label
var _qual_label: Label
var _refund_label: Label
var _gain_label: Label
var _cancel: Button
var _confirm: Button
var _confirm_title: Label
var _confirm_sub: Label
var _rare: Control
var _rare_line: RichTextLabel
var _rare_thumbs: HBoxContainer
var _rare_total: Label
var _rare_refund: Label
var _rare_gain: Label
var _last_gain := -1


func _init() -> void:
	name = "SalvageDialog"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.name = "Dimmer"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if SettingsView._tapped(event):
			close())
	add_child(_dim)
	_frame = Panel.new()
	_frame.name = "PopupFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	add_child(_frame)
	_build_strip()
	_build_chips()
	_build_grid()
	_build_summary()
	_build_buttons()
	_ribbon = QKit.ribbon("分解装备", 52, 340, true)
	_ribbon.name = "Ribbon"
	add_child(_ribbon)
	_close = _close_button()
	add_child(_close)
	_hint = QKit.tag("点击空白处关闭", "dark", 32, 30)
	_hint.name = "CloseHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_build_rare_confirm()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func apply_safe_area(inset: Vector4) -> void:
	_inset = inset
	_layout()


# ───────── 打开 / 刷新 / 关闭 ─────────

## 打开：一件都不选（负责人已定）。bag = 当前行囊（BagModel.from_state）。
func open(bag: BagModel) -> void:
	model = SalvageModel.from_bag(bag)
	_rare.visible = false
	_last_gain = -1
	_apply_bag(bag)
	visible = true
	move_to_front()
	_layout()


## 分解成功后：换成新行囊（保留还在的勾选——其实已全部分解掉），弹窗不关；行囊不满了满包条消失。
func after_decompose(bag: BagModel) -> void:
	model.refresh(bag)
	_apply_bag(bag)
	_layout()


func close() -> void:
	if not visible:
		return
	visible = false
	_rare.visible = false
	closed.emit()


func is_confirming_rare() -> bool:
	return _rare.visible


func _apply_bag(bag: BagModel) -> void:
	_used = bag.used_slots() if bag != null else 0
	_capacity = bag.capacity if bag != null else 0
	_full = bag != null and bag.is_full()
	_strip.visible = _full
	_strip_text.text = ""
	(_strip.get_node("StripTitle") as RichTextLabel).text = "[color=#4a3a33]行囊 [/color][color=#d93a3f]%d / %d[/color][color=#4a3a33] 已满[/color]" % [_used, _capacity]
	_render_grid()
	_render_state()


# ───────── 操作（测试也直接调） ─────────

func toggle_item(id: String) -> void:
	model.toggle(id)
	_render_state()


func toggle_quality(rarity: int) -> void:
	model.toggle_quality(rarity)
	_render_state()


## 点「确认分解」：N=0 提示；含紫 / 橙先二次确认；否则直接分解。
func press_confirm() -> void:
	if model.selected_count() == 0:
		toast_requested.emit("请先选择装备", false)
		return
	if model.needs_rare_confirm():
		_open_rare()
		return
	_do_decompose()


## 二次确认「再想想」：关确认，回到分解界面，保留勾选。
func rare_think_again() -> void:
	_rare.visible = false


func rare_confirm() -> void:
	_rare.visible = false
	_do_decompose()


func _do_decompose() -> void:
	var ids := model.selected_ids()
	if ids.is_empty():
		return
	if not animate or not is_inside_tree():
		decompose_requested.emit(ids)
		return
	# 格子依次缩小淡出（每格 0.06s 错开，最多算 8 格），然后再发请求。
	var tween := create_tween().set_parallel(true)
	var delay := 0.0
	for id in ids:
		var cell := _cells.get(id, null) as Control
		if cell == null:
			continue
		cell.pivot_offset = Vector2(CELL, CELL) / 2.0
		tween.tween_property(cell, "scale", Vector2(0.2, 0.2), 0.18).set_delay(delay)
		tween.tween_property(cell, "modulate:a", 0.0, 0.18).set_delay(delay)
		delay = minf(delay + 0.06, 0.42)
	tween.chain().tween_callback(func() -> void: decompose_requested.emit(ids))


# ───────── 布局 ─────────

func _frame_h() -> float:
	return FRAME_H_FULL - (0.0 if _full else STRIP_H)


## 满包条以下的内容在没满时上移 126。
func _dy() -> float:
	return 0.0 if _full else -STRIP_H


func _layout() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1080, 2340)
	var avail := view.y - _inset.y - _inset.w
	var h := _frame_h()
	var top := _inset.y + maxf(70.0, (avail - h) / 2.0)
	_frame.position = Vector2(FRAME_X, top)
	_frame.size = Vector2(FRAME_W, h)
	var dy := _dy()
	_chips_well.position = Vector2(40, 210 + dy)
	_grid_well.position = Vector2(40, 402 + dy)
	_summary.position = Vector2(40, 1266 + dy)
	_cancel.position = Vector2(40, 1492 + dy)
	_confirm.position = Vector2(500, 1492 + dy)
	_ribbon.size = _ribbon.custom_minimum_size
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, top - 62)
	_close.position = Vector2(FRAME_X + FRAME_W - 62, top - 36)
	_close.size = Vector2(84, 89)
	_hint.size = Vector2(400, 60)
	_hint.position = Vector2(340, top + h + 22)
	var box := _rare.get_node("RareFrame") as Control
	box.position = Vector2(110, top + 468 + dy)  # 稿：确认框 (110,775)，分解框顶 307
	var ribbon := _rare.get_node("RareRibbon") as Control
	ribbon.size = ribbon.custom_minimum_size
	ribbon.position = Vector2(540 - ribbon.custom_minimum_size.x / 2.0, box.position.y - 52)


# ───────── 搭界面 ─────────

func _well(node_name: String, size: Vector2) -> Panel:
	var well := Panel.new()
	well.name = node_name
	well.size = size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", ArtLib.q_nine("well_apricot") if ArtLib.qui("well_apricot") != null else QSkin.custom(Color("fcebd0"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0))
	_frame.add_child(well)
	return well


func _at(parent: Control, node: Control, pos: Vector2, size: Vector2 = Vector2.ZERO) -> Control:
	node.position = pos
	if size != Vector2.ZERO:
		node.size = size
		node.custom_minimum_size = size
	parent.add_child(node)
	return node


func _rich(size: int, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align as HorizontalAlignment
	label.add_theme_font_override("normal_font", ArtLib.title_font())
	label.add_theme_font_size_override("normal_font_size", size)
	return label


func _tex(name_in_ui: String, size: Vector2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.qui(name_in_ui)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.custom_minimum_size = size
	node.size = size
	return node


## 满包提示（稿 391–495）：浅红条 + 背包图标 + badge_full +「行囊 100 / 100 已满」+ 说明。
func _build_strip() -> void:
	_strip = Panel.new()
	_strip.name = "BagFullStrip"
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_stylebox_override("panel", QSkin.custom(Color("ffe6dc"), Color("f3a08a"), 4, 30, 0, 0, 0))
	_at(_frame, _strip, Vector2(40, 84), Vector2(880, 104))
	var pouch := TextureRect.new()
	pouch.texture = ArtLib.icon("tab_bag")
	pouch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pouch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pouch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_strip, pouch, Vector2(22, 8), Vector2(88, 88))
	_at(_strip, _tex("badge_full", Vector2(44, 44)), Vector2(80, 4))
	var title := _rich(36)
	title.name = "StripTitle"
	_at(_strip, title, Vector2(132, 6), Vector2(720, 50))
	_strip_text = UiKit.label("", 1, Color.WHITE)
	_strip_text.visible = false
	_strip.add_child(_strip_text)
	var sub := UiKit.label("新装备不会再掉落，分解后才能继续拾取", 28, Color("b0614a"))
	_at(_strip, sub, Vector2(132, 56), Vector2(720, 40))


## 品质一键全选（稿 517–687）：5 个胶囊 156×72、间距 12，从 x126 起，y591。
func _build_chips() -> void:
	_chips_well = _well("QualityWell", Vector2(880, 170))
	_at(_chips_well, QKit.title("按品质一键全选", 32, LABEL_GREY), Vector2(34, 16), Vector2(400, 48))
	var tip := UiKit.label("再点一次取消该品质", 26, GREY, HORIZONTAL_ALIGNMENT_RIGHT)
	_at(_chips_well, tip, Vector2(440, 22), Vector2(406, 40))
	for rarity in QUALITY_KEYS.size():
		var chip := Button.new()
		chip.name = "Chip_" + QUALITY_KEYS[rarity]
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(toggle_quality.bind(rarity))
		var row := UiKit.hbox(6)
		row.name = "Row"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(row)
		var dot := _tex("qdot_" + QUALITY_KEYS[rarity], Vector2(32, 32))
		dot.name = "Dot"
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var word := QKit.title(str(QUALITY_WORDS[rarity]), 38, UiTokens.rarity_color(rarity).darkened(0.25))
		word.name = "Word"
		word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(word)
		_at(_chips_well, chip, Vector2(26 + rarity * 168, 74), Vector2(156, 72))
		_chips.append(chip)


func _style_chip(chip: Button, rarity: int, on: bool, empty: bool) -> void:
	var cut: String = ("qchip_on_" + QUALITY_KEYS[rarity]) if on else "qchip_off_72"
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBox
		if state == "focus":
			box = StyleBoxEmpty.new()
		elif ArtLib.qui(cut) != null:
			box = ArtLib.q_nine(cut)
		else:
			box = QSkin.custom(UiTokens.rarity_color(rarity) if on else UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 36, 0, 0, 0)
		chip.add_theme_stylebox_override(state, box)
	var dot := chip.get_node("Row/Dot") as TextureRect
	dot.texture = ArtLib.qui("check_box_on") if on else ArtLib.qui("qdot_" + QUALITY_KEYS[rarity])
	dot.custom_minimum_size = Vector2(40, 40) if on else Vector2(32, 32)
	var word := chip.get_node("Row/Word") as Label
	if on:
		word.add_theme_color_override("font_color", Color.WHITE)
		word.add_theme_color_override("font_outline_color", UiTokens.rarity_color(rarity).darkened(0.45))
		word.add_theme_constant_override("outline_size", 9)
	else:
		word.add_theme_color_override("font_color", UiTokens.rarity_color(rarity).darkened(0.25))
		word.add_theme_constant_override("outline_size", 0)
	chip.modulate = Color(1, 1, 1, 0.55) if empty else Color.WHITE


## 装备格（稿 709–1551）：标题 +「已选 N / 总数」；5 列 150 格，列距 24，行距 186，第一行 y793。
func _build_grid() -> void:
	_grid_well = _well("GridWell", Vector2(880, 842))
	_at(_grid_well, QKit.title("选择要分解的装备", 32, LABEL_GREY), Vector2(34, 22), Vector2(420, 48))
	_count_label = _rich(30, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label.name = "SelectedCount"
	_at(_grid_well, _count_label, Vector2(440, 24), Vector2(406, 44))
	_scroll = ScrollContainer.new()
	_scroll.name = "GridScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_at(_grid_well, _scroll, Vector2(7, 74), Vector2(866, 760))
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_more_hint())
	_grid = Control.new()
	_grid.name = "Grid"
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_grid)
	_more_hint = Control.new()
	_more_hint.name = "MoreHint"
	_more_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.988, 0.922, 0.816, 0.0))
	grad.set_color(1, Color(0.988, 0.922, 0.816, 1.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	fade.texture = gtex
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_more_hint, fade, Vector2.ZERO, Vector2(866, 110))
	_at(_more_hint, UiKit.label("↓ 下滑查看更多（已穿戴的装备不在这里）", 26, GREY, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0, 66), Vector2(866, 40))
	_at(_grid_well, _more_hint, Vector2(7, 724), Vector2(866, 110))


func _render_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	var list := model.items
	var rows := int(ceil(float(list.size()) / COLS))
	_grid.custom_minimum_size = Vector2(866, maxf(1.0, rows * ROW_PITCH))
	for index in list.size():
		var item: Dictionary = list[index]
		var cell := _cell(item)
		cell.position = Vector2(10 + (index % COLS) * (CELL + COL_GAP), 16 + int(index / COLS) * ROW_PITCH)
		_grid.add_child(cell)
		_cells[str(item.get("id", ""))] = cell
	var empty := UiKit.label("行囊里没有可以分解的装备（已穿戴的装备不在这里）", 30, GREY, HORIZONTAL_ALIGNMENT_CENTER)
	empty.name = "EmptyHint"
	empty.visible = list.is_empty()
	empty.position = Vector2(0, 300)
	empty.size = Vector2(866, 60)
	_grid.add_child(empty)
	_scroll.scroll_vertical = 0
	_update_more_hint()


func _cell(item: Dictionary) -> Button:
	var id := str(item.get("id", ""))
	var cell := Button.new()
	cell.name = "Cell_" + id
	cell.focus_mode = Control.FOCUS_NONE
	cell.size = Vector2(CELL, CELL + 36)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		cell.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	cell.pressed.connect(toggle_item.bind(id))
	var ring := Panel.new()
	ring.name = "Ring"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_theme_stylebox_override("panel", ArtLib.q_nine("ring_set_current") if ArtLib.qui("ring_set_current") != null else QSkin.custom(Color(0, 0, 0, 0), PICK_ORANGE, 6, 36, 0, 0, 0))
	ring.position = Vector2(-10, -10)
	ring.size = Vector2(CELL + 20, CELL + 20)
	ring.visible = false
	cell.add_child(ring)
	var art := KitStyle.icon_for(item)
	var level := int(item.get("enhance", 0))
	var slot := QKit.slot(art.get("texture", null) as Texture2D, int(item.get("rarity", 0)), int(CELL), "", ("+%d" % level) if level > 0 else "")
	slot.name = "Slot"
	slot.position = Vector2.ZERO
	slot.size = Vector2(CELL, CELL)
	cell.add_child(slot)
	var box := _tex("check_box_off", Vector2(56, 56))
	box.name = "Check"
	box.position = Vector2(CELL - 44, -12)
	cell.add_child(box)
	var word := UiKit.label(str(item.get("rarity_name", "")), 24, UiTokens.rarity_color(int(item.get("rarity", 0))).darkened(0.3), HORIZONTAL_ALIGNMENT_CENTER)
	word.position = Vector2(0, CELL - 20)
	word.z_index = 1
	word.size = Vector2(CELL, 30)
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(word)
	return cell


func _update_more_hint() -> void:
	var rows := int(ceil(float(model.items.size()) / COLS))
	var bar := _scroll.get_v_scroll_bar()
	var at_end := bar.value + bar.page >= bar.max_value - 4.0 if bar.max_value > 0 else true
	_more_hint.visible = rows > VISIBLE_ROWS and not (at_end and bar.value > 0)


## 汇总（稿 1573–1769）：金色条；左「已选 N 件」+ 品质件数 + 强化返还；右「将获得」+ 精粹图标 +「炼器精粹」+「×N」。
func _build_summary() -> void:
	_summary = Panel.new()
	_summary.name = "Summary"
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary.add_theme_stylebox_override("panel", QSkin.custom(Color("ffedc7"), UiTokens.Q_COCOA, 4, 34, 0, 0, 0))
	_at(_frame, _summary, Vector2(40, 1266), Vector2(880, 196))
	_sel_label = QKit.title("", 38, UiTokens.TEXT)
	_sel_label.name = "SelectedLabel"
	_at(_summary, _sel_label, Vector2(34, 26), Vector2(380, 56))
	_qual_label = UiKit.label("", 28, LABEL_GREY)
	_qual_label.name = "QualityLine"
	_at(_summary, _qual_label, Vector2(34, 88), Vector2(400, 42))
	_refund_label = UiKit.label("", 26, OK_GREEN)
	_refund_label.name = "RefundLine"
	_at(_summary, _refund_label, Vector2(34, 134), Vector2(400, 40))
	_at(_summary, QKit.title("将获得", 32, LABEL_GREY), Vector2(440, 22), Vector2(140, 46))
	var icon := TextureRect.new()
	icon.texture = ArtLib.q("items/refine_essence")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_summary, icon, Vector2(430, 70), Vector2(112, 112))
	_at(_summary, QKit.title("炼器精粹", 32, UiTokens.TEXT), Vector2(590, 22), Vector2(200, 46))
	_gain_label = QKit.outlined("×0", 72, NUM_FILL, NUM_EDGE, 11)
	_gain_label.name = "GainLabel"
	_at(_summary, _gain_label, Vector2(560, 74), Vector2(300, 100))


## 按钮（稿 1799–1923）：左薄荷「取 消」，右橙「确认分解」+ 副标「分解 N 件」；各 420 宽，间距 40。
func _build_buttons() -> void:
	_cancel = QKit.button("取 消", "m", 124, 48)
	_cancel.name = "CancelButton"
	_cancel.pressed.connect(close)
	_at(_frame, _cancel, Vector2(40, 1492), Vector2(420, 130))
	_confirm = QKit.button("", "o", 124, 44)
	_confirm.name = "ConfirmButton"
	_confirm.pressed.connect(press_confirm)
	var col := UiKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -8
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(col)
	_confirm_title = QKit.outlined("确认分解", 46, Color.WHITE, UiTokens.Q_COCOA, 9, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_confirm_title)
	_confirm_sub = QKit.outlined("", 28, Color.WHITE, UiTokens.Q_COCOA, 7, HORIZONTAL_ALIGNMENT_CENTER)
	_confirm_sub.name = "ConfirmSub"
	col.add_child(_confirm_sub)
	_at(_frame, _confirm, Vector2(500, 1492), Vector2(420, 130))


## 勾选一变就重算（格子勾、胶囊、已选数、汇总、按钮）。
func _render_state() -> void:
	for id in _cells:
		var cell := _cells[id] as Control
		var on := model.is_selected(str(id))
		(cell.get_node("Ring") as CanvasItem).visible = on
		(cell.get_node("Check") as TextureRect).texture = ArtLib.qui("check_box_on" if on else "check_box_off")
	for rarity in _chips.size():
		_style_chip(_chips[rarity], rarity, model.chip_on(rarity), model.count_of(rarity) == 0)
	var n := model.selected_count()
	_count_label.text = "[color=#9a8b7e]已选 [/color][color=#e07b24]%d[/color][color=#9a8b7e] / %d[/color]" % [n, model.total()]
	_sel_label.text = "已选 %d 件" % n
	if n == 0:
		_qual_label.text = "点格子或上面的品质来勾选"
		_qual_label.add_theme_color_override("font_color", GREY)
		_qual_label.add_theme_font_size_override("font_size", 26)
	else:
		_qual_label.text = model.quality_line()
		_qual_label.add_theme_color_override("font_color", LABEL_GREY)
		_qual_label.add_theme_font_size_override("font_size", 28)
	var refund := model.total_refund()
	_refund_label.text = "含强化返还 +%s" % QKit.grouped(refund)
	_refund_label.visible = n > 0 and refund > 0
	var gain := model.total_gain()
	_gain_label.text = "×%s" % QKit.grouped(gain)
	_gain_label.add_theme_color_override("font_color", NUM_FILL if n > 0 else GREY)
	_gain_label.add_theme_color_override("font_outline_color", NUM_EDGE if n > 0 else Color("d8cabb"))
	if gain != _last_gain and _last_gain >= 0 and is_inside_tree():
		_bounce(_gain_label)
	_last_gain = gain
	var state := model.confirm_state()
	QKit.style_button(_confirm, "o" if bool(state.enabled) else "g", 44)
	_confirm.text = ""
	_confirm_sub.text = str(state.sub)


func _bounce(node: Control) -> void:
	node.pivot_offset = node.size / 2.0
	var tween := create_tween()
	tween.tween_property(node, "scale", Vector2(1.12, 1.12), 0.075)
	tween.tween_property(node, "scale", Vector2.ONE, 0.075)


# ───────── 紫 / 橙二次确认（17.9） ─────────

func _build_rare_confirm() -> void:
	_rare = Control.new()
	_rare.name = "RareConfirm"
	_rare.visible = false
	_rare.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rare.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(30.0 / 255.0, 20.0 / 255.0, 15.0 / 255.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if SettingsView._tapped(event):
			rare_think_again())
	_rare.add_child(dim)
	var box := Panel.new()
	box.name = "RareFrame"
	box.size = Vector2(860, 790)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	_rare.add_child(box)
	_rare_line = _rich(42, HORIZONTAL_ALIGNMENT_CENTER)
	_rare_line.name = "RareLine"
	_at(box, _rare_line, Vector2(0, 62), Vector2(860, 60))
	_at(box, UiKit.label("分解后无法恢复，请确认", 30, RED, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0, 132), Vector2(860, 44))
	var groove := Panel.new()
	groove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groove.add_theme_stylebox_override("panel", QSkin.custom(Color("fcebd0"), Color(0, 0, 0, 0), 0, 30, 0, 0, 0))
	_at(box, groove, Vector2(30, 204), Vector2(800, 214))
	_rare_thumbs = UiKit.hbox(24)
	_rare_thumbs.name = "RareThumbs"
	_rare_thumbs.alignment = BoxContainer.ALIGNMENT_CENTER
	_rare_thumbs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(groove, _rare_thumbs, Vector2(0, 16), Vector2(800, 190))
	var gold := Panel.new()
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold.add_theme_stylebox_override("panel", QSkin.custom(Color("ffedc7"), UiTokens.Q_COCOA, 4, 30, 0, 0, 0))
	_at(box, gold, Vector2(30, 442), Vector2(800, 150))
	_rare_total = QKit.title("", 34, UiTokens.TEXT)
	_rare_total.name = "RareTotal"
	_at(gold, _rare_total, Vector2(28, 26), Vector2(330, 50))
	_rare_refund = UiKit.label("", 26, OK_GREEN)
	_at(gold, _rare_refund, Vector2(28, 84), Vector2(330, 40))
	_at(gold, QKit.title("将获得", 30, LABEL_GREY), Vector2(350, 50), Vector2(110, 46))
	var icon := TextureRect.new()
	icon.texture = ArtLib.q("items/refine_essence")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(gold, icon, Vector2(458, 26), Vector2(96, 96))
	_rare_gain = QKit.outlined("", 64, NUM_FILL, NUM_EDGE, 11)
	_rare_gain.name = "RareGain"
	_at(gold, _rare_gain, Vector2(560, 30), Vector2(240, 90))
	var think := QKit.button("再想想", "m", 100, 44)
	think.name = "RareThink"
	think.pressed.connect(rare_think_again)
	_at(box, think, Vector2(40, 626), Vector2(370, 112))
	var ok := QKit.button("确认分解", "o", 100, 44)
	ok.name = "RareOk"
	ok.pressed.connect(rare_confirm)
	_at(box, ok, Vector2(450, 626), Vector2(370, 112))
	var ribbon := QKit.ribbon("确认分解", 48, 380, true)
	ribbon.name = "RareRibbon"
	_rare.add_child(ribbon)
	add_child(_rare)


func _open_rare() -> void:
	var parts: Array[String] = []
	for rarity in [3, 4]:
		var n := model.selected_of(rarity)
		if n > 0:
			parts.append("[color=#%s]%s ×%d[/color]" % [UiTokens.rarity_color(rarity).darkened(0.25).to_html(false), SalvageModel.RARE_WORDS[rarity], n])
	_rare_line.text = "[color=#4a3a33]包含 [/color]" + "[color=#4a3a33] · [/color]".join(parts)
	for child in _rare_thumbs.get_children():
		_rare_thumbs.remove_child(child)
		child.queue_free()
	var preview := model.rare_preview()
	for item in preview.shown:
		var col := UiKit.vbox(4)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var art := KitStyle.icon_for(item)
		var level := int(item.get("enhance", 0))
		col.add_child(QKit.slot(art.get("texture", null) as Texture2D, int(item.rarity), 150, "", ("+%d" % level) if level > 0 else ""))
		col.add_child(UiKit.label(SalvageModel.rare_caption(item), 24, LABEL_GREY, HORIZONTAL_ALIGNMENT_CENTER))
		_rare_thumbs.add_child(col)
	if int(preview.more) > 0:
		var more := Panel.new()
		more.custom_minimum_size = Vector2(150, 150)
		more.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		more.add_theme_stylebox_override("panel", QSkin.custom(Color("e3d9cc"), UiTokens.Q_COCOA, 4, 36, 0, 0, 0))
		var label := QKit.title("+%d" % int(preview.more), 44, LABEL_GREY, HORIZONTAL_ALIGNMENT_CENTER)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.add_child(label)
		_rare_thumbs.add_child(more)
	_rare_total.text = "共分解 %d 件" % model.selected_count()
	var refund := model.total_refund()
	_rare_refund.text = "含强化返还 +%s" % QKit.grouped(refund)
	_rare_refund.visible = refund > 0
	_rare_gain.text = "×%s" % QKit.grouped(model.total_gain())
	_rare.visible = true
	_rare.move_to_front()
	_layout()


func _close_button() -> Button:
	var button := Button.new()
	button.name = "CloseButton"
	button.focus_mode = Control.FOCUS_NONE
	var close_tex := ArtLib.qui("btn_close")
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBox = StyleBoxTexture.new() if close_tex != null and key != "focus" else StyleBoxEmpty.new()
		if box is StyleBoxTexture:
			(box as StyleBoxTexture).texture = close_tex
		button.add_theme_stylebox_override(key, box)
	if close_tex == null:
		button.text = "✕"
	button.pressed.connect(close)
	return button
