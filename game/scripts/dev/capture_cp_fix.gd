extends SceneTree
## 成鹏④⑤ hotfix 截图：离线 dismiss+宝箱再开、历练 Boss 行固定高+clip。

var _out := ""
var _scene: Node


func _initialize() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", "ready")
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/cp_fix_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 40:
		await process_frame
	await _wait(0.8)
	# ① 开机离线收益弹窗
	await _shot("01_offline_popup")
	# ② 点关闭 = dismiss，报告仍在
	var popup: OfflinePopup = _scene.get("_offline_popup")
	popup.close_button().pressed.emit()
	await _wait(0.5)
	await _shot("02_offline_dismissed_chest_dot")
	# ③ 宝箱再开
	(_scene.get("_home_page") as HomePage).chest_button().pressed.emit()
	await _wait(0.5)
	await _shot("03_offline_reopened_via_chest")
	popup.claim_button().pressed.emit()
	await _wait(0.45)
	# ④ 历练页 Boss 行
	_scene.call("_show_page", "adventure")
	await _wait(0.5)
	await _shot("04_adventure_boss_rows")
	# 选中一张可挑战卡，看 300 高 + 奖励
	var page: StagePage = _scene.get("_stage_page")
	var list := page.find_child("StageCards", true, false)
	if list != null:
		for child in list.get_children():
			if str(child.name).begins_with("Stage_"):
				(child as BaseButton).pressed.emit()
				await _wait(0.4)
				break
	await _shot("05_adventure_selected_rewards")
	print("cp_fix shots done → ", _out)
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await _wait(0.2)
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, name])
	print("shot ", name, " ", image.get_size())
