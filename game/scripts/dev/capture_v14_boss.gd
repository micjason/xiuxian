extends SceneTree
## v14 首领战特效截图（开发用，不进游戏）：真实首领战页面 + 演示数据（ProtoMock），首领气血不改。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_MOCK_SCENARIO=full XIUXIAN_SAFE_AREA=0,90,0,0 xvfb-run godot --path game --rendering-driver opengl3 \
##   --resolution 1080x2340 --fixed-fps 30 --script res://scripts/dev/capture_v14_boss.gd -- <输出目录> [关卡 slug]
## 存 v14_boss_hit.png（第一次普攻打中）、v14_boss_ult.png（大招最后一剑打中）、v14_boss_result.png（结算面板）。

var _out := "/tmp/ui_v14_boss"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else _out
	var stage := args[1] if args.size() > 1 else "lianqi_3"
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 10:
		await process_frame
	var offline := scene.get("_offline_popup") as Control
	if offline != null and offline.visible:
		offline.call("close_popup")
	scene.call("_open_battle", stage)
	var page: Node = scene.get("_battle_page")
	var fight: BossFight = page.get("fight")
	for i in 30:
		await process_frame
	var fx: Node = page.get("_fx")
	var big := fx.get_node("Front/BigNumber") as Node2D
	var hits := [0]
	fx.connect("number_shown", func(side: String, _d: int) -> void:
		if side == "boss":
			hits[0] += 1)
	page.call("_on_start")
	var hit_shot := false
	var ult_shot := false
	var since := -1
	var n := 0
	while n < 30 * 120:
		await process_frame
		n += 1
		if fight.ult_ready() and int(page.get("phase")) == 1:
			page.call("_on_ult_tapped")
		if not hit_shot and hits[0] >= 1 and not big.visible:
			for k in 3:
				await process_frame
			_shot("v14_boss_hit")
			hit_shot = true
		if not ult_shot and big.visible:
			since = 0 if since < 0 else since + 1
			if since == 3:
				ult_shot = true
				_shot("v14_boss_ult")
		var panel := page.get("_result_panel") as Control
		if panel != null and panel.visible:
			for k in 20:
				await process_frame
			_shot("v14_boss_result")
			break
	print("BOSS done win=", fight.win, " reason=", fight.reason, " frames=", n, " hit=", hit_shot, " ult=", ult_shot)
	quit()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)
