extends SceneTree

const OfflineViewScript = preload("res://scripts/model/offline_view.gd")
## 极简离线收益弹窗截图：摘要（时长/修为/件数）+ 吸底一键领取；无滚动条、无装备列表。
## 用法（需 xvfb，勿 --headless）：
##   XIUXIAN_UI_MOCK=1 XIUXIAN_SAFE_AREA=0,90,0,0 \
##   xvfb-run -a -s "-screen 0 1100x2400x24" Godot --path game --rendering-driver opengl3 \
##   --resolution 1080x2340 --script res://scripts/dev/capture_offline_popup_minimal.gd -- <outdir>

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/offline_popup_minimal"
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
	# 即使 mock 报告带 loot，极简 UI 也不应出现滚动列表节点。
	if popup.find_child("LootScroll", true, false) != null:
		push_error("LootScroll should be gone in minimal popup")
		quit(2)
		return
	_shot("01_minimal_summary_claim")
	# 再喂一份带大量 loot 的报告：仍只显示件数摘要，不列装备。
	var long_loot: Array = []
	for i in 20:
		long_loot.append({"itemSlug": "gear_major1_gloves_white", "quality": "white", "quantity": 1, "idle": true})
		long_loot.append({"itemSlug": "mat_spirit_stone", "quality": "blue", "quantity": 3 + i, "idle": true})
	var report := {
		"id": "minimal-long",
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
		if slug.begins_with("gear_"):
			return "白手套"
		if slug.begins_with("mat_"):
			return "灵石碎片"
		return slug, 915.0)
	popup.show_report(view)
	await _wait(4.0)
	if popup.find_child("LootScroll", true, false) != null or popup.find_child("CategoryHead", true, false) != null:
		push_error("loot list leaked into minimal popup")
		quit(3)
		return
	var count_chip = popup.find_child("ItemCountChip", true, false)
	if count_chip == null:
		push_error("ItemCountChip missing")
		quit(4)
		return
	_shot("02_minimal_many_items_count_only")
	print("done -> ", _out)
	print("note: update-gate is ordering logic in play_screen; hard to mock live latest.json here")
	quit()


func _shot(shot_name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("shot ", shot_name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
