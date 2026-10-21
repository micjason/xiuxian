extends SceneTree
## 开发用：设置弹窗截图（演示数据，不连服务器）：设置 → 点未开放入口（toast）→ 退出登录确认 → 回到登录页。
## 用法：XIUXIAN_UI_MOCK=1 godot --script res://scripts/dev/capture_settings.gd -- <输出目录>
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/settings_shot"
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(40)
	(scene.get("_offline_popup") as Control).hide()  # 演示数据开场有离线收益弹窗，先关掉
	await _settle(10)
	(scene.get("_top_bar") as TopBar).settings_pressed.emit()
	await _settle(20)
	_shot(out, "1_settings")
	var settings := scene.get("_settings") as Control
	(settings.find_child("CreditsRow", true, false) as Button).pressed.emit()
	await _settle(12)
	_shot(out, "1b_credits")
	(scene.get("_popup") as GamePopup).close_popup()
	await _settle(6)
	(settings.find_child("Locked_兑换码", true, false) as Button).pressed.emit()
	await _settle(12)
	_shot(out, "2_locked_toast")
	await create_timer(2.2).timeout
	(settings.find_child("LogoutButton", true, false) as Button).pressed.emit()
	await _settle(20)
	_shot(out, "3_logout_confirm")
	(settings.find_child("ConfirmLogout", true, false) as Button).pressed.emit()
	await _settle(40)
	_shot(out, "4_login")
	print("shots done")
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
	await create_timer(0.6).timeout


func _shot(out: String, name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
