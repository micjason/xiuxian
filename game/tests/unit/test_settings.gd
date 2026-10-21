extends GutTest
## 设置弹窗（点头像，设计稿 q_settings_popup / SPEC_Q 17.4）：退出登录清掉令牌回登录页；音乐 / 音效开关本机保存并作用到音频总线；
## 未开放入口提示且弹窗不关；旧的战报开关 / 背包满处理不再出现。

const SAVED := ["user://player_token.txt", "user://player_account.json"]
var _backup: Dictionary = {}


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING
	_backup.clear()
	for path in SAVED:
		if FileAccess.file_exists(path):
			_backup[path] = FileAccess.get_file_as_string(path)
	LocalSettings.path = "user://test_settings_%d.cfg" % Time.get_ticks_usec()


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LocalSettings.path))
	LocalSettings.path = LocalSettings.DEFAULT_PATH
	LocalSettings.apply_audio()
	for path in SAVED:
		if _backup.has(path):
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(str(_backup[path]))
			file.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _boot() -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await wait_frames(2)
	OS.unset_environment("XIUXIAN_UI_MOCK")
	return scene


func _texts(node: Node, out: Array[String] = []) -> Array[String]:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for child in node.get_children():
		_texts(child, out)
	return out


func _press(root: Node, node_name: String) -> void:
	var button := root.find_child(node_name, true, false) as Button
	assert_not_null(button, node_name)
	if button != null:
		button.pressed.emit()


func test_forget_session_clears_token_and_account() -> void:
	PlayerApi.save_token("tok-abc")
	PlayerApi.save_account("daoyou", "p-1")
	assert_eq(PlayerApi.token(), "tok-abc")
	assert_eq(str(PlayerApi.account().get("username", "")), "daoyou")
	PlayerApi.forget_session()
	assert_eq(PlayerApi.token(), "")
	assert_true(PlayerApi.account().is_empty())
	assert_false(FileAccess.file_exists(PlayerApi.TOKEN_PATH))


func test_audio_toggles_persist_and_mute_buses() -> void:
	assert_true(LocalSettings.music_on(), "默认开")
	assert_true(LocalSettings.sfx_on(), "默认开")
	LocalSettings.set_music_on(false)
	assert_false(LocalSettings.music_on())
	assert_true(LocalSettings.sfx_on())
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(LocalSettings.path), OK, "写到磁盘")
	assert_eq(cfg.get_value("audio", "music", true), false)
	var music := AudioServer.get_bus_index(LocalSettings.BUS_MUSIC)
	var sfx := AudioServer.get_bus_index(LocalSettings.BUS_SFX)
	assert_gt(music, 0, "Music 总线存在")
	assert_gt(sfx, 0, "SFX 总线存在")
	assert_true(AudioServer.is_bus_mute(music))
	assert_false(AudioServer.is_bus_mute(sfx))
	LocalSettings.set_sfx_on(false)
	LocalSettings.set_music_on(true)
	assert_false(AudioServer.is_bus_mute(music))
	assert_true(AudioServer.is_bus_mute(sfx))
	assert_false(LocalSettings.sfx_on(), "重新读文件仍是关")


