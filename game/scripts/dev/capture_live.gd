extends Node
## 开发用：连真实服务器截图（不用演示数据）。服务器地址用环境变量 XIUXIAN_API_BASE（可以是 SSH 隧道 http://127.0.0.1:端口）。
## 用法：godot --path game res://scenes/dev/capture_live.tscn -- <输出目录> <模式>（用场景启动，自动加载的 ApiClient 才在）
##   update：假装是旧版本（XIUXIAN_FAKE_VERSION_CODE，默认 30），等「发现新版本」弹窗出现后截图 01_update_popup.png
##   play：  先截登录页 02_login.png；用 XIUXIAN_TEST_USER / XIUXIAN_TEST_PASS 注册（已存在就登录），等真实数据进来后截主界面
##          03_main.png 和历练页 04_adventure.png。不检查更新（XIUXIAN_UPDATE_CHECK=0）。
## 输出一行 LIVE … 供脚本检查。

var _out := "/tmp/live_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	var mode := args[1] if args.size() > 1 else "update"
	DirAccess.make_dir_recursive_absolute(_out)
	if mode == "update":
		ProjectSettings.set_setting("xiuxian/build/version_code", int(OS.get_environment("XIUXIAN_FAKE_VERSION_CODE") if OS.has_environment("XIUXIAN_FAKE_VERSION_CODE") else "30"))
		ProjectSettings.set_setting("application/config/version", OS.get_environment("XIUXIAN_FAKE_VERSION_NAME") if OS.has_environment("XIUXIAN_FAKE_VERSION_NAME") else "0.10.1-proto")
	else:
		OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player_token.txt"))  # 从登录页开始
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	if mode == "update":
		await _run_update(scene)
	else:
		await _run_play(scene)
	get_tree().quit()


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s" % [_out, name])
	print("shot ", name)


func _find_popup(scene: Node) -> GamePopup:
	for child in scene.get_children():
		if child is GamePopup:
			return child
	return null


func _run_update(scene: Node) -> void:
	var popup := _find_popup(scene)
	for i in 300:
		await get_tree().process_frame
		if popup != null and popup.visible and popup.title_label.text.begins_with("发现新版本"):
			await get_tree().create_timer(0.8).timeout
			await _shot("01_update_popup.png")
			print("LIVE update_popup title=%s" % popup.title_label.text)
			return
		await get_tree().create_timer(0.05).timeout
	await _shot("01_update_popup_MISSING.png")
	print("LIVE update_popup MISSING")


func _run_play(scene: Node) -> void:
	for i in 40:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	await _shot("02_login.png")
	var user := OS.get_environment("XIUXIAN_TEST_USER")
	var pass_word := OS.get_environment("XIUXIAN_TEST_PASS")
	var login := scene.find_children("*", "PlayerLogin", true, false)
	if login.is_empty() or user.is_empty():
		print("LIVE play MISSING login/user")
		return
	var form: PlayerLogin = login[0]
	var edits := form.find_children("*", "LineEdit", true, false)
	(edits[0] as LineEdit).text = user
	(edits[1] as LineEdit).text = pass_word
	await form._submit(true)  # 注册；用户名已存在时再登录
	if form.visible:
		await form._submit(false)
	print("LIVE auth logged_in=%s" % str(not form.visible))
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		if not form.visible and scene.get("_state") is Dictionary and not (scene.get("_state") as Dictionary).is_empty():
			break
	await get_tree().create_timer(2.0).timeout
	await _shot("03_main.png")
	var state: Dictionary = scene.get("_state") if scene.get("_state") is Dictionary else {}
	print("LIVE play realm=%s cultivation=%s" % [str(state.get("realmName", "?")), str(state.get("cultivation", "?"))])
	scene.call("_show_page", "adventure")
	await get_tree().create_timer(1.5).timeout
	await _shot("04_adventure.png")
