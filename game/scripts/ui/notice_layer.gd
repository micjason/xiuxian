class_name NoticeLayer
extends Control

signal dismissed(notice_id: String, hide_for_session: bool)
signal download_requested

var queue: NoticeQueue
var _card: PanelContainer
var _title: Label
var _body: RichTextLabel
var _primary: Button
var _secondary: Button


func _ready() -> void:
	MainTheme.fill_parent(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = UiTokens.SCRIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MainTheme.fill_parent(dim)
	add_child(dim)
	_card = PanelContainer.new()
	add_child(_card)
	resized.connect(show_current)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	_card.add_child(box)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", MainTheme.title_font())
	_title.add_theme_font_size_override("font_size", UiTokens.FS_HERO)
	_title.add_theme_color_override("font_color", UiTokens.GOLD)
	box.add_child(_title)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.fit_content = true
	_body.scroll_active = true
	_body.custom_minimum_size = Vector2(0, 180)
	_body.add_theme_font_size_override("normal_font_size", UiTokens.FS_BODY_L)
	box.add_child(_body)
	_primary = _button(true)
	_secondary = _button(false)
	box.add_child(_primary)
	box.add_child(_secondary)
	_primary.pressed.connect(_on_primary)
	_secondary.pressed.connect(_on_secondary)


func show_current() -> void:
	if queue == null or queue.current.is_empty():
		visible = false
		return
	var notice := queue.current
	var payload: Dictionary = notice.get("payload", {})
	var template := str(notice.get("template", ""))
	_apply_template_size(template)
	_secondary.visible = template == "confirm"
	if template == "confirm":
		_title.text = "发现新版本"
		_body.text = "新版本：%s\n\n%s" % [str(payload.get("version", "")), str(payload.get("notes", ""))]
		_primary.text = "下载更新"
		_secondary.text = "暂不更新"
	elif template == "reward":
		_title.text = "闭关归来"
		_body.text = _reward_text(payload)
		_primary.text = "收下"
	else:
		_title.text = str(payload.get("title", "公告"))
		_body.text = str(payload.get("body", ""))
		_primary.text = "知道了"
	visible = true


func _apply_template_size(template: String) -> void:
	var max_size := Vector2(760, 640)
	if template == "confirm":
		max_size = Vector2(840, 840)
	elif template == "reward":
		max_size = Vector2(960, 460)
	var card_size := MainTheme.place_centered(_card, size, max_size)
	_body.custom_minimum_size = Vector2(maxf(120.0, card_size.x - 80.0), minf(280.0, maxf(80.0, card_size.y - 220.0)))


func _reward_text(payload: Dictionary) -> String:
	var lines: PackedStringArray = [
		"获得修为：%s" % CultivationFormat.amount(float(payload.get("cultivationGained", 0))),
		"结算时长：%s" % CultivationFormat.duration_hours(int(payload.get("countedSeconds", 0))),
	]
	if bool(payload.get("hitCap", false)):
		lines.append("已顶到离线上限 %s。" % CultivationFormat.duration_hours(int(payload.get("offlineCapSeconds", 0))))
	else:
		lines.append("未顶到离线上限。")
	return "\n".join(lines)


func _button(primary: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, UiTokens.H_CTA)
	button.theme_type_variation = MainTheme.VAR_PRIMARY if primary else MainTheme.VAR_SECONDARY
	return button


func _on_primary() -> void:
	var template := str(queue.current.get("template", ""))
	var notice_id := str(queue.current.get("id", ""))
	if template == "confirm":
		dismissed.emit(notice_id, true)
		download_requested.emit()
		return
	dismissed.emit(notice_id, false)


func _on_secondary() -> void:
	dismissed.emit(str(queue.current.get("id", "")), false)
