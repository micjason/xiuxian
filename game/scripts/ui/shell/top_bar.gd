class_name TopBar
extends Control
## 顶部栏（Q 版设计稿）：圆形头像、薄荷绿境界牌、「战」+ 总战力；右侧 灵石 / 葫芦 两个货币胶囊和邮件按钮；
## 第二行修为条（只在修炼、功法页显示，见 set_cultivation_visible）。
## 真实数据：境界名、战力（服务器 power，含装备）、灵石（state.spiritStones）、修为 / 突破所需。
## 还没有的东西照设计显示，点了统一提示「功能暂未开放」：灵石旁的「+」、葫芦货币（没有数值，显示 --）、邮件。
## 点头像发 settings_pressed（设置面板）；点修为条右侧状态钮发 breakthrough_pressed（外壳决定开突破弹窗还是提示）。

signal settings_pressed
signal breakthrough_pressed

## 带修为条时的高度（不含刘海）；只有第一行时是 COMPACT_HEIGHT。
const HEIGHT := 264
const COMPACT_HEIGHT := 152
const CIRCLE_MASK := preload("res://assets/shaders/circle_mask.gdshader")

var _realm: Label
var _power: Label
var _stones: Label
var _gourd: Label
var _cult_value: Label
var _cult_status: Button
var _cult_bar: QBar
var _cult_row: Control
var _avatar: Button
var _mail: Button
var _content: Control
var _show_cult := true


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil := TextureRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.35))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	veil.texture = tex
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(veil)
	_content = Control.new()
	_content.name = "Margin"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	_build_identity()
	_build_currencies()
	_build_cultivation_row()


func _build_identity() -> void:
	_avatar = Button.new()
	_avatar.name = "Avatar"
	_avatar.focus_mode = Control.FOCUS_NONE
	_avatar.tooltip_text = "设置"
	_place(_avatar, 26, 6, 136, 142)
	var frame_tex := ArtLib.qui("avatar_frame")
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_avatar.add_theme_stylebox_override(state, StyleBoxEmpty.new() if frame_tex != null else QSkin.custom(Color("ffd45c"), UiTokens.Q_COCOA, 6, 999, 6, 0, 0))
	var disc := Panel.new()
	_place(disc, 6, 6, 124, 124)
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", QSkin.custom(Color.WHITE, Color(0, 0, 0, 0), 0, 999, 0, 0, 0))
	_avatar.add_child(disc)
	var face := TextureRect.new()
	face.name = "Face"
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	## 主角头像：美术 2026-10-20 补交的 avatar_player_round（已裁圆、浅青渐变底，SPEC_Q 12.3），上盖 avatar_frame。
	var round := ArtLib.qui("avatar_player_round@2x")
	face.name = "Face"
	face.texture = round if round != null else ArtLib.icon("avatar_meditate")
	_place(face, 6, 6, 124, 124)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mask := ShaderMaterial.new()
	mask.shader = CIRCLE_MASK
	face.material = mask
	_avatar.add_child(face)
	if frame_tex != null:
		var frame := QKit.cut_rect("avatar_frame")
		_place(frame, 0, 0, 136, 142)
		_avatar.add_child(frame)
	_avatar.pressed.connect(func() -> void: settings_pressed.emit())
	_content.add_child(_avatar)
	_realm = QKit.outlined("—", 36, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 6, HORIZONTAL_ALIGNMENT_CENTER)
	_realm.name = "Realm"
	var plate := PanelContainer.new()
	plate.name = "RealmPlate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ArtLib.qui("badge_realm_mint") != null:
		var box := ArtLib.q_nine("badge_realm_mint")
		box.content_margin_left = 24
		box.content_margin_right = 24
		box.content_margin_top = 0
		box.content_margin_bottom = 5
		plate.add_theme_stylebox_override("panel", box)
	else:
		plate.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_MINT, UiTokens.Q_COCOA, 4, 999, 5, 24, 2))
	plate.add_child(_realm)
	plate.position = Vector2(172, 14)
	plate.custom_minimum_size = Vector2(0, 63)
	_content.add_child(plate)
	var seal: Control
	if ArtLib.qui("badge_power") != null:
		seal = QKit.cut_rect("badge_power", Vector2(50, 50))
	else:
		seal = PanelContainer.new()
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seal.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_ORANGE, UiTokens.Q_COCOA, 4, 999, 0, 0, 0))
		seal.add_child(QKit.outlined("战", 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_CENTER))
	_place(seal, 176, 84, 50, 50)
	_content.add_child(seal)
	_power = QKit.outlined("0", 48, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 12)
	_power.name = "Power"
	_place(_power, 236, 78, 220, 60)
	_content.add_child(_power)


