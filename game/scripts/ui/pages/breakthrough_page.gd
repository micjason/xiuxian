class_name BreakthroughPage
extends Control
## 境界突破弹窗（Q 版设计稿 q_breakthrough_popup）：底栏正中「突破」圆钮打开，居中盖在当前页上（外壳加遮罩）。
## 绶带标题「突破 · 下一境界」；舞台（当前 → 目标境界、战力提升牌、成功率环、打坐的主角）；
## 突破条件（修为、必须击败的首领，满足打勾）；属性提升（生命/攻击/防御/速度 突破前 → 后、战力前 → 后）；
## 「突破」大按钮（下写消耗）；首领没打时多一个「前往挑战」；底下「点击空白处关闭」。
## 条件没满足时按钮灰化。数值全部来自服务器 breakthrough（preview / rateBp / requiredStage），这里不自己算。
## 动画（2026-10-20 动画交付）：弹窗 ui_popup 的 open / close（README 2b）；舞台用 breakthrough_fx（README 4）：
## 平时 idle（法阵慢转、光晕），点「突破」播 charge（进度条充满 + 水波纹），服务器回成功后播 success（光柱、光环、星光、
## 「突破成功」横幅）；失败回到 idle。横幅从场景默认的 y-360（会压住「当前 → 目标境界」行和两侧的战力牌、成功率环）
## 挪到主角脚下（TITLE_Y），和舞台上的文字、牌子都不重叠。播动画期间新的状态先存着，播完再重画（不打断动画）。

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
var _fx: Control  # ui_popup 外壳；没有动画交付时为 null
var _host: Control
var _break_fx: Node2D
var _fx_running := false
var _pending_bind: Array = []

## 突破特效在舞台里的锚点（设计稿 (540, 892) − 舞台左上 (84, 410)）和「突破成功」横幅的 y（相对锚点）。
const FX_ANCHOR := Vector2(456, 482)
const TITLE_Y := 0.0


