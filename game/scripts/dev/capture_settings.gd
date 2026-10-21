extends SceneTree
## 开发用：设置面板截图（演示数据，不连服务器）：设置面板 → 退出登录确认 → 回到登录页。
## 用法：--script res://scripts/dev/capture_settings.gd -- <输出目录>   （环境变量 XIUXIAN_UI_MOCK=1）
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/settings_shot"
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(40)
	(scene.get("_offline_popup") as Control).hide()  # 演示数据开场有离线收益弹窗，先关掉
	await _settle(10)
	_shot(out, "0_home")
	(scene.get("_top_bar") as TopBar).settings_pressed.emit()
	await _settle(20)
	_shot(out, "1_settings")
	var popup := scene.get("_popup") as GamePopup
	(popup.find_child("Locked_兑换码", true, false) as Button).pressed.emit()
	await _settle(12)
	_shot(out, "2_locked_toast")
	(popup.find_child("LogoutButton", true, false) as Button).pressed.emit()
	await _settle(20)
	_shot(out, "3_logout_confirm")
	(popup.actions.get_child(1) as Button).pressed.emit()
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
