extends SceneTree
## 开发用：第五批截图（演示数据「full」满包场景，不连服务器）：历练页满包提示 → 分解弹窗（默认 / 勾白绿 / 紫橙二次确认 / 分解后）
## → 装备详情强化消耗（够 / 不够 + 提示）。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_MOCK_SCENARIO=full godot --script res://scripts/dev/capture_b5.gd -- <输出目录>
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/b5_shot"
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _settle(40)
	(scene.get("_offline_popup") as Control).hide()
	scene.call("_show_page", "adventure")
	await _settle(30)
	_shot(out, "4_bagfull_hint")
	var stage := scene.get("_stage_page") as StagePage
	stage.bag_hint().pressed.emit()
	await _settle(20)
	_shot(out, "1_salvage_default")
	var dialog := scene.call("salvage_dialog") as SalvageDialog
	dialog.toggle_quality(0)
	dialog.toggle_quality(1)
	await _settle(12)
	_shot(out, "1b_salvage_selected")
	dialog.toggle_quality(3)
	dialog.toggle_quality(4)
	dialog.press_confirm()
	await _settle(16)
	_shot(out, "2_purple_confirm")
	dialog.rare_think_again()
	await _settle(6)
	dialog.toggle_quality(3)
	dialog.toggle_quality(4)
	dialog.press_confirm()
	await _settle(50)
	_shot(out, "2b_after_decompose")
	dialog.close()
	await create_timer(2.5).timeout
	scene.call("_show_page", "bag")
	await _settle(20)
	_shot(out, "5_bag_after")
	var bag := scene.get("_bag_page") as BagPage
	var pick: Dictionary = {}
	for item in bag.model.items:
		if BagModel.can_enhance(item) and not bool(item.get("equipped", false)) and int(item.get("rarity", 0)) >= 2:
			pick = item
			break
	if pick.is_empty():
		for item in bag.model.items:
			if BagModel.can_enhance(item):
				pick = item
				break
	bag.call("_on_slot", pick)
	await _settle(20)
	_shot(out, "3_enhance_cost")
	(scene.get("_item_popup") as ItemDetailPopup).close_popup()
	var state := scene.get("_state") as Dictionary
	for row in state.items:
		if str(row.itemSlug) == "refine_essence":
			row["quantity"] = 30
	state.erase("essence")
	scene.call("_render")
	await _settle(10)
	bag.call("_on_slot", bag.model.find(str(pick.id)))
	await _settle(20)
	var popup := scene.get("_item_popup") as ItemDetailPopup
	var one := popup.find_child("EnhanceOne", true, false) as Button
	if one != null:
		one.pressed.emit()
	await _settle(8)
	_shot(out, "3b_enhance_short")
	print("shots done")
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame
	await create_timer(0.6).timeout


func _shot(out: String, name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
