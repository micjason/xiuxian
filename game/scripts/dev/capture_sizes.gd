extends SceneTree
## 按窗口尺寸截 5 个主页面，并打印布局数据（开发用，不进游戏）。数据来自 ProtoMock，不连服务器。
## 用法：XIUXIAN_UI_MOCK=1 godot --path game --resolution 540x1170 --script res://scripts/dev/capture_sizes.gd -- <输出目录> [前缀]
## 每页打印：视口大小、页签栏下沿与视口下沿的距离（应为 0）、内容区下沿与页签栏上沿的距离（应 ≥ 0）。

var _out := ""
var _prefix := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_shots_sizes"
	_prefix = args[1] if args.size() > 1 else ""
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 30:
		await process_frame
	await _wait(1.0)
	(_scene.get("_offline_popup") as Control).hide()
	for entry in [["cultivate", "01_cultivate"], ["adventure", "02_adventure"], ["bag", "03_bag"], ["skill", "04_skill"], ["cave", "05_cave"]]:
		_scene.call("_show_page", entry[0])
		await _wait(0.5)
		_report(entry[1])
		var image := root.get_viewport().get_texture().get_image()
		image.save_png("%s/%s%s.png" % [_out, _prefix, entry[1]])
		if entry[0] == "adventure":
			# 滚到最下面：看首领 / 关卡详情和固定在底部的挑战按钮
			var view := (_scene.get("_stage_page") as StagePage).get("_stage_view") as ScrollContainer
			view.scroll_vertical = 100000
			await _wait(0.4)
			root.get_viewport().get_texture().get_image().save_png("%s/%s02b_adventure_detail.png" % [_out, _prefix])
			view.scroll_vertical = 0
			await _wait(0.2)
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _report(name: String) -> void:
	var view := root.get_visible_rect().size
	var tab: Control = _scene.get("_tab_bar")
	var host: Control = _scene.get("_page_host")
	var tab_rect := tab.get_global_rect()
	var host_rect := host.get_global_rect()
	print("LAYOUT %s window=%s viewport=%s tab_bottom_gap=%.1f tab_top=%.1f content_bottom=%.1f content_over_tab=%.1f" % [
		name, root.size, view, view.y - tab_rect.end.y, tab_rect.position.y, host_rect.end.y,
		host_rect.end.y - tab_rect.position.y])
