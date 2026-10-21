class_name SettingsView
extends Control
## 设置弹窗（设计稿 q_design/q_settings_popup + q_settings_states，SPEC_Q §17.4）：点左上角头像打开，居中盖在当前页上。
## 账号信息（头像、名字、境界、账号打码、服务器）/ 声音（音乐、音效开关，本机保存，LocalSettings）/
## 更多（5 个未开放入口：灰色可点，提示「功能暂未开放」，弹窗不关）/ 版本号 + 检查更新 / 退出登录（二次确认）。
## 坐标按 1080×2340 设计稿、相对弹窗框左上角（稿上 60,513）；弹窗整体在可用高度里垂直居中。
## 只管界面，动作发信号给外壳（play_screen）。

signal logout_confirmed
signal check_update_requested
signal locked_pressed(feature: String)
signal credits_requested
signal closed

const FRAME_SIZE := Vector2(960, 1314)
const FRAME_X := 60.0
const LOCKED_TEXT := LockedFeature.TEXT
## 未开放入口：[名字, 图标, 列, 行, 宽]（稿上两行 3 列，最后一个跨 2 列）。
const TILES := [
	["修改密码", "icon_set_key", 0, 0, 268],
	["绑定手机", "icon_set_phone", 1, 0, 268],
	["兑换码", "icon_set_gift", 2, 0, 268],
	["客服反馈", "icon_set_service", 0, 1, 268],
	["用户协议与隐私政策", "icon_set_doc", 1, 1, 560],
]
const GREY := Color("9a8b7e")
const LABEL_GREY := Color("a08f82")
const OK_GREEN := Color("3c9a4e")
const NEW_ORANGE := Color("e07b24")

var _info: Dictionary = {}
var _dim: ColorRect
var _frame: Control
var _ribbon: Control
var _close: Button
var _hint: Control
var _name: Label
var _realm_chip: Control
var _realm_text: Label
var _account_value: Label
var _server_value: Label
var _music: Button
var _sfx: Button
var _version: Label
var _update_state: Label
var _check: Button
var _confirm: Control
var _confirm_text: Label
var _inset := Vector4.ZERO


func _init() -> void:
	name = "SettingsPopup"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.name = "Dimmer"
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if _tapped(event):
			close())
	add_child(_dim)
	_frame = Panel.new()
	_frame.name = "PopupFrame"
	_frame.size = FRAME_SIZE
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_frame.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	add_child(_frame)
	_build_account()
	_build_sound()
	_build_more()
	_build_version()
	_build_logout()
	_ribbon = QKit.ribbon("设 置", 52, 300, true)
	_ribbon.name = "Ribbon"
	add_child(_ribbon)
	_close = _close_button()
	add_child(_close)
	_hint = QKit.tag("点击空白处关闭", "dark", 32, 30)
	_hint.name = "CloseHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_build_confirm()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func apply_safe_area(inset: Vector4) -> void:
	_inset = inset
	_layout()


## 弹窗在「状态栏以下、手势条以上」的区域里垂直居中（稿上框顶 513、高 1314；绶带压在框顶上 62）。
func _layout() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1080, 2340)
	var avail_top := _inset.y
	var avail := view.y - _inset.y - _inset.w
	var top := avail_top + maxf(70.0, (avail - FRAME_SIZE.y) / 2.0)
	_frame.position = Vector2(FRAME_X, top)
	_ribbon.position = Vector2(540 - _ribbon.custom_minimum_size.x / 2.0, top - 62)
	_ribbon.size = _ribbon.custom_minimum_size
	_close.position = Vector2(FRAME_X + FRAME_SIZE.x - 62, top - 36)
	_close.size = Vector2(84, 89)
	_hint.size = Vector2(400, 60)
	_hint.position = Vector2(340, top + FRAME_SIZE.y + 22)
	var box := _confirm.get_node("ConfirmFrame") as Control
	box.position = Vector2(130, top + 377)
	var ribbon := _confirm.get_node("ConfirmRibbon") as Control
	ribbon.size = ribbon.custom_minimum_size
	ribbon.position = Vector2(540 - ribbon.custom_minimum_size.x / 2.0, box.position.y - 52)


# ───────── 打开 / 关闭 ─────────