func _init() -> void:
	name = "BreakthroughPage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_host = self
	_fx = QFx.popup_shell()
	if _fx != null:
		# 遮罩只管画（淡入淡出），点空白处关闭仍由外壳底下那层透明遮罩接
		_fx.name = "PopupFx"
		(_fx.get_node("Backdrop") as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fx)
		_host = QFx.popup_content(_fx)
	_frame = PanelContainer.new()
	_frame.name = "PopupFrame"
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	_host.add_child(_frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_frame.add_child(scroll)
	_body = UiKit.vbox(18)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var ribbon := QKit.ribbon("突破", 52, 420, true)
	ribbon.name = "Ribbon"
	_ribbon_text = ribbon.find_child("RibbonText", true, false) as Label
	_host.add_child(ribbon)
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
	QFx.bounce(_button)
	_goto = QKit.button("", "m", 100, 36)
	_goto.name = "GotoStageButton"
	_goto.visible = false
	_hint = UiKit.label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.name = "Hint"
	_close_hint = QKit.tag("点击空白处关闭", "dark", 32, 30).get_child(0) as Label
	var close_pill := _close_hint.get_parent() as Control
	close_pill.name = "CloseHint"
	_host.add_child(close_pill)
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
	_host.add_child(close)
	_layout()


## 刘海高度变了重新摆（弹窗按设计稿画布坐标，整体跟着状态栏下移）。
func apply_safe_area(inset: Vector4) -> void:
	_inset_top = inset.y
	_layout()


func _layout() -> void:
	var shift := _inset_top - 90.0
	_frame.position = Vector2(FRAME.position.x, FRAME.position.y + shift)
	_frame.size = FRAME.size + Vector2(0, 12)
	var ribbon := _host.get_node("Ribbon") as Control
	ribbon.position = Vector2(540 - ribbon.custom_minimum_size.x / 2.0, 224 + shift)
	var pill := _host.get_node("CloseHint") as Control
	pill.position = Vector2(340, 1814 + shift)
	pill.custom_minimum_size = Vector2(400, 60)
	var close := _host.get_node("CloseButton") as Control
	close.position = Vector2(948, 312 + shift)
	close.size = Vector2(84, 89)
	if _fx != null:
		QFx.set_popup_pivot(_fx, Rect2(_frame.position, _frame.size))


## 弹出动画：ui_popup 的 open（遮罩淡入 + 面板 0.55 → 1.06 → 1）；没有动画交付时缩放 0.92 → 1。
func pop_in() -> void:
	if _fx != null:
		QFx.play(_fx, "open")
		return
	_frame.pivot_offset = _frame.size / 2.0
	_frame.scale = Vector2(0.92, 0.92)
	_frame.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.tween_property(_frame, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_frame, "modulate:a", 1.0, 0.12)


## 关闭动画（ui_popup 的 close，0.22s），播完调 done；没有动画交付时立刻调。
func pop_out(done: Callable) -> void:
	if _fx == null:
		done.call()
		return
	QFx.play(_fx, "close")
	get_tree().create_timer(0.24).timeout.connect(done)


func has_popup_fx() -> bool:
	return _fx != null


func view() -> Dictionary:
	return _view


## ---- 突破特效（breakthrough_fx）----

func break_fx() -> Node2D:
	return _break_fx


func fx_running() -> bool:
	return _fx_running


## 点「突破」：充能（2s）。服务器结果回来前就开始播。
func play_charge() -> void:
	if _break_fx == null:
		return
	_fx_running = true
	QFx.play(_break_fx, "charge")


## 成功：光柱、光环、星光、「突破成功」横幅（2.4s），播完返回。
func play_success() -> void:
	if _break_fx == null:
		return
	_fx_running = true
	var ap := QFx.player(_break_fx)
	if ap == null or not ap.has_animation("success"):
		return
	ap.play("success")
	await ap.animation_finished


## 结束特效：回到 idle，补上播动画期间收到的新状态。
func finish_fx() -> void:
	_fx_running = false
	if _break_fx != null:
		QFx.play(_break_fx, "idle")
	if not _pending_bind.is_empty():
		var args := _pending_bind
		_pending_bind = []
		bind(args[0], args[1], args[2], args[3])


## 「突破成功」横幅（场景 Front/Title/Box）在画布上的矩形（按缩放 1 算，测试 / 截图核对用）。
func success_title_rect() -> Rect2:
	if _break_fx == null:
		return Rect2()
	var box := _break_fx.get_node("Front/Title/Box") as Control
	var title := _break_fx.get_node("Front/Title") as Node2D
	var origin := title.get_global_transform().origin
	var scale := _break_fx.get_global_transform().get_scale()
	return Rect2(origin + Vector2(box.offset_left, box.offset_top) * scale, Vector2(box.offset_right - box.offset_left, box.offset_bottom - box.offset_top) * scale)


func start_button() -> Button:
	return _button


func goto_button() -> Button:
	return _goto


func set_busy(value: bool) -> void:
	_button.disabled = value or not bool(_view.get("can_start", false))


var _bind_sig := 0

func bind(state: Dictionary, _content: Dictionary, next_realm_name: String, _after_next_name: String = "") -> void:
	if _fx_running:
		_pending_bind = [state, _content, next_realm_name, _after_next_name]
		return
	_view = BreakthroughView.build(state, next_realm_name)
	# v14：心跳每次都 bind，内容没变就不重建（原来每次重建约 120ms，滚动时每隔十几秒卡一下）。
	var sig := hash([_view, str(state.get("realmName", "")), next_realm_name, str((state.get("appearance", {}) as Dictionary).get("quality", "") if typeof(state.get("appearance", null)) == TYPE_DICTIONARY else "")])
	if sig == _bind_sig and _body.get_child_count() > 0:
		return
	_bind_sig = sig
	var has_next := bool(_view.has_next)
	_ribbon_text.text = "突破 · %s" % next_realm_name if has_next else "已至最高境界"
	if _break_fx != null and _break_fx.get_parent() != null:
		_break_fx.get_parent().remove_child(_break_fx)  # 特效和主角复用，不随每次心跳重建
	UiKit.clear(_body)
	_body.add_child(_stage(str(state.get("realmName", "")), next_realm_name, state.get("appearance", null)))
	_apply_break_outfit(state.get("appearance", null))
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
func _stage(current_name: String, target_name: String, appearance: Variant = null) -> Control:
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
	if _break_fx == null:
		_break_fx = _make_break_fx()
	if _break_fx != null:
		_break_fx.position = FX_ANCHOR
		stage.add_child(_break_fx)
	var statics := [["sprites/fx_sunburst", Rect2(280, 450, 520, 520), 0.6], ["sprites/fx_ring_solid", Rect2(200, 690, 680, 280), 0.7], ["sprites/fx_ring_dashed", Rect2(260, 720, 560, 220), 0.8], ["sprites/lotus_platform", Rect2(310, 726, 460, 224), 1.0], ["sprites/hero_meditate", Rect2(340, 496, 400, 400), 1.0]]
	for spec in ([] if _break_fx != null else statics):
		var tex := TextureRect.new()
		tex.texture = ArtLib.q(str(spec[0])) if ArtLib.has_q(str(spec[0]) + ".png") else null
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if str(spec[0]).contains("hero") or str(spec[0]).contains("lotus") else TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.modulate.a = float(spec[2])
		if str(spec[0]).contains("hero"):
			tex.name = "MeditateArt"
			var outfit := OutfitAppearance.texture(appearance, "meditate")
			if outfit != null:
				tex.texture = outfit
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


## 突破特效 + 莲台 + 动画主角（README 4：HeroSlot 里放莲台和主角，主角缩放 400/706，坐垫隐藏）。没有交付返回 null。
func _make_break_fx() -> Node2D:
	var fx := QFx.make(QFx.BREAKTHROUGH) as Node2D
	if fx == null:
		return null
	fx.name = "BreakFx"
	var title := fx.get_node_or_null("Front/Title") as Node2D
	if title != null:
		title.position = Vector2(0, TITLE_Y)
	# 横幅挪到主角脚下后会和主角重叠：主角部件自带 z_index（最高 20），前景层要比它高才盖得住
	var front := fx.get_node_or_null("Front") as CanvasItem
	if front != null:
		front.z_index = 30
	var slot := fx.get_node("HeroSlot") as Node2D
	if ArtLib.has_q("sprites/lotus_platform.png"):
		var lotus := Sprite2D.new()
		lotus.name = "Lotus"
		lotus.texture = ArtLib.q("sprites/lotus_platform")
		lotus.scale = Vector2.ONE * (460.0 / lotus.texture.get_width())
		lotus.position = Vector2(0, -54)  # 设计稿莲台 (310,726,460,224) 的中心 (540, 838)
		slot.add_child(lotus)
	var hero := QFx.make(QFx.HERO) as Node2D
	if hero != null:
		hero.name = "Hero"
		hero.scale = Vector2.ONE * (400.0 / 706.0)
		hero.position = Vector2(0, -0.5)
		var seat := hero.get_node_or_null("Rig/Cushion") as CanvasItem
		if seat != null:
			seat.visible = false
		slot.add_child(hero)
	QFx.play(fx, "idle")
	return fx


func _apply_break_outfit(appearance: Variant) -> void:
	if _break_fx == null:
		return
	var slot := _break_fx.get_node_or_null("HeroSlot") as Node2D
	if slot == null:
		return
	var hero := slot.get_node_or_null("Hero") as CanvasItem
	var outfit := slot.get_node_or_null("OutfitMeditate") as Sprite2D
	var tex := OutfitAppearance.texture(appearance, "meditate")
	if tex == null:
		if outfit != null:
			outfit.visible = false
		if hero != null:
			hero.visible = true
		return
	if outfit == null:
		outfit = Sprite2D.new()
		outfit.name = "OutfitMeditate"
		outfit.centered = true
		slot.add_child(outfit)
	outfit.texture = tex
	outfit.scale = Vector2.ONE * (400.0 / maxf(tex.get_width(), 1))
	outfit.position = Vector2(0, -0.5)
	outfit.visible = true
	if hero != null:
		hero.visible = false


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
