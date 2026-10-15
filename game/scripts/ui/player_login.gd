class_name PlayerLogin
extends Control

signal logged_in

var _username: LineEdit
var _password: LineEdit
var _error: Label
var _card: PanelContainer


func _ready() -> void:
	MainTheme.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := Backdrop.new()
	add_child(backdrop)
	backdrop.show_background("login")
	var logo := TextureRect.new()
	logo.name = "Logo"
	logo.texture = ArtLib.ui("logo_title")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	logo.offset_top = 150.0
	logo.offset_bottom = 560.0
	add_child(logo)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", ArtLib.nine("panel_popup"))
	add_child(_card)
	resized.connect(_fit_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTokens.SP_3)
	_card.add_child(box)
	var subtitle := Label.new()
	subtitle.text = "登录后，修为记在你的账号上"
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.theme_type_variation = MainTheme.VAR_SUBTLE
	box.add_child(subtitle)
	_username = _field("用户名")
	_password = _field("密码")
	_password.secret = true
	box.add_child(_username)
	box.add_child(_password)
	var login := _button("登录", true)
	login.pressed.connect(_on_login)
	box.add_child(login)
	var register := _button("注册", false)
	register.pressed.connect(_on_register)
	box.add_child(register)
	_error = Label.new()
	_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.theme_type_variation = MainTheme.VAR_DANGER_LABEL
	box.add_child(_error)
	_fit_card()


func _fit_card() -> void:
	MainTheme.place_centered(_card, size, Vector2(860, 760))


func _field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	return edit


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	button.theme_type_variation = MainTheme.VAR_PRIMARY if primary else MainTheme.VAR_SECONDARY
	return button


func _on_login() -> void:
	_submit(false)


func _on_register() -> void:
	_submit(true)


func _submit(is_register: bool) -> void:
	_error.text = ""
	var name := _username.text.strip_edges()
	var password := _password.text
	if name.is_empty() or password.is_empty():
		_error.text = "请填写用户名和密码"
		return
	var result: Dictionary = {}
	if is_register:
		result = await PlayerApi.register(name, password)
	else:
		result = await PlayerApi.login(name, password)
	if result.is_empty():
		_error.text = "网络失败，请稍后再试"
		return
	if int(result.get("code", 0)) >= 400 or not result.has("token"):
		_error.text = "账号或密码不正确" if not is_register else "注册失败，换一个用户名试试"
		return
	PlayerApi.save_token(str(result.get("token", "")))
	hide()
	logged_in.emit()