## info: {username, realm, server, version, versionCode}
func open(info: Dictionary) -> void:
	_info = info
	var username := _text(info.get("username", ""), "道友")
	_name.text = username
	_realm_text.text = _text(info.get("realm", ""), "—")
	_account_value.text = mask_account(username)
	_server_value.text = _text(info.get("server", ""), "—")
	(_music as QToggleSwitch).set_on(LocalSettings.music_on())
	(_sfx as QToggleSwitch).set_on(LocalSettings.sfx_on())
	_version.text = version_text(info)
	set_update_state("", Color.WHITE)
	set_checking(false)
	_confirm.visible = false
	visible = true
	move_to_front()
	_layout()


func close() -> void:
	if not visible:
		return
	visible = false
	_confirm.visible = false
	closed.emit()


func is_confirming() -> bool:
	return _confirm.visible


## 检查更新状态（稿：已是最新 绿 / 发现新版本 橙），空串隐藏。
func set_update_state(text: String, color: Color) -> void:
	_update_state.text = text
	_update_state.add_theme_color_override("font_color", color)


func set_checking(checking: bool) -> void:
	_check.disabled = checking
	_check.text = "检查中…" if checking else "检查更新"


func show_latest() -> void:
	set_checking(false)
	set_update_state("已是最新版本", OK_GREEN)


func show_new_version(version: String) -> void:
	set_checking(false)
	set_update_state("发现新版本 v%s" % version, NEW_ORANGE)


## 退出登录二次确认：在设置弹窗上再压暗，取消回设置，退出才真的退出。
func confirm_logout() -> void:
	_confirm_text.text = "退出后回到登录页，角色「%s」数据保留在服务器" % _text(_info.get("username", ""), "道友")
	_confirm.visible = true


# ───────── 文字 ─────────

static func version_text(info: Dictionary) -> String:
	var version := _text(info.get("version", ""), "—")
	var code := int(info.get("versionCode", 0))
	return "v%s（%d）" % [version, code] if code > 0 else "v%s" % version


## 账号中间打码：手机号 3+4 位显示（138****6612）；其它账号 ≥ 6 位时留头 2 尾 2，短的原样。
static func mask_account(account: String) -> String:
	var text := account.strip_edges()
	if text.length() == 11 and text.is_valid_int():
		return text.substr(0, 3) + "****" + text.substr(7)
	if text.length() >= 6:
		return text.substr(0, 2) + "*".repeat(mini(4, text.length() - 4)) + text.substr(text.length() - 2)
	return text


static func _text(value: Variant, fallback: String) -> String:
	var text := "" if value == null else str(value).strip_edges()
	return fallback if text.is_empty() else text


# ───────── 搭界面（坐标相对弹窗框） ─────────

func _well(rect: Rect2, node_name: String) -> Panel:
	var well := Panel.new()
	well.name = node_name
	well.position = rect.position
	well.size = rect.size
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


func _build_account() -> void:
	var well := _well(Rect2(26, 84, 908, 252), "SettingsAccount")
	# 头像 172（稿 112,637）+ 框 184（106,631）
	var face := TextureRect.new()
	face.texture = ArtLib.qui("avatar_player_round@2x") if ArtLib.qui("avatar_player_round@2x") != null else ArtLib.icon("avatar_meditate")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mask := ShaderMaterial.new()
	mask.shader = TopBar.CIRCLE_MASK
	face.material = mask
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(well, face, Vector2(26, 40), Vector2(172, 172))
	if ArtLib.qui("avatar_frame") != null:
		_at(well, QKit.cut_rect("avatar_frame", Vector2(184, 192)), Vector2(20, 34), Vector2(184, 192))
	var head := UiKit.hbox(16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name = QKit.title("", 50, UiTokens.TEXT)
	_name.name = "SettingsName"
	head.add_child(_name)
	_realm_chip = QKit.tag("—", "mint", 28, 18)
	_realm_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_realm_text = _realm_chip.get_child(0) as Label
	head.add_child(_realm_chip)
	_at(well, head, Vector2(230, 20), Vector2(640, 70))
	_account_value = _info_row(well, "账号", 100)
	_account_value.name = "SettingsAccountValue"
	_server_value = _info_row(well, "服务器", 168)


func _info_row(well: Control, key: String, y: float) -> Label:
	var row := Panel.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 3, 30, 0, 0, 0))
	_at(well, row, Vector2(226, y), Vector2(654, 60))
	_at(row, _v_label(key, 28, LABEL_GREY, false), Vector2(26, 0), Vector2(120, 60))
	var value := _v_label("", 32, UiTokens.TEXT, false)
	value.clip_text = true
	value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_at(row, value, Vector2(148, 0), Vector2(490, 60))
	return value


