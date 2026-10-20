class_name BreakthroughPage
extends Control
## 境界突破弹窗（Q 版设计稿 q_breakthrough_popup）：底栏正中「突破」圆钮打开，居中盖在当前页上（外壳加遮罩）。
## 绶带标题「突破 · 下一境界」；舞台（当前 → 目标境界、战力提升牌、成功率环、打坐的主角）；
## 突破条件（修为、必须击败的首领，满足打勾）；属性提升（生命/攻击/防御/速度 突破前 → 后、战力前 → 后）；
## 「突破」大按钮（下写消耗）；首领没打时多一个「前往挑战」；底下「点击空白处关闭」。
## 条件没满足时按钮灰化。数值全部来自服务器 breakthrough（preview / rateBp / requiredStage），这里不自己算。

signal start_requested
signal goto_stage_requested(stage_slug: String)
signal close_requested

## 弹窗框在 1080 画布上的位置（设计稿 60,340,960,1440；状态栏 90 以下）。
const FRAME := Rect2(60, 340, 960, 1440)

var _view: Dictionary = {}
var _frame: PanelContainer
var _ribbon_text: Label
var _body: VBoxContainer
var _button: Button
var _button_title: Label
var _button_sub: Label
var _hint: Label
var _goto: Button
var _close_hint: Label
var _inset_top := 90.0


func _init() -> void:
	name = "BreakthroughPage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = PanelContainer.new()
	_frame.name = "PopupFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	add_child(_frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(scroll)
	_body = UiKit.vbox(18)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var ribbon := QKit.ribbon("突破", 52, 420, true)
	ribbon.name = "Ribbon"
	_ribbon_text = ribbon.find_child("RibbonText", true, false) as Label
	add_child(ribbon)
	_button = Button.new()
	_button.name = "StartButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Vector2(500, 156)
	QKit.style_button(_button, "o", 52)
	_button.custom_minimum_size = Vector2(500, 156)
	var labels := UiKit.vbox(0)
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	labels.offset_bottom = -10
	_button.add_child(labels)
	_button_title = QKit.outlined("突破", 72, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 12, HORIZONTAL_ALIGNMENT_CENTER)
	labels.add_child(_button_title)
	_button_sub = QKit.outlined("", 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 6, HORIZONTAL_ALIGNMENT_CENTER, false)
	labels.add_child(_button_sub)
	_button.pressed.connect(func() -> void: start_requested.emit())
	_goto = QKit.button("", "m", 100, 36)
	_goto.name = "GotoStageButton"
	_goto.visible = false
	_hint = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.name = "Hint"
	_close_hint = QKit.tag("点击空白处关闭", "dark", 32, 30).get_child(0) as Label
	var close_pill := _close_hint.get_parent() as Control
	close_pill.name = "CloseHint"
	add_child(close_pill)
	var close := Button.new()
	close.name = "CloseButton"
	close.focus_mode = Control.FOCUS_NONE
	close.flat = true
	var close_tex := ArtLib.qui("btn_close")
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBox = StyleBoxTexture.new() if close_tex != null and key != "focus" else StyleBoxEmpty.new()
		if box is StyleBoxTexture:
			(box as StyleBoxTexture).texture = close_tex
		close.add_theme_stylebox_override(key, box)
	if close_tex == null:
		close.text = "✕"
	close.pressed.connect(func() -> void: close_requested.emit())
	add_child(close)
	_layout()


## 刘海高度变了重新摆（弹窗按设计稿画布坐标，整体跟着状态栏下移）。
func apply_safe_area(inset: Vector4) -> void:
	_inset_top = inset.y
	_layout()


func _layout() -> void:
	var shift := _inset_top - 90.0
	_frame.position = Vector2(FRAME.position.x, FRAME.position.y + shift)
	_frame.size = FRAME.size + Vector2(0, 12)
	var ribbon := get_node("Ribbon") as Control
	ribbon.position = Vector2(540 - ribbon.custom_minimum_size.x / 2.0, 224 + shift)
	var pill := get_node("CloseHint") as Control
	pill.position = Vector2(340, 1814 + shift)
	pill.custom_minimum_size = Vector2(400, 60)
	var close := get_node("CloseButton") as Control
	close.position = Vector2(948, 312 + shift)
	close.size = Vector2(84, 89)


## 弹出动画（缩放 0.92 → 1）。
func pop_in() -> void:
	_frame.pivot_offset = _frame.size / 2.0
	_frame.scale = Vector2(0.92, 0.92)
	_frame.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_frame, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_frame, "modulate:a", 1.0, 0.12)


func view() -> Dictionary:
	return _view


func start_button() -> Button:
	return _button


func goto_button() -> Button:
	return _goto


func set_busy(value: bool) -> void:
	_button.disabled = value or not bool(_view.get("can_start", false))