## 右上角：灵石（真实数值）、葫芦（暂无，显示 --）、邮件（暂无）。右对齐，宽屏也贴右边。
## 坐标照 SPEC_Q 第 8 节：灵石 462,112,250；葫芦 742,112,170；邮件 946,100,100（画布 1080 宽）。
func _build_currencies() -> void:
	var stone := _currency("res_stone", "StonePill", 76)
	_stones = stone.label
	stone.root.offset_left = -618
	stone.root.offset_right = -368
	var gourd := _currency("res_gourd", "GourdPill", 72)
	_gourd = gourd.label
	_gourd.text = "--"
	gourd.root.offset_left = -338
	gourd.root.offset_right = -168
	LockedFeature.wire(gourd.hit, "currency_gourd")
	LockedFeature.wire(stone.plus, "currency_stone_buy")
	LockedFeature.wire(gourd.plus, "currency_gourd_buy")
	_mail = Button.new()
	_mail.name = "MailButton"
	_mail.focus_mode = Control.FOCUS_NONE
	_mail.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mail.offset_left = -134
	_mail.offset_right = -34
	_mail.offset_top = 10
	_mail.offset_bottom = 116
	var mail_tex := ArtLib.qui("btn_mail")
	if mail_tex != null:
		var normal := StyleBoxTexture.new()
		normal.texture = mail_tex
		var down := StyleBoxTexture.new()
		down.texture = mail_tex
		down.modulate_color = Color(0.92, 0.9, 0.86)
		for state in ["normal", "hover", "disabled"]:
			_mail.add_theme_stylebox_override(state, normal)
		_mail.add_theme_stylebox_override("pressed", down)
	else:
		var disc := QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 5, 999, 6, 0, 0)
		for state in ["normal", "hover", "pressed", "disabled"]:
			_mail.add_theme_stylebox_override(state, disc)
		var env := QKit.outlined("✉", 54, UiTokens.Q_COCOA, Color(0, 0, 0, 0), 0, HORIZONTAL_ALIGNMENT_CENTER, false)
		env.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mail.add_child(env)
	_mail.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	LockedFeature.wire(_mail, "mail")
	_content.add_child(_mail)


func _currency(icon_name: String, node_name: String, icon_size: int) -> Dictionary:
	var root := Control.new()
	root.name = node_name
	root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	root.offset_top = 22
	root.offset_bottom = 91
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := Panel.new()
	pill.set_anchors_preset(Control.PRESET_FULL_RECT)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ArtLib.qui("currency_pill") != null:
		pill.add_theme_stylebox_override("panel", ArtLib.q_nine("currency_pill"))
	else:
		pill.offset_bottom = -5
		pill.add_theme_stylebox_override("panel", QSkin.custom(Color(1, 0.973, 0.925, 0.96), UiTokens.Q_COCOA, 4, 32, 5, 0, 0))
	root.add_child(pill)
	var hit := QKit.hit_area(root)
	hit.name = "Hit"
	var icon := UiKit.icon(icon_name, icon_size)
	icon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_place(icon, -22, 32 - icon_size / 2, icon_size, icon_size)
	root.add_child(icon)
	var label := QKit.title("0", 38, UiTokens.TEXT)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = icon_size - 18
	label.offset_right = -56
	label.offset_bottom = -5
	label.clip_text = true
	root.add_child(label)
	var plus := Button.new()
	plus.name = "Plus"
	plus.focus_mode = Control.FOCUS_NONE
	plus.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plus.offset_left = -52
	plus.offset_right = -6
	plus.offset_top = 9
	plus.offset_bottom = 55
	var plus_tex := ArtLib.qui("btn_plus")
	if plus_tex != null:
		var box := StyleBoxTexture.new()
		box.texture = plus_tex
		for key in ["normal", "hover", "pressed", "disabled"]:
			plus.add_theme_stylebox_override(key, box)
		plus.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	else:
		plus.text = "+"
		QKit.style_button(plus, "c", 36)
	root.add_child(plus)
	_content.add_child(root)
	return {"root": root, "label": label, "plus": plus, "hit": hit}


