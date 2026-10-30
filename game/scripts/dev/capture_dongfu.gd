extends Node
## 连真实服务器截洞府 L0 + L1 真场景（无线框）。
## 用法：XIUXIAN_API_BASE=http://101.132.74.32:8090 XIUXIAN_TEST_ACCOUNT_FILE=... XIUXIAN_UPDATE_CHECK=0 \
##   xvfb-run -a godot --path game --resolution 1080x2340 res://scenes/dev/capture_dongfu.tscn -- /out/dir

var _out := "/tmp/dongfu_shots"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player_token.txt"))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run(scene)
	get_tree().quit()

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s" % [_out, name])
	print("shot ", name)

func _hide_popups(scene: Node) -> void:
	var offline: Variant = scene.get("_offline_popup")
	if offline is Control:
		(offline as Control).hide()
	for child in scene.get_children():
		if child is GamePopup:
			(child as GamePopup).hide()

func _test_account() -> Dictionary:
	var out := {"XIUXIAN_TEST_USER": OS.get_environment("XIUXIAN_TEST_USER"), "XIUXIAN_TEST_PASS": OS.get_environment("XIUXIAN_TEST_PASS")}
	var path := OS.get_environment("XIUXIAN_TEST_ACCOUNT_FILE")
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var at := line.find("=")
		if at > 0:
			out[line.substr(0, at).strip_edges()] = line.substr(at + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out

func _login(scene: Node) -> bool:
	for i in 40:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var account := _test_account()
	var user := str(account.get("XIUXIAN_TEST_USER", ""))
	var pass_word := str(account.get("XIUXIAN_TEST_PASS", ""))
	var login := scene.find_children("*", "PlayerLogin", true, false)
	if login.is_empty() or user.is_empty():
		print("DONGFU capture MISSING login/user")
		return false
	var form: PlayerLogin = login[0]
	var edits := form.find_children("*", "LineEdit", true, false)
	(edits[0] as LineEdit).text = user
	(edits[1] as LineEdit).text = pass_word
	await form._submit(true)
	if form.visible:
		await form._submit(false)
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		if not form.visible and scene.get("_state") is Dictionary and not (scene.get("_state") as Dictionary).is_empty():
			break
	await get_tree().create_timer(1.5).timeout
	_hide_popups(scene)
	print("DONGFU auth ok=%s" % str(not form.visible))
	return not form.visible

func _run(scene: Node) -> void:
	if not await _login(scene):
		return
	_hide_popups(scene)
	scene.call("_show_page", "cave")
	await get_tree().create_timer(2.0).timeout
	_hide_popups(scene)
	await _shot("01_l0_courtyard.png")
	var cave: CavePage = scene.get("_cave_page")
	if cave == null:
		print("DONGFU MISSING cave_page")
		return
	cave._enter_facility("garden")
	await get_tree().create_timer(1.2).timeout
	_hide_popups(scene)
	await _shot("02_l1_garden.png")
	cave._on_back()
	await get_tree().create_timer(0.4).timeout
	cave._enter_facility("alchemy")
	await get_tree().create_timer(1.2).timeout
	_hide_popups(scene)
	await _shot("03_l1_alchemy.png")
	cave._on_back()
	await get_tree().create_timer(0.4).timeout
	cave._enter_facility("enhance")
	await get_tree().create_timer(1.2).timeout
	_hide_popups(scene)
	await _shot("04_l1_enhance.png")
	print("DONGFU capture done out=%s" % _out)