func bind(state: Dictionary, _content: Dictionary, next_realm_name: String, _after_next_name: String = "") -> void:
	_view = BreakthroughView.build(state, next_realm_name)
	var has_next := bool(_view.has_next)
	_ribbon_text.text = "突破 · %s" % next_realm_name if has_next else "已至最高境界"
	UiKit.clear(_body)
	_body.add_child(_stage(str(state.get("realmName", "")), next_realm_name))
	_body.add_child(_conditions())
	_body.add_child(_stats())
	var foot := UiKit.vbox(8)
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	if _button.get_parent() != null:
		_button.get_parent().remove_child(_button)
	if _goto.get_parent() != null:
		_goto.get_parent().remove_child(_goto)
	if _hint.get_parent() != null:
		_hint.get_parent().remove_child(_hint)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	foot.add_child(_button)
	foot.add_child(_hint)
	_goto.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	foot.add_child(_goto)
	_body.add_child(foot)
	var can_start := bool(_view.can_start)
	_button.disabled = not can_start
	_button_title.text = "突破" if has_next else "已圆满"
	_button_sub.text = "消耗 修为 %s" % OfflineView.grouped(float(_view.cost)) if has_next else ""
	_hint.text = str(_view.hint)
	_goto.visible = has_next and bool(_view.has_gate) and not bool(_view.boss_ok)
	for connection in _goto.pressed.get_connections():
		_goto.pressed.disconnect(connection.callable)
	if _goto.visible:
		var slug := str(_view.gate_stage)
		_goto.text = "前往挑战 %s" % str(_view.gate_stage_name)
		_goto.custom_minimum_size.x = 460
		_goto.pressed.connect(func() -> void: goto_stage_requested.emit(slug))


