extends SceneTree
## 新界面（4 页签 + 战斗 + 离线 + 突破）的截图脚本（开发用）。数据来自 ProtoMock，不连服务器。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_MOCK_SCENARIO=<ready|gate|full|fresh> godot --path game --resolution 1080x1920 \
##   --script res://scripts/dev/capture_v5.gd -- <输出目录> <场景名：ready|gate|full>

var _out := ""
var _kind := "ready"
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_shots_v5"
	_kind = args[1] if args.size() > 1 else "ready"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 30:
		await process_frame
	await _wait(1.0)
	match _kind:
		"ready":
			await _run_ready()
		"gate":
			await _run_gate()
		"full":
			await _run_full()
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await _wait(0.5)
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, name])
	print("shot ", name, " ", image.get_size())


func _page(name: String) -> void:
	_scene.call("_show_page", name)
	await _wait(0.3)


func _gate_slug() -> String:
	return str(((_scene.get("_state") as Dictionary).breakthrough.requiredStage as Dictionary).slug)


func _fight(tap: bool, until: float = 999.0, stop_for_shot: String = "") -> void:
	var page: BattlePage = _scene.get("_battle_page")
	var elapsed := 0.0
	while page.phase == BattlePage.Phase.RUNNING and elapsed < until:
		page.step(0.25)
		elapsed += 0.25
		if tap and page.fight.ult_ready() and not page.fight.casts.size() > 0:
			if not stop_for_shot.is_empty():
				await _wait(0.2)
				await _shot(stop_for_shot)
				stop_for_shot = ""
			pass  # 第四批：大招全自动，没有点击
	await _wait(0.5)


func _run_ready() -> void:
	# 离线收益弹窗（进入游戏就弹）
	await _shot("01_offline_popup")
	(_scene.get("_offline_popup") as OfflinePopup).claim_button().pressed.emit()
	await _wait(0.3)
	# 修炼主屏：波次进度 + 击杀/掉落反馈
	var state: Dictionary = _scene.get("_state")
	state["lastSettle"] = {"online": true, "seconds": 12, "passiveGained": 36, "kills": 4, "deaths": 0, "killCultivation": 20,
		"drops": [{"itemSlug": "gear_major1_helmet_green", "quantity": 1, "quality": "green"}], "bagFull": false}
	(state.wave as Dictionary)["progress"] = 0.62
	_scene.call("_render", true)
	await _shot("02_home")
	await _page("adventure")
	await _shot("03_adventure_list")
	_scene.call("_open_battle", _gate_slug())
	await _shot("04_battle_ready")
	var page: BattlePage = _scene.get("_battle_page")
	page._on_start()
	await _fight(true, 9.5)
	await _shot("05_battle_running_ult_ready")
	pass  # 第四批：大招全自动，没有点击
	await _fight(true, 3.0)
	await _shot("05b_battle_after_ult")
	await _fight(true)
	await _shot("06_battle_result")
	await _page("bag")
	await _shot("07_bag_merged")
	await _page("skill")
	await _shot("08_skill")
	await _page("cave")
	await _shot("09_cave")
	_scene.call("_open_breakthrough")
	await _wait(0.3)
	await _shot("10_breakthrough_ready")
	_scene.call("_on_breakthrough")
	await _wait(0.8)
	await _shot("11_breakthrough_success")


func _run_gate() -> void:
	_scene.call("_open_breakthrough")
	await _wait(0.3)
	await _shot("10b_breakthrough_blocked_by_boss")
	_scene.call("_open_battle", _gate_slug())
	var page: BattlePage = _scene.get("_battle_page")
	page._on_start()
	await _fight(false, 14.0)
	await _shot("06b_battle_auto_cast")


func _run_full() -> void:
	var state: Dictionary = _scene.get("_state")
	state["autoDecompose"] = false
	_scene.call("_render")
	await _page("bag")
	await _shot("07b_bag_full")
	_scene.call("_open_battle", _gate_slug())
	var page: BattlePage = _scene.get("_battle_page")
	page._on_start()
	await _fight(false, 60.0)
	await _shot("12a_bag_full_fight_result")
	_scene.call("_show_bag_full", 20, 20)
	await _wait(0.4)
	await _shot("12_bag_full_prompt")