func _v_label(text: String, size: int, color: Color, title_font: bool) -> Label:
	var label := QKit.title(text, size, color) if title_font else UiKit.label(text, size, color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_sound() -> void:
	var well := _well(Rect2(26, 358, 908, 196), "SettingsSound")
	_at(well, UiKit.label("声音", 32, LABEL_GREY), Vector2(28, 14))
	_music = _sound_strip(well, "MusicToggle", "音乐", "icon_set_music", 28, LocalSettings.set_music_on)
	_sfx = _sound_strip(well, "SfxToggle", "音效", "icon_set_sfx", 466, LocalSettings.set_sfx_on)


func _sound_strip(well: Control, node_name: String, text: String, icon: String, x: float, setter: Callable) -> Button:
	var strip := Panel.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_theme_stylebox_override("panel", ArtLib.q_nine("strip_cream_96") if ArtLib.qui("strip_cream_96") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 3, 50, 4, 0, 0))
	_at(well, strip, Vector2(x, 70), Vector2(414, 102))
	_at(strip, QKit.cut_rect(icon, Vector2(64, 64)), Vector2(26, 17), Vector2(64, 64))
	_at(strip, _v_label(text, 40, UiTokens.TEXT, true), Vector2(102, 0), Vector2(110, 96))
	var toggle := QToggleSwitch.new()
	toggle.name = node_name
	toggle.toggled_on.connect(func(on: bool) -> void: setter.call(on))
	_at(strip, toggle, Vector2(414 - 176, 11), Vector2(156, 80))
	return toggle


func _build_more() -> void:
	var well := _well(Rect2(26, 576, 908, 392), "SettingsMore")
	_at(well, UiKit.label("更多", 32, LABEL_GREY), Vector2(28, 14))
	var soon := UiKit.label("敬请期待", 26, Color("b8a799"), HORIZONTAL_ALIGNMENT_RIGHT)
	_at(well, soon, Vector2(580, 18), Vector2(300, 40))
	for spec in TILES:
		var tile := _tile(str(spec[0]), str(spec[1]), int(spec[4]))
		_at(well, tile, Vector2(28 + int(spec[2]) * 292, 78 + int(spec[3]) * 158), Vector2(int(spec[4]), 136))


## 未开放入口格：tile_setting_off + 灰图标 + 灰字 + 右上「未开放」角标；点了压暗 0.1s、发 locked_pressed。
func _tile(text: String, icon: String, width: int) -> Button:
	var tile := Button.new()
	tile.name = "Locked_%s" % text
	tile.focus_mode = Control.FOCUS_NONE
	var cut := "tile_setting_off"
	for key in ["normal", "hover", "disabled", "focus"]:
		tile.add_theme_stylebox_override(key, ArtLib.q_nine(cut) if ArtLib.qui(cut) != null else QSkin.custom(Color("f1ebe4"), Color("c9bcb0"), 3, 30, 4, 0, 0))
	tile.add_theme_stylebox_override("pressed", ArtLib.q_nine(cut, Color(0.88, 0.85, 0.83)) if ArtLib.qui(cut) != null else QSkin.custom(Color("e4dcd3"), Color("c9bcb0"), 3, 30, 2, 0, 0))
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var glyph := QKit.cut_rect(icon, Vector2(64, 64))
	glyph.modulate = Color(0.72, 0.68, 0.66, 0.55)  # 稿：alpha .55 + 去饱和
	_at(tile, glyph, Vector2(22, 32), Vector2(64, 64))
	var label := _v_label(text, 34, GREY, true)
	_at(tile, label, Vector2(94, 0), Vector2(width - 104, 128))
	if ArtLib.qui("tag_unopened") != null:
		var tag := QKit.cut_rect("tag_unopened", Vector2(112, 44))
		_at(tile, tag, Vector2(width - 100, -14), Vector2(112, 44))
	tile.pressed.connect(func() -> void: locked_pressed.emit(text))
	return tile