func test_avatar_opens_settings_and_logout_returns_to_login() -> void:
	PlayerApi.save_token("tok-logout")
	PlayerApi.save_account("old_account", "p-9")
	var scene := await _boot()
	var settings := scene.get("_settings") as SettingsView
	var login := scene.get("_login") as PlayerLogin
	assert_false(login.visible)
	(scene.get("_top_bar") as TopBar).settings_pressed.emit()
	await wait_frames(2)
	assert_true(settings.visible, "点头像打开设置")
	var texts := _texts(settings)
	for wanted in ["设 置", "声音", "音乐", "音效", "更多", "敬请期待", "版本号", "检查更新", "退出登录", "修改密码", "绑定手机", "兑换码", "客服反馈", "用户协议与隐私政策"]:
		assert_has(texts, wanted)
	for gone in ["显示战斗记录", "满包：跳过掉落", "导出存档文本", "战报"]:
		assert_does_not_have(texts, gone)
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with("v") and t.contains("（")), "显示版本号 v名（号）")
	# 稿 v2：版本号旁的检查结果（演示数据算「已是最新版本」）+「致谢与版本」入口
	assert_eq((settings.find_child("UpdateState", true, false) as Label).text, "已是最新版本")
	assert_has(texts, "致谢与版本")
	_press(settings, "CreditsRow")
	await wait_frames(2)
	var popup := scene.get("_popup") as GamePopup
	assert_true(popup.visible, "打开致谢与版本")
	assert_eq(popup.title_label.text, "致谢与版本")
	assert_true(settings.visible, "叠在设置上面，设置不关")
	assert_gt(popup.get_index(), settings.get_index(), "致谢页画在设置上面")
	popup.close_popup()
	assert_true(settings.visible, "关掉回到设置")
	# 未开放：toast，弹窗不关
	_press(settings, "Locked_兑换码")
	assert_eq((scene.get("_toast") as Toast).text(), "功能暂未开放")
	assert_true(settings.visible, "设置弹窗不关")
	# 音乐开关：点一下关掉并写盘
	_press(settings, "MusicToggle")
	assert_false(LocalSettings.music_on())
	assert_false((settings.find_child("MusicToggle", true, false) as QToggleSwitch).is_on)
	# 退出登录 → 二次确认 → 取消回设置
	_press(settings, "LogoutButton")
	assert_true(settings.is_confirming())
	assert_has(_texts(settings), "确定要退出当前账号吗？")
	assert_eq(PlayerApi.token(), "tok-logout", "确认前不退出")
	_press(settings, "ConfirmCancel")
	assert_false(settings.is_confirming())
	assert_true(settings.visible, "取消回到设置")
	# 再来一次，退出
	_press(settings, "LogoutButton")
	_press(settings, "ConfirmLogout")
	await wait_frames(2)
	assert_eq(PlayerApi.token(), "", "令牌清掉")
	assert_true(PlayerApi.account().is_empty(), "账号记录清掉")
	assert_true(login.visible, "回到登录页")
	assert_false(settings.visible)
	assert_true((scene.get("_state") as Dictionary).is_empty(), "旧账号数据清空")
	assert_eq(int(scene.call("session_id")), 1)
	# 能登录另一个账号：登录页发 logged_in 后重新开始心跳
	PlayerApi.save_token("tok-other")
	PlayerApi.save_account("new_account", "p-10")
	login.hide()
	login.logged_in.emit()
	assert_false(login.visible)
	assert_eq(PlayerApi.token(), "tok-other")


func test_close_by_button_and_texts() -> void:
	var scene := await _boot()
	var settings := scene.get("_settings") as SettingsView
	(scene.get("_top_bar") as TopBar).settings_pressed.emit()
	await wait_frames(1)
	_press(settings, "CloseButton")
	assert_false(settings.visible)
	assert_eq(SettingsView.version_text({"version": "0.17.1", "versionCode": 39}), "v0.17.1（39）")
	assert_eq(SettingsView.mask_account("13812346612"), "138****6612")
	assert_eq(SettingsView.mask_account("daoyou01"), "da****01")
	assert_eq(SettingsView.mask_account("abc"), "abc")


func test_update_state_shows_next_to_version() -> void:
	var view := SettingsView.new()
	add_child_autofree(view)
	view.open({"version": "0.17.1", "versionCode": 39, "updateState": "new", "latestVersion": "0.17.2"})
	var state := view.find_child("UpdateState", true, false) as Label
	assert_eq(state.text, "发现新版本 v0.17.2")
	view.open({"version": "0.17.1", "versionCode": 39, "updateState": ""})
	assert_eq(state.text, "", "没查过不显示")
	view.set_checking(true)
	assert_eq((view.find_child("CheckUpdateButton", true, false) as Button).text, "检查中…")
	assert_true((view.find_child("CheckUpdateButton", true, false) as Button).disabled)
	view.show_latest()
	assert_eq(state.text, "已是最新版本")
	assert_false((view.find_child("CheckUpdateButton", true, false) as Button).disabled)
