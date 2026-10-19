class_name UpdatePrompt
extends RefCounted
## 「发现新版本」弹窗（和背包已满提示同一种屏幕正中的小弹窗）。按钮：更新 / 稍后（强制更新时没有稍后，点遮罩也不关）。
## 更新：Android 上用 XiuxianUpdater 插件在应用里下载（显示进度）并拉起系统安装器；
##       插件不可用（桌面、老 ROM 出错）时改用系统浏览器打开安装包地址。

var popup: GamePopup
var service: UpdateService
var _info: Dictionary = {}
var _bar: ProgressBar
var _status: Label
var _update_button: Button
var _downloaded := false
var _use_browser := false


func _init(target_popup: GamePopup, update_service: UpdateService) -> void:
	popup = target_popup
	service = update_service
	service.download_progress_changed.connect(_on_progress)
	service.download_ready.connect(_on_ready)
	service.status_changed.connect(_on_status)
	service.failed.connect(_on_failed)


static func title_for(info: Dictionary) -> String:
	return "发现新版本 %s" % str(info.get("version", ""))


static func size_text(bytes: int) -> String:
	return "" if bytes <= 0 else "安装包约 %.0f MB" % (float(bytes) / 1048576.0)


func show_update(info: Dictionary, current_version: String) -> void:
	_info = info
	var force := bool(info.get("force_update", false))
	popup.clear_content()
	popup.set_dim_closes(not force)
	var from_to := UiKit.label("当前 %s → 新版 %s" % [current_version, str(info.get("version", ""))], UiTokens.FS_BODY, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	from_to.name = "UpdateVersions"
	popup.body.add_child(from_to)
	var notes := str(info.get("release_notes", ""))
	if not notes.is_empty():
		var notes_label := UiKit.wrap_label(notes, UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
		notes_label.name = "UpdateNotes"
		notes_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup.body.add_child(notes_label)
	var size_line := size_text(int(info.get("apk_size", 0)))
	if force:
		size_line = ("这个版本必须更新后才能继续。" + ("" if size_line.is_empty() else "  " + size_line))
	if not size_line.is_empty():
		popup.body.add_child(UiKit.label(size_line, UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_bar = ProgressBar.new()
	_bar.name = "UpdateProgress"
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.custom_minimum_size = Vector2(0, 40)
	_bar.visible = false
	popup.body.add_child(_bar)
	_status = UiKit.wrap_label("", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	_status.name = "UpdateStatus"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	popup.body.add_child(_status)
	var buttons: Array = [{"text": "更新", "variation": MainTheme.VAR_PRIMARY, "callback": _on_update_pressed, "close": false}]
	if not force:
		buttons.push_front({"text": "稍后", "variation": MainTheme.VAR_SECONDARY})
	popup.set_actions(buttons)
	for child in popup.actions.get_children():
		if child is Button and (child as Button).text == "更新":
			_update_button = child
	popup.open_popup(title_for(info), true)


func _on_update_pressed() -> void:
	if _downloaded and not _use_browser:
		service.install_downloaded_update()
		return
	if service.can_install_in_app() and not _use_browser:
		_update_button.disabled = true
		_bar.visible = true
		_status.visible = true
		service.download_update()
	elif service.open_in_browser():
		_say("已在浏览器打开下载地址，下载完成后点通知安装。")
	else:
		_say("无法打开下载地址：%s" % str(_info.get("apk_url", "")))


## 弹窗现在显示的是不是更新内容（同一个弹层也给别的提示用，内容被清掉后旧控件就失效了）
func _active() -> bool:
	return popup.visible and is_instance_valid(_status) and _status.is_inside_tree()


func _on_progress(progress: float) -> void:
	if _active():
		_bar.value = progress * 100.0


func _on_ready(_path: String) -> void:
	_downloaded = true
	service.install_downloaded_update()
	if is_instance_valid(_update_button):
		_update_button.disabled = false
		_update_button.text = "安装"


func _on_status(message: String) -> void:
	if _active() and not message.is_empty():
		_say(message)


func _on_failed(message: String) -> void:
	if not _active():
		return
	# 应用内下载 / 安装失败一次后，再点就改用浏览器下载
	_use_browser = true
	_say(message + "  再点一次会改用浏览器下载。")
	if is_instance_valid(_update_button):
		_update_button.disabled = false
		_update_button.text = "用浏览器下载"


func _say(message: String) -> void:
	if not is_instance_valid(_status):
		return
	_status.text = message
	_status.visible = true
	popup.fit()
