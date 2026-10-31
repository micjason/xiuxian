extends SceneTree

const OfflineViewScript = preload("res://scripts/model/offline_view.gd")
## 离线收益弹窗样式改版截图：短列表（吸底可见）+ 长列表滚动/折叠后吸底仍可见。
## 用法（需 xvfb，勿 --headless）：
##   XIUXIAN_UI_MOCK=1 XIUXIAN_SAFE_AREA=0,90,0,0 \
##   xvfb-run -a -s "-screen 0 1100x2400x24" Godot --path game --rendering-driver opengl3 \
##   --resolution 1080x2340 --script res://scripts/dev/capture_offline_popup_style.gd -- <outdir>

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/offline_popup_style"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 40:
		await process_frame
	await _wait(4.6)
	var popup = _scene.get("_offline_popup")
	if popup == null or not popup.visible:
		push_error("offline popup missing")
		quit(1)
		return
	_shot("01_short_sticky_footer")
	var long_loot: Array = []
	for i in 12:
		long_loot.append({"itemSlug": "gear_major1_gloves_white", "quality": "white", "quantity": 1, "idle": true})
		long_loot.append({"itemSlug": "gear_major1_helmet_green", "quality": "green", "quantity": 1, "idle": true})
		long_loot.append({"itemSlug": "mat_spirit_stone", "quality": "blue", "quantity": 3 + i, "idle": true})
		long_loot.append({"itemSlug": "pill_cultivate", "quality": "purple", "quantity": 1, "idle": false})
		long_loot.append({"itemSlug": "seed_lingcao", "quality": null, "quantity": 2, "seed": true})
	var report := {
		"id": "style-long",
		"seconds": 33120,
		"countedSeconds": 28800,
		"hitCap": true,
		"offlineCapSeconds": 28800,
		"gained": 33120.0,
		"baseGained": 28800.0,
		"bonusGained": 4320.0,
		"realmName": "炼气三层",
		"loot": long_loot,
		"bagFullSkipped": true,
		"power": 915,
	}
	var view = OfflineViewScript.build(report, "青元诀", 15.0, func(slug: String) -> String:
		if slug.begins_with("gear_major1_gloves"):
			return "白手套"
		if slug.begins_with("gear_major1_helmet"):
			return "绿头盔"
		if slug.begins_with("mat_"):
			return "灵石碎片"
		if slug.begins_with("pill_"):
			return "修为丹"
		if slug.begins_with("seed_"):
			return "灵草种子"
		return slug, 915.0)
	popup.show_report(view)
	await _wait(4.0)
	_shot("02_long_list_footer_visible")
	for child in _find_all(popup, "CategoryHead"):
		if child is Button:
			(child as Button).pressed.emit()
	await _wait(0.35)
	var scroll = popup.find_child("LootScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 80
	await _wait(0.4)
	_shot("03_long_scrolled_categories_collapsed")
	print("done -> ", _out)
	quit()


func _find_all(node: Node, wanted: String) -> Array:
	var out: Array = []
	if node.name == wanted:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_all(child, wanted))
	return out


func _shot(shot_name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("shot ", shot_name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
