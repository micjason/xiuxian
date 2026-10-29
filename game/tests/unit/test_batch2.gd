extends GutTest
## 批次②（客户端）：部位 / 品质名字来自服务器统一表、品质 5 档无红、装备详情的套装信息、功法栏位按 state.skillSlots 显示。


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func after_each() -> void:
	# 恢复默认名字，别影响其他测试
	UiTokens.RARITY_NAMES = ["凡品", "良品", "精品", "珍品", "绝品"]
	SlotConfig.apply_names({})


func _server_content() -> Dictionary:
	var content := UiMock.content()
	content["globals"]["qualities"] = [
		{"key": "white", "name": "凡品·白", "short": "白", "sortOrder": 1},
		{"key": "green", "name": "良品", "short": "绿", "sortOrder": 2},
		{"key": "blue", "name": "精品", "short": "蓝", "sortOrder": 3},
		{"key": "purple", "name": "珍品", "short": "紫", "sortOrder": 4},
		{"key": "orange", "name": "绝品·橙", "short": "橙", "sortOrder": 5},
	]
	content["globals"]["slots"] = [
		{"key": "weapon", "name": "兵器", "glyph": "剑", "sortOrder": 1},
		{"key": "shoes", "name": "靴子", "glyph": "靴", "sortOrder": 5},
	]
	return content


func _item(model: BagModel, slug: String) -> Dictionary:
	for it in model.items:
		if str(it.slug) == slug:
			return it
	return {}


func test_slot_and_quality_names_come_from_server_tables() -> void:
	var content := _server_content()
	var model := BagModel.from_state(UiMock.state(), content)
	assert_eq(str(_item(model, "sword_r").rarity_name), "绝品·橙", "品质名来自 globals.qualities")
	assert_eq(str(SlotConfig.find("weapon").name), "兵器", "部位名来自 globals.slots")
	assert_eq(str(SlotConfig.find("shoes").name), "靴子")
	assert_eq(str(SlotConfig.find("helmet").name), "头冠", "服务器没给的部位用默认名（和服务器部位表一致）")
	assert_eq(ItemDetailView.kind_text(_item(model, "sword_r")), "兵器")
	assert_eq(UiTokens.RARITY_NAMES.size(), 5)


func test_default_names_match_server_catalog_and_no_red() -> void:
	var names: Array[String] = []
	for slot in SlotConfig.core():
		names.append(str(slot.name))
	assert_eq(names, ["武器", "头冠", "衣服", "护手", "鞋子", "饰品"] as Array[String])
	assert_eq(Catalog.QUALITY_KEYS.size(), 5)
	assert_false(Catalog.QUALITY_KEYS.has("red"))
	assert_false((UiMock.content()["globals"]["enhance"]["qualities"] as Dictionary).has("red"))


func test_set_view_counts_owned_and_worn_and_lights_tiers() -> void:
	var content := UiMock.content()
	var model := BagModel.from_state(UiMock.state(), content)
	var view := ItemDetailView.set_view(_item(model, "sword_r"), content, model)
	assert_eq(str(view.name), "青云套")
	assert_eq(int(view.total), 4)
	assert_eq(int(view.owned), 4, "四件都在背包 / 身上")
	assert_eq(int(view.worn), 1, "只穿着鞋子")
	assert_eq(str(view.summary), "已有 4/4 · 穿戴 1/4")
	assert_eq((view.tiers as Array).size(), 2)
	assert_false(bool(view.tiers[0].active), "穿 1 件不够 2 件档")
	assert_eq(str(view.tiers[0].text), "2 件：攻击 +5%")
	assert_eq(str(view.tiers[1].text), "4 件：气血 +8%、速度 +3")
	var shoe: Dictionary = (view.members as Array).filter(func(m: Dictionary) -> bool: return str(m.slug) == "shoe_b")[0]
	assert_true(bool(shoe.worn))
	assert_eq(str(shoe.slot_name), "鞋子")
	assert_true(ItemDetailView.set_view(_item(model, "sword_w"), content, model).is_empty(), "不属于套装的装备没有套装块")


