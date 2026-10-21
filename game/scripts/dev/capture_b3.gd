extends Node
## 开发用：第三批截图（连本地 / 测试服务器，不用演示数据）。服务器地址 XIUXIAN_API_BASE，账号 XIUXIAN_TEST_USER / XIUXIAN_TEST_PASS。
## 用法：godot --path game --resolution 1080x2340 res://scenes/dev/capture_b3.tscn -- <输出目录> <模式> [关卡 slug] [文件名]
##   list：  历练页（章节页签 + 竖排关卡卡）→ <文件名>
##   scene： 历练页不滚动（场景区 + 右下角精英预览小卡）→ <文件名>
##   battle：点关卡卡上的按钮进首领战，点开始，登场后截图 → <文件名>（截完就退出，不提交战斗）

var _out := "/tmp/b3_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	var mode := args[1] if args.size() > 1 else "list"
	var stage := args[2] if args.size() > 2 else ""
	var file := args[3] if args.size() > 3 else "game_%s.png" % mode
	DirAccess.make_dir_recursive_absolute(_out)
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player_token.txt"))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	for i in 40:
		await get_tree().process_frame
	if not await _login(scene):
		print("B3 login failed")
		get_tree().quit(1)
		return
	var offline := scene.get("_offline_popup") as Control
	if offline != null and offline.visible:
		offline.call("close_popup")
	scene.call("_show_page", "adventure")
	await get_tree().create_timer(1.5).timeout
	var page := scene.get("_stage_page") as StagePage
	if not stage.is_empty():
		scene.call("_select_stage", stage)
		await get_tree().create_timer(0.6).timeout
	if mode == "scene":
		await get_tree().create_timer(0.4).timeout
		print("B3 preview visible=%s slug=%s" % [str(page.preview_card().visible), page.preview_slug()])
		await _shot(file)
	elif mode == "list":
		# 滚到章节页签那里，让关卡卡多露一些
		var view := page.get("_stage_view") as ScrollContainer
		var tabs := page.find_child("ChapterTabs", true, false) as Control
		if tabs != null:
			view.scroll_vertical = int(tabs.position.y)
		await get_tree().create_timer(0.4).timeout
		await _shot(file)
	else:
		var button := page.challenge_button_for(stage)
		print("B3 button %s text=%s disabled=%s" % [stage, button.text if button else "-", str(button.disabled) if button else "-"])
		if button == null or button.disabled:
			get_tree().quit(1)
			return
		button.pressed.emit()
		await get_tree().create_timer(0.8).timeout
		var battle: Node = scene.get("_battle_page")
		battle.call("_on_start")
		await get_tree().create_timer(2.6).timeout
		await _shot(file)
		var fx: Node = battle.get("_fx")
		print("B3 battle stage=%s tier=%s fx=%s bg=%s" % [stage, str(fx.get("tier")), str((fx.get("boss") as Node).get("fx_variant")), str((scene.get("_backdrop") as Node).call("current_background"))])
	get_tree().quit()


func _login(scene: Node) -> bool:
	var login := scene.find_children("*", "PlayerLogin", true, false)
	if login.is_empty():
		return false
	var form: PlayerLogin = login[0]
	var edits := form.find_children("*", "LineEdit", true, false)
	(edits[0] as LineEdit).text = OS.get_environment("XIUXIAN_TEST_USER")
	(edits[1] as LineEdit).text = OS.get_environment("XIUXIAN_TEST_PASS")
	await form._submit(false)
	for i in 300:
		await get_tree().create_timer(0.1).timeout
		if not form.visible and scene.get("_state") is Dictionary and not (scene.get("_state") as Dictionary).is_empty():
			await get_tree().create_timer(1.5).timeout
			return true
	return false


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s" % [_out, name])
	print("shot ", name)
