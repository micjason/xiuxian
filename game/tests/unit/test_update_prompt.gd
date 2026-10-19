extends GutTest
## 「发现新版本」弹窗：标题、版本、更新 / 稍后；强制更新没有稍后，点遮罩不关。

var _popup: GamePopup
var _service: UpdateService


func before_each() -> void:
	_popup = GamePopup.new()
	add_child_autofree(_popup)
	_service = UpdateService.new()
	add_child_autofree(_service)


func _info(force: bool) -> Dictionary:
	return {"version": "0.11.0", "version_code": 31, "apk_url": "http://101.132.74.32:8090/download/a.apk", "apk_size": 95 * 1048576,
		"apk_sha256": "a".repeat(64), "release_notes": "新增在线更新", "force_update": force}


func _button_texts() -> Array:
	var out: Array = []
	for child in _popup.actions.get_children():
		out.append((child as Button).text)
	return out


func test_popup_shows_new_version_with_update_and_later() -> void:
	var prompt := UpdatePrompt.new(_popup, _service)
	prompt.show_update(_info(false), "0.10.1-proto")
	await wait_frames(2)
	assert_true(_popup.visible)
	assert_eq(_popup.title_label.text, "发现新版本 0.11.0")
	assert_eq(_button_texts(), ["稍后", "更新"])
	assert_string_contains((_popup.body.find_child("UpdateVersions", true, false) as Label).text, "0.10.1-proto → 新版 0.11.0")
	assert_eq((_popup.body.find_child("UpdateNotes", true, false) as Label).text, "新增在线更新")
	assert_false((_popup.body.find_child("UpdateProgress", true, false) as Control).visible)


func test_force_update_has_no_later_button() -> void:
	var prompt := UpdatePrompt.new(_popup, _service)
	prompt.show_update(_info(true), "0.10.1-proto")
	await wait_frames(2)
	assert_eq(_button_texts(), ["更新"])
	_popup._on_dim_input(_click())
	assert_true(_popup.visible, "强制更新时点遮罩不关闭")


func test_failure_after_popup_reused_does_not_crash() -> void:
	var prompt := UpdatePrompt.new(_popup, _service)
	prompt.show_update(_info(false), "0.10.1")
	await wait_frames(2)
	_popup.clear_content()
	await wait_frames(1)
	_service.failed.emit("网络错误")
	_service.download_progress_changed.emit(0.5)
	assert_true(true)


func _click() -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.pressed = true
	e.button_index = MOUSE_BUTTON_LEFT
	return e