func _build_version() -> void:
	var well := _well(Rect2(26, 990, 908, 124), "SettingsVersion")
	_at(well, UiKit.label("版本号", 28, LABEL_GREY), Vector2(28, 12))
	_version = QKit.title("", 38, UiTokens.TEXT)
	_version.name = "SettingsVersionText"
	_at(well, _version, Vector2(28, 52))
	# 稿上没有「素材致谢」入口：点版本号区域打开致谢页（CC BY 素材署名要能看到；用户协议页开放后挪过去，SPEC_Q 17.4）
	var credits := Button.new()
	credits.name = "CreditsArea"
	credits.flat = true
	credits.focus_mode = Control.FOCUS_NONE
	for key in ["normal", "hover", "pressed", "focus", "disabled"]:
		credits.add_theme_stylebox_override(key, StyleBoxEmpty.new())
	credits.pressed.connect(func() -> void: credits_requested.emit())
	_at(well, credits, Vector2(0, 0), Vector2(290, 124))
	_update_state = UiKit.label("", 26, OK_GREEN)
	_update_state.name = "UpdateState"
	_at(well, _update_state, Vector2(300, 64), Vector2(280, 40))
	_check = QKit.button("检查更新", "m", 100, 38)
	_check.name = "CheckUpdateButton"
	_check.pressed.connect(func() -> void: check_update_requested.emit())
	_at(well, _check, Vector2(580, 12), Vector2(300, _check.custom_minimum_size.y))


func _build_logout() -> void:
	var button := QKit.button("", "r", 124, 50)
	button.name = "LogoutButton"
	_at(_frame, button, Vector2(40, 1144), Vector2(880, button.custom_minimum_size.y))
	var row := UiKit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -8
	row.add_child(QKit.cut_rect("icon_set_logout", Vector2(60, 60)))
	(row.get_child(0) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(QKit.outlined("退出登录", 50, UiTokens.Q_WHITE, Color("a8323a"), 9, HORIZONTAL_ALIGNMENT_CENTER))
	(row.get_child(1) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_child(row)
	button.pressed.connect(confirm_logout)


## 二次确认（稿 q_settings_state_logout）：再压暗 rgba(30,20,15,.55)，820×560 小弹窗，绶带「退出登录」，
## 头像 124 + 「确定要退出当前账号吗？」+ 说明；取消（薄荷）/ 退出（红）。
func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "LogoutConfirm"
	_confirm.visible = false
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(30.0 / 255.0, 20.0 / 255.0, 15.0 / 255.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)
	var box := Panel.new()
	box.name = "ConfirmFrame"
	box.size = Vector2(820, 560)
	box.add_theme_stylebox_override("panel", QKit.cut_box("popup_frame", 24, 30) if ArtLib.qui("popup_frame") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 6, 48, 12, 24, 30))
	_confirm.add_child(box)
	var face := TextureRect.new()
	face.texture = ArtLib.qui("avatar_player_round@2x") if ArtLib.qui("avatar_player_round@2x") != null else ArtLib.icon("avatar_meditate")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var mask := ShaderMaterial.new()
	mask.shader = TopBar.CIRCLE_MASK
	face.material = mask
	_at(box, face, Vector2(348, 74), Vector2(124, 124))
	if ArtLib.qui("avatar_frame") != null:
		_at(box, QKit.cut_rect("avatar_frame", Vector2(136, 142)), Vector2(342, 68), Vector2(136, 142))
	var ask := QKit.title("确定要退出当前账号吗？", 40, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	ask.name = "LogoutConfirmText"
	_at(box, ask, Vector2(0, 222), Vector2(820, 60))
	_confirm_text = UiKit.label("", 28, LABEL_GREY, HORIZONTAL_ALIGNMENT_CENTER)
	_confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_at(box, _confirm_text, Vector2(40, 290), Vector2(740, 80))
	var cancel := QKit.button("取 消", "m", 100, 44)
	cancel.name = "ConfirmCancel"
	cancel.pressed.connect(func() -> void: _confirm.visible = false)
	_at(box, cancel, Vector2(50, 400), Vector2(340, cancel.custom_minimum_size.y))
	var ok := QKit.button("退 出", "r", 100, 44)
	ok.name = "ConfirmLogout"
	ok.pressed.connect(func() -> void:
		_confirm.visible = false
		visible = false
		logout_confirmed.emit())
	_at(box, ok, Vector2(430, 400), Vector2(340, ok.custom_minimum_size.y))
	var ribbon := QKit.ribbon("退出登录", 44, 240, true)
	ribbon.name = "ConfirmRibbon"
	_confirm.add_child(ribbon)
	add_child(_confirm)


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


static func _tapped(event: InputEvent) -> bool:
	return (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
