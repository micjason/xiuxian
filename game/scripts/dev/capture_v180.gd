extends Node
## 开发用：0.18.0 线上截图（连测试服务器，不用演示数据）。服务器地址 XIUXIAN_API_BASE，账号 XIUXIAN_TEST_USER / XIUXIAN_TEST_PASS（行囊要先满）。
## 顺序：历练页满包提示 → 装备详情精粹不够（提示）→ 分解弹窗默认 → 勾白绿 → 再勾紫橙点分解出二次确认 → 再想想 → 只分解白绿（真的分解）
## → 装备详情强化消耗（够）。不点强化。
## 用法：godot --path game --resolution 1080x2340 res://scenes/dev/capture_v180.tscn -- <输出目录>
var _out := "/tmp/v180_shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	DirAccess.make_dir_recursive_absolute(_out)
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player_token.txt"))
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await _settle(40)
	if not await _login(scene):
		print("V180 login failed")
		get_tree().quit(1)
		return
	var offline := scene.get("_offline_popup") as Control
	if offline != null and offline.visible:
		offline.hide()
	if args.size() > 1 and args[1] == "rare":
		# 只补拍紫/橙二次确认（不分解）：从背包页「分解」打开
		scene.call("_show_page", "bag")
		await _settle(20)
		scene.call("open_salvage")
		await _settle(20)
		var d := scene.call("salvage_dialog") as SalvageDialog
		d.toggle_quality(2)
		d.toggle_quality(3)
		d.toggle_quality(4)
		d.press_confirm()
		await _settle(16)
		await _shot(args[2] if args.size() > 2 else "2_purple_confirm_fixed")
		get_tree().quit()
		return
	scene.call("_show_page", "adventure")
	await _settle(40)
	await _shot("4_bagfull_hint")
	scene.call("_show_page", "bag")
	await _settle(20)
	var bag := scene.get("_bag_page") as BagPage
	var pick := _pick(bag)
	bag.call("_on_slot", pick)
	await _settle(20)
	var popup := scene.get("_item_popup") as ItemDetailPopup
	var one := popup.find_child("EnhanceOne", true, false) as Button
	if one != null:
		one.pressed.emit()
	await _settle(8)
	await _shot("3b_enhance_short")
	popup.close_popup()
	await get_tree().create_timer(2.5).timeout
	scene.call("_show_page", "adventure")
	await _settle(20)
	(scene.get("_stage_page") as StagePage).bag_hint().pressed.emit()
	await _settle(20)
	await _shot("1_salvage_default")
	var dialog := scene.call("salvage_dialog") as SalvageDialog
	dialog.toggle_quality(0)
	dialog.toggle_quality(1)
	await _settle(12)
	await _shot("1b_salvage_selected")
	dialog.toggle_quality(3)
	dialog.toggle_quality(4)
	dialog.press_confirm()
	await _settle(16)
	await _shot("2_purple_confirm")
	dialog.rare_think_again()
	await _settle(6)
	dialog.toggle_quality(3)
	dialog.toggle_quality(4)
	dialog.press_confirm()
	for i in 60:
		await get_tree().create_timer(0.1).timeout
	await _settle(10)
	await _shot("2b_after_decompose")
	dialog.close()
	await get_tree().create_timer(2.5).timeout
	scene.call("_show_page", "bag")
	await _settle(20)
	bag.call("_on_slot", bag.model.find(str(pick.id)))
	await _settle(20)
	await _shot("3_enhance_cost")
	var st := scene.get("_state") as Dictionary
	print("V180 essence=%s bagUsed=%s version=%s" % [JSON.stringify(st.get("essence")), str(st.get("bagUsed")), str(ProjectSettings.get_setting("application/config/version"))])
	get_tree().quit()


func _pick(bag: BagPage) -> Dictionary:
	for item in bag.model.items:
		if BagModel.can_enhance(item) and not bool(item.get("equipped", false)) and int(item.get("rarity", 0)) == 2:
			return item
	for item in bag.model.items:
		if BagModel.can_enhance(item):
			return item
	return {}


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


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)
