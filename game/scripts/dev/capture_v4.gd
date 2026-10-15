extends SceneTree
## 强化 v2 的关键画面截图（开发用，不进游戏）：突破节点、红色强化卡、已穿戴不能分解、后台之外的游戏端部分。
## 用法：XIUXIAN_UI_MOCK=1 godot --path game --resolution 1080x1920 --script res://scripts/dev/capture_v4.gd -- <输出目录>
## 数据来自 UiMock，不连服务器；需要真实窗口或 xvfb。

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_shots_v4"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 30:
		await process_frame
	await _wait(1.0)
	await _run()
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


func _item_id(slug: String) -> String:
	for row in (_scene.get("_state") as Dictionary).get("items", []):
		if str(row.get("itemSlug", "")) == slug:
			return str(row.get("id", ""))
	return ""


func _scroll_popup_to_bottom(popup: GamePopup) -> void:
	await _wait(0.2)
	var scroll: ScrollContainer = popup.get("_scroll")
	if scroll != null:
		scroll.scroll_vertical = 100000


func _run() -> void:
	var bag: BagPage = _scene.get("_bag_page")
	var character: CharacterPage = _scene.get("_char_page")
	var popup: GamePopup = _scene.get("_popup")
	await _page("bag")
	# 1. 卡在 +5 突破节点、材料不够（紫色武器：下品突破石 6 / 8）
	bag.show_detail(_item_id("sword_p"))
	await _shot("01_enhance_card_break_node_short")
	await _scroll_popup_to_bottom(popup)
	await _shot("01b_enhance_card_break_node_short_bottom")
	popup.close_popup()
	# 2. 还没到节点：显示下一个突破节点的要求（橙色佩饰 +4）
	bag.show_detail(_item_id("acc_o"))
	await _scroll_popup_to_bottom(popup)
	await _shot("02_enhance_card_next_node_hint")
	popup.close_popup()
	# 3. 红色（仙品）装备也能强化
	bag.show_detail(_item_id("sword_r"))
	await _scroll_popup_to_bottom(popup)
	await _shot("03_red_gear_enhance_card")
	popup.close_popup()
	# 4. 已穿戴的装备：分解按钮置灰并写明原因
	await _page("character")
	character._on_slot("weapon")
	await _scroll_popup_to_bottom(popup)
	await _shot("04_worn_gear_decompose_disabled")
	popup.close_popup()
	# 5. 已穿戴的靴子卡在 +5、材料齐了：「突破」可点
	character._on_slot("shoes")
	await _scroll_popup_to_bottom(popup)
	await _shot("05_worn_gear_break_ready")
	# 点「突破」→ 突破成功提示 + 回到详情（节点已通过，可以继续强化）
	_scene.call("_breakthrough", _item_id("shoe_b"))
	await _wait(0.4)
	popup.close_popup()
	character._on_slot("shoes")
	await _scroll_popup_to_bottom(popup)
	await _shot("06_after_break_through")
	popup.close_popup()
	# 6. 服务器拒绝分解已穿戴装备时，客户端只显示服务器给的原因，不破坏状态
	await _scene.call("_decompose_many", [_item_id("sword_g")])
	await _shot("07_decompose_worn_rejected_toast")