## 舞台：境界行、战力提升牌（左）、成功率环（右）、主角坐莲台 + 灵气环。
func _stage(current_name: String, target_name: String) -> Control:
	var stage := Panel.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(0, 560)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	stage.add_theme_stylebox_override("panel", QKit.cut_box("well_teal", 0, 0) if ArtLib.qui("well_teal") != null else QSkin.custom(Color("cfeefa"), Color(0, 0, 0, 0), 0, 36, 0, 0, 0))
	var origin := Vector2(84, 410)
	var add := func(node: Control, rect: Rect2) -> void:
		node.position = rect.position - origin
		node.size = rect.size
		stage.add_child(node)
	for spec in [["sprites/fx_sunburst", Rect2(280, 450, 520, 520), 0.6], ["sprites/fx_ring_solid", Rect2(200, 690, 680, 280), 0.7], ["sprites/fx_ring_dashed", Rect2(260, 720, 560, 220), 0.8], ["sprites/lotus_platform", Rect2(310, 726, 460, 224), 1.0], ["sprites/hero_meditate", Rect2(340, 496, 400, 400), 1.0]]:
		var tex := TextureRect.new()
		tex.texture = ArtLib.q(str(spec[0])) if ArtLib.has_q(str(spec[0]) + ".png") else null
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if str(spec[0]).contains("hero") or str(spec[0]).contains("lotus") else TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.modulate.a = float(spec[2])
		add.call(tex, spec[1])
	var realm := PanelContainer.new()
	realm.name = "RealmRow"
	realm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	realm.add_theme_stylebox_override("panel", QKit.cut_box("plate_label_cream_66", 30, 0) if ArtLib.qui("plate_label_cream_66") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 33, 4, 30, 0))
	var row := UiKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	realm.add_child(row)
	row.add_child(QKit.title(current_name, 36, UiTokens.TEXT))
	row.add_child(QKit.title("→", 36, UiTokens.Q_ORANGE))
	row.add_child(QKit.title(target_name if bool(_view.has_next) else "—", 36, UiTokens.Q_BLUE_DARK))
	add.call(realm, Rect2(310, 432, 460, 71))
	var plate := PanelContainer.new()
	plate.name = "PowerGain"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", QKit.cut_box("plate_gold_r30", 14, 6) if ArtLib.qui("plate_gold_r30") != null else QSkin.custom(Color("ffe08a"), UiTokens.Q_COCOA, 4, 30, 6, 14, 6))
	var col := UiKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	plate.add_child(col)
	col.add_child(QKit.title("战力提升", 32, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var delta := int(_view.power_delta)
	col.add_child(QKit.outlined("%s%s" % ["+" if delta >= 0 else "", OfflineView.grouped(float(delta))], 50, UiTokens.Q_WHITE, UiTokens.Q_ORANGE_DARK, 10, HORIZONTAL_ALIGNMENT_CENTER))
	add.call(plate, Rect2(104, 470, 196, 141))
	add.call(_rate_ring(int(_view.rate_percent)), Rect2(810, 450, 176, 182))
	return stage


## 成功率环（SPEC_Q：radial_bg_176 + 顺时针 TextureProgressBar radial_fill_166 偏移 (5,5) + radial_center_132 偏移 (22,22)）。
func _rate_ring(percent: int) -> Control:
	var holder := Control.new()
	holder.name = "RateRing"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := QKit.cut_rect("radial_bg_176", Vector2(176, 182))
	holder.add_child(bg)
	var fill := TextureProgressBar.new()
	fill.name = "RateFill"
	fill.texture_progress = ArtLib.qui("radial_fill_166")
	fill.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	fill.max_value = 100
	fill.value = clampi(percent, 0, 100)
	fill.position = Vector2(5, 5)
	fill.size = Vector2(166, 166)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	var center := QKit.cut_rect("radial_center_132", Vector2(132, 132))
	center.position = Vector2(22, 22)
	holder.add_child(center)
	var col := UiKit.vbox(0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(22, 22)
	col.size = Vector2(132, 132)
	holder.add_child(col)
	col.add_child(QKit.title("成功率", 30, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(QKit.outlined("%d%%" % percent, 44, UiTokens.Q_WHITE, UiTokens.Q_MINT_DARK, 8, HORIZONTAL_ALIGNMENT_CENTER))
	return holder


func _section(title: String) -> Dictionary:
	var box := QKit.inset(Color("fcebd0"), 30, 22, 16)
	box.body.add_theme_constant_override("separation", 10)
	box.body.add_child(QKit.title(title, 32, UiTokens.TEXT_MUTED))
	return box


## 突破条件：修为（当前 / 所需）、必须击败的首领。满足的打勾。
func _conditions() -> Control:
	var box := _section("突破条件")
	box.panel.name = "Conditions"
	if not bool(_view.has_next):
		box.body.add_child(UiKit.label("当前已是最高境界", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
		return box.panel
	box.body.add_child(_condition_row("res_lotus", "修为已满" if bool(_view.cultivation_ok) else "修为", "%s / %s" % [OfflineView.grouped(float(_view.cultivation)), OfflineView.grouped(float(_view.cost))], bool(_view.cultivation_ok)))
	if bool(_view.has_gate):
		box.body.add_child(_condition_row("tab_adventure", "击败 %s" % str(_view.gate_boss), str(_view.gate_stage_name), bool(_view.boss_ok)))
	return box.panel


func _condition_row(icon_name: String, title: String, value: String, ok: bool) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ConditionRow"
	panel.add_theme_stylebox_override("panel", QKit.cut_box("row_cream_74", 18, 0) if ArtLib.qui("row_cream_74") != null else QSkin.custom(Color.WHITE, UiTokens.Q_COCOA, 4, 37, 4, 18, 0))
	panel.custom_minimum_size = Vector2(0, 80)
	var row := UiKit.hbox(14)
	panel.add_child(row)
	row.add_child(UiKit.icon(icon_name, 56))
	var name := QKit.title(title, 34, UiTokens.TEXT)
	name.custom_minimum_size = Vector2(260, 0)
	name.clip_text = true
	row.add_child(name)
	var mid := UiKit.label(value, UiTokens.FS_MICRO, UiTokens.Q_MINT_DARK if ok else UiTokens.Q_RED, HORIZONTAL_ALIGNMENT_CENTER)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.clip_text = true
	row.add_child(mid)
	row.add_child(UiKit.label("已满足" if ok else "未满足", UiTokens.FS_MICRO, UiTokens.Q_MINT_DARK if ok else UiTokens.Q_RED))
	row.add_child(QKit.check(ok, 56))
	return panel


## 属性提升：4 格（突破前 → 后、增量），右上战力前 → 后。数据来自 breakthrough.preview。
func _stats() -> Control:
	var box := _section("属性提升")
	box.panel.name = "StatsBox"
	var head := box.body.get_child(0) as Label
	box.body.remove_child(head)
	var top := UiKit.hbox(8)
	box.body.add_child(top)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(head)
	top.add_child(QKit.title("战力 %s" % OfflineView.grouped(float(_view.power_now)), 34, UiTokens.TEXT))
	top.add_child(QKit.title("→ %s" % OfflineView.grouped(float(_view.power_after)), 34, UiTokens.Q_ORANGE_DARK))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 14)
	box.body.add_child(grid)
	for row in _view.rows:
		grid.add_child(_stat_cell(str(row.name), float(row.before), float(row.after), float(row.delta)))
	return box.panel


func _stat_cell(stat_name: String, before: float, after: float, delta: float) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 88)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", QSkin.custom(Color.WHITE, UiTokens.Q_COCOA, 4, 24, 4, 16, 0))
	var row := UiKit.hbox(8)
	panel.add_child(row)
	row.add_child(QKit.title(stat_name, 32, UiTokens.TEXT))
	var values := UiKit.label("%d→%d" % [int(round(before)), int(round(after))], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	values.clip_text = true
	row.add_child(values)
	var gain := int(round(delta))
	row.add_child(QKit.outlined("%s%d%s" % ["+" if gain >= 0 else "", gain, "↑" if gain > 0 else ""], 36, UiTokens.Q_WHITE, UiTokens.Q_MINT_DARK, 8, HORIZONTAL_ALIGNMENT_RIGHT))
	return panel