func test_set_tier_turns_active_when_enough_pieces_worn() -> void:
	var content := UiMock.content()
	var state := UiMock.state()
	for row in state.items:
		if str(row.itemSlug) == "acc_o":
			row["equippedSlot"] = "accessory"
		elif str(row.itemSlug) == "acc_w":
			row["equippedSlot"] = null
	var model := BagModel.from_state(state, content)
	var view := ItemDetailView.set_view(_item(model, "acc_o"), content, model)
	assert_eq(int(view.worn), 2)
	assert_true(bool(view.tiers[0].active), "穿 2 件：2 件档生效")
	assert_false(bool(view.tiers[1].active))


func test_detail_popup_shows_set_section() -> void:
	var content := UiMock.content()
	var state := UiMock.state()
	var model := BagModel.from_state(state, content)
	var popup: ItemDetailPopup = load("res://scenes/ui/item_detail_popup.tscn").instantiate()
	add_child_autofree(popup)
	popup.show_view(ItemDetailView.build(_item(model, "sword_r"), {}, model, content, state), {})
	await get_tree().process_frame
	var section := popup.find_child("SetSection", true, false)
	assert_not_null(section, "装备详情里有套装块")
	var texts := popup.texts()
	assert_true(texts.has("套装 · 青云套"), "显示套装名")
	assert_true(texts.has("已有 4/4 · 穿戴 1/4"), "显示已有 / 穿戴件数")
	assert_true(texts.any(func(t: String) -> bool: return t.contains("2 件：攻击 +5%")), "显示档位加成")
	popup.close_popup()


func test_skill_slots_follow_state() -> void:
	var content := UiMock.content()
	var state := {
		"skillSlots": {"open": 2, "max": 4, "next": {"slots": 3, "realmOrder": 5, "realmName": "筑基初期"}},
		"skills": [
			{"skillSlug": "art1", "level": 1, "runningSlot": "run_2"},
			{"skillSlug": "heart1", "level": 2, "runningSlot": "heart"},
		],
	}
	var view := SkillView.slots_view(state, content)
	assert_eq(int(view.open), 2)
	assert_eq((view.cells as Array).size(), 4, "按 max 画 4 个栏位")
	assert_eq(str(view.cells[0].skill_slug), "heart1", "老运转名补进第一个空栏位")
	assert_eq(str(view.cells[1].skill_name), "青云剑诀")
	assert_false(bool(view.cells[2].open))
	assert_eq(str(view.cells[2].hint), "筑基初期开放")
	assert_eq(str(view.cells[3].hint), "未开放")
	assert_eq(str(view.note), "技能栏位 2/4 已开放 · 筑基初期开放第 3 栏")


func test_skill_slots_default_to_three_open_without_server_info() -> void:
	var view := SkillView.slots_view({}, {})
	assert_eq(int(view.open), 3)
	assert_eq((view.cells as Array).size(), 3)
	for cell in view.cells:
		assert_true(bool(cell.open))


func test_skill_page_renders_slot_cells() -> void:
	var page := SkillPage.new()
	add_child_autofree(page)
	var state := UiMock.state()
	state["skillSlots"] = {"open": 1, "max": 3, "next": {"slots": 2, "realmOrder": 3, "realmName": "炼气后期"}}
	page.bind(state, UiMock.content())
	await get_tree().process_frame
	assert_eq(page.equip_slot_buttons().size(), 3)
	var caption := page.find_child("SlotCaption_2", true, false) as Label
	assert_not_null(caption)
	assert_eq(caption.text, "炼气后期开放")
	assert_eq((page.find_child("SkillSlotNote", true, false) as Label).text, "技能栏位 1/3 已开放 · 炼气后期开放第 2 栏")