## 第二行：奶白胶囊条（strip_cream_96）+ 莲花 + 「修为」+ 修为条（bar_bg_xiuwei_52）+ 右侧状态钮（btn_*_60）。
func _build_cultivation_row() -> void:
	_cult_row = Panel.new()
	_cult_row.name = "CultivationCapsule"
	if ArtLib.qui("strip_cream_96") != null:
		_cult_row.add_theme_stylebox_override("panel", ArtLib.q_nine("strip_cream_96"))
	else:
		_cult_row.add_theme_stylebox_override("panel", QSkin.custom(Color(1, 0.973, 0.925, 0.94), UiTokens.Q_COCOA, 4, 48, 6, 0, 0))
	_cult_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cult_row.offset_left = 26
	_cult_row.offset_right = -26
	_cult_row.offset_top = 164
	_cult_row.offset_bottom = 266
	_cult_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_cult_row)
	var lotus := UiKit.icon("res_cultivation", 92, UiTokens.JADE)
	_place(lotus, 4, 2, 92, 92)
	_cult_row.add_child(lotus)
	var name := QKit.title("修为", 36, UiTokens.TEXT)
	_place(name, 98, 24, 80, 48)
	_cult_row.add_child(name)
	_cult_bar = QKit.bar(0.0, UiTokens.Q_BLUE, 52, 1, Color("ddf1fa"), "xiuwei") as QBar
	_cult_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_cult_bar.offset_left = 180
	_cult_bar.offset_right = -274
	_cult_bar.offset_top = 22
	_cult_bar.offset_bottom = 74
	_cult_row.add_child(_cult_bar)
	_cult_value = QKit.outlined("0 / 0", 34, UiTokens.Q_WHITE, Color("1f6faf"), 8, HORIZONTAL_ALIGNMENT_CENTER)
	_cult_value.name = "CultivationValue"
	_cult_value.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cult_bar.add_child(_cult_value)
	_cult_status = QKit.button("", "c", 60, 30)
	_cult_status.name = "CultivationStatus"
	_cult_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_cult_status.offset_left = -254
	_cult_status.offset_right = -14
	_cult_status.offset_top = 18
	_cult_status.offset_bottom = 84
	_cult_status.clip_text = true
	_cult_status.pressed.connect(func() -> void: breakthrough_pressed.emit())
	_cult_row.add_child(_cult_status)


static func _place(node: Control, x: float, y: float, w: float, h: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(w, h)
	node.custom_minimum_size = Vector2(w, h)


## 是否显示第二行修为条（修炼 / 功法页显示；历练 / 背包 / 洞府不显示，设计稿如此）。
func set_cultivation_visible(on: bool) -> void:
	_show_cult = on
	_cult_row.visible = on


func cultivation_visible() -> bool:
	return _show_cult


## 实际占用的高度（不含刘海）。
func content_height() -> float:
	return float(HEIGHT if _show_cult else COMPACT_HEIGHT)


func apply_safe_area(inset: Vector4) -> void:
	offset_top = 0.0
	offset_left = inset.x
	offset_right = -inset.z
	offset_bottom = content_height() + inset.y
	_content.offset_top = inset.y


func bind(state: Dictionary) -> void:
	_realm.text = str(state.get("realmName", "—"))
	_power.text = OfflineView.grouped(float(state.get("power", 0)))
	_stones.text = OfflineView.grouped(float(state.get("spiritStones", 0))) if state.get("spiritStones", null) != null else "--"
	var view := BreakthroughView.build(state)
	var cultivation := float(state.get("cultivation", 0))
	var cost := float(view.cost)
	var has_next := bool(view.has_next)
	_cult_value.text = "%s / %s" % [OfflineView.grouped(cultivation), OfflineView.grouped(cost)] if has_next else OfflineView.grouped(cultivation)
	var ratio := clampf(cultivation / maxf(cost, 1.0), 0.0, 1.0) if has_next else 1.0
	_cult_bar.set_ratio(ratio)
	var kind := "c"
	if not has_next:
		_cult_status.text = "已至最高境界"
	elif bool(view.can_start):
		_cult_status.text = "已满·可突破"
		kind = "o"
	elif bool(view.cultivation_ok):
		_cult_status.text = "已满·需击败首领"
	else:
		_cult_status.text = "还差 %s" % OfflineView.grouped(cost - cultivation)
	QKit.style_button(_cult_status, kind, 30)


func power_text() -> String:
	return "战力 %s" % _power.text


func realm_text() -> String:
	return _realm.text


func cultivation_text() -> String:
	return _cult_value.text


func status_text() -> String:
	return _cult_status.text


func stones_text() -> String:
	return _stones.text


func gourd_text() -> String:
	return _gourd.text


func mail_button() -> Button:
	return _mail
