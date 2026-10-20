extends SceneTree
## Q 版 7 屏截图（开发用，不进游戏）：修炼、历练、背包、功法、洞府、离线收益弹窗、突破弹窗。数据来自 ProtoMock。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_SAFE_AREA=0,90,0,0 godot --path game --resolution 1080x2340 --script res://scripts/dev/capture_q.gd -- <输出目录>

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_q"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 30:
		await process_frame
	await _wait(1.2)
	_shot("q_offline_popup")
	(_scene.get("_offline_popup") as Control).hide()
	for entry in [["cultivate", "q_cultivate"], ["adventure", "q_adventure"], ["bag", "q_bag"], ["skill", "q_techniques"], ["cave", "q_cave"]]:
		_scene.call("_show_page", entry[0])
		await _wait(0.8)
		_shot(entry[1])
	_scene.call("_show_page", "cultivate")
	await _wait(0.3)
	_scene.call("_open_breakthrough")
	await _wait(1.0)
	_shot("q_breakthrough_popup")
	quit()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
