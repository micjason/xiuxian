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
	var backdrop := ColorRect.new()
	backdrop.color = MainTheme.INK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MainTheme.fill_parent(backdrop)
	add_child(backdrop)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	add_child(_card)
	resized.connect(_fit_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	_card.add_child(box)
	var title := Label.new()
	title.text = "修仙"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", MainTheme.title_font())
	title.add_theme_font_size_override("font_size", MainTheme.SIZE_DISPLAY)
	title.add_theme_color_override("font_color", MainTheme.IVORY)
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "登录后，修为记在你的账号上"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
	subtitle.add_theme_color_override("font_color", MainTheme.MUTED)
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
	_error.add_theme_font_size_override("font_size", MainTheme.SIZE_CAPTION)
	_error.add_theme_color_override("font_color", MainTheme.GOLD)
	box.add_child(_error)
	_fit_card()


func _fit_card() -> void:
	MainTheme.place_centered(_card, size, Vector2(760, 860))


func _field(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, MainTheme.H_CTA)
	edit.add_theme_font_size_override("font_size", MainTheme.SIZE_UI)
	edit.add_theme_color_override("font_color", MainTheme.IVORY)
	edit.add_theme_color_override("font_placeholder_color", MainTheme.IVORY)
	edit.add_theme_stylebox_override("normal", MainTheme.input_normal())
	edit.add_theme_stylebox_override("focus", MainTheme.input_focus())
	return edit


func _button(text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, MainTheme.H_CTA)
	button.add_theme_font_size_override("font_size", MainTheme.SIZE_HERO)
	if primary:
		button.add_theme_color_override("font_color", MainTheme.INK)
		button.add_theme_color_override("font_hover_color", MainTheme.INK)
		button.add_theme_color_override("font_pressed_color", MainTheme.INK)
		button.add_theme_stylebox_override("normal", MainTheme.progress_fill(true))
		button.add_theme_stylebox_override("hover", MainTheme.progress_fill(true))
		button.add_theme_stylebox_override("pressed", MainTheme.progress_fill(true))
	else:
		button.add_theme_color_override("font_color", MainTheme.IVORY)
		button.add_theme_color_override("font_hover_color", MainTheme.IVORY)
		button.add_theme_color_override("font_pressed_color", MainTheme.IVORY)
		button.add_theme_stylebox_override("normal", MainTheme.secondary_button())
		button.add_theme_stylebox_override("hover", MainTheme.secondary_button())
		button.add_theme_stylebox_override("pressed", MainTheme.secondary_button())
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
