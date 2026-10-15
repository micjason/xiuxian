extends SceneTree
## 演示模式下逐页截图（开发用，不进游戏）。
## 用法：XIUXIAN_UI_MOCK=1 godot --path game --resolution 1080x1920 --script res://scripts/dev/capture_pages.gd -- <输出目录> [login]  （login：不设 XIUXIAN_UI_MOCK，截登录页）
## 数据全部来自 UiMock，不连服务器；需要真实窗口或 xvfb。

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_shots"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 30:
		await process_frame
	await _wait(1.0)
	if args.has("login"):
		await _shot("00_login")
	else:
		await _run()
	quit()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _shot(name: String) -> void:
	await _wait(0.45)
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [_out, name])
	print("shot ", name, " ", image.get_size())


func _page(name: String) -> void:
	_scene.call("_show_page", name)
	await _wait(0.3)


func _item_id(slug: String) -> String:
	for row in (_scene.get("_state") as Dictionary).get("items", []):
		if str(row.get("itemSlug", "")) == slug:
			return str(row.get("id", ""))
	return ""


func _run() -> void:
	var bag: BagPage = _scene.get("_bag_page")
	var character: CharacterPage = _scene.get("_char_page")
	var stage: StagePage = _scene.get("_stage_page")
	var popup: GamePopup = _scene.get("_popup")
	await _page("cultivate")
	await _shot("01_home")
	await _page("adventure")
	await _shot("02_stage_list")
	await _page("character")
	await _shot("03_character_top")
	character.scroll_vertical = 1100
	await _shot("04_character_bottom")
	character.scroll_vertical = 0
	# 装备栏：点已穿戴的武器 → 带强化的详情；点空的手部 → 可替换列表
	character._on_slot("weapon")
	await _shot("05_equipped_weapon_detail")
	popup.close_popup()
	character._on_slot("gloves")
	await _shot("06_gloves_picker")
	popup.close_popup()
	character._on_slot("pet")
	await _shot("07_reserved_slot_popup")
	popup.close_popup()
	await _page("bag")
	await _shot("08_bag_grid")
	bag.show_detail(_item_id("acc_o"))
	await _shot("09_orange_detail_enhance")
	popup.close_popup()
	bag.show_detail(_item_id("sword_p"))
	await _shot("10_gear_detail_compare")
	popup.close_popup()
	bag._tabs.select("material", true)
	await _shot("11_bag_material_tab")
	bag._tabs.select("equip", true)
	bag.sort_index = 2
	bag.refresh()
	bag._toggle_batch()
	var ids := bag.model.visible_items("equip", "power")
	bag._grid._on_slot(ids[0])
	bag._grid._on_slot(ids[2])
	bag._grid._on_slot(ids[3])
	await _shot("12_bag_batch_select")
	bag._confirm_batch()
	await _shot("13_batch_confirm")
	popup.close_popup()
	bag._toggle_batch()
	# 强化一次，看经验条和结果提示
	_scene.call("_enhance", _item_id("acc_o"), false)
	await _wait(0.4)
	await _shot("14_after_enhance_toast")
	popup.close_popup()
	# 战斗：挑战后战报
	await _page("adventure")
	_scene.call("_select_stage", "s1")
	await _wait(0.3)
	stage._stage_view.scroll_vertical = 0
	await _shot("15_stage_selected")
	await _scene.call("_on_challenge")
	await _shot("16_battle_report")
	await _page("skill")
	await _shot("17_skill_page")
	CreditsView.show_credits(popup)
	await _shot("18_credits")
	popup.close_popup()
