extends GutTest
## 洞府药园 / 炼丹界面文案必须是中文 displayName，不能露出物品 slug。


func test_missing_display_name_keeps_chinese_ui_copy() -> void:
	var content := {
		"globals": {
			"dongfu": {
				"seeds": [
					{"seedSlug": "seed_lingcao", "herbSlug": "herb_lingcao", "growSeconds": 60},
					{"seedSlug": "seed_qingxin", "herbSlug": "herb_qingxin", "growSeconds": 120},
				],
				"recipes": [
					{
						"recipeSlug": "pill_cultivate",
						"outputItemSlug": "pill_cultivate",
						"outputQty": 1,
						"craftSeconds": 30,
						"spiritStones": 0,
						"costs": [{"itemSlug": "herb_lingcao", "count": 2}],
					},
					{
						"recipeSlug": "pill_atk_temp",
						"outputItemSlug": "pill_atk_temp",
						"outputQty": 1,
						"craftSeconds": 45,
						"spiritStones": 5,
						"costs": [
							{"itemSlug": "herb_qingxin", "count": 1},
							{"itemSlug": "not_a_real_item", "count": 1},
						],
					},
				],
			},
		},
		"items": [
			{"slug": "seed_lingcao"},
			{"slug": "herb_lingcao", "displayName": ""},
			{"slug": "pill_cultivate", "displayName": "pill_cultivate"},
		],
	}
	var state := {
		"spiritStones": 0,
		"items": [],
		"dongfu": {
			"plotCount": 2,
			"alchemyQueueLength": 2,
			"woodItemSlug": "wood_lingmu",
			"plots": [
				{"slot": 0, "seedSlug": "seed_lingcao", "herbSlug": "herb_lingcao", "plantedAt": "2026-01-01T00:00:00.000Z", "matureAt": "2099-01-01T00:00:00.000Z", "status": "growing"},
				{"slot": 1, "seedSlug": "seed_qingxin", "herbSlug": "herb_qingxin", "plantedAt": "2026-01-01T00:00:00.000Z", "matureAt": "2020-01-01T00:00:00.000Z", "status": "ready"},
			],
			"alchemy": [
				{"id": "j1", "recipeSlug": "pill_def_temp", "startedAt": "2026-01-01T00:00:00.000Z", "readyAt": "2020-01-01T00:00:00.000Z", "status": "ready", "outputItemSlug": "pill_def_temp", "outputQty": 1},
			],
			"claimable": {"plots": 1, "alchemy": 1},
		},
	}
	var view := CaveView.build(state, content)
	var growing: Dictionary = (view.get("plots", []) as Array)[0]
	var ready: Dictionary = (view.get("plots", []) as Array)[1]
	assert_string_contains(str(growing.get("line", "")), "灵草种子")
	assert_false(_has_slug(str(growing.get("line", "")), "seed_lingcao"))
	assert_string_contains(str(ready.get("line", "")), "清心草")
	assert_false(_has_slug(str(ready.get("line", "")), "herb_qingxin"))
	assert_false(_has_slug(str(ready.get("line", "")), "seed_qingxin"))
	var seeds: Array = view.get("seeds", [])
	assert_eq(str((seeds[0] as Dictionary).get("name", "")), "灵草种子")
	assert_eq(str((seeds[1] as Dictionary).get("name", "")), "清心草种子")
	var job: Dictionary = (view.get("alchemy", []) as Array)[0]
	assert_eq(str(job.get("outputName", "")), "防御临时丹")
	assert_false(_has_slug(str(job.get("line", "")), "pill_def_temp"))
	var recipes: Array = view.get("recipes", [])
	var cultivate: Dictionary = recipes[0]
	assert_eq(str(cultivate.get("outputName", "")), "修为丹")
	assert_false(_has_slug(str(cultivate.get("outputName", "")), "pill_cultivate"))
	assert_false(_has_slug(str(cultivate.get("costLine", "")), "herb_lingcao"))
	assert_string_contains(str(cultivate.get("costLine", "")), "灵草")
	var attack: Dictionary = recipes[1]
	assert_eq(str(attack.get("outputName", "")), "攻击临时丹")
	assert_string_contains(str(attack.get("costLine", "")), "清心草")
	assert_string_contains(str(attack.get("costLine", "")), "未知物品")
	assert_false(_has_slug(str(attack.get("costLine", "")), "not_a_real_item"))
	assert_false(_has_slug(str(attack.get("outputName", "")), "pill_atk_temp"))
	assert_eq(str(view.get("woodName", "")), "灵木")
	assert_eq(CaveView.item_name({"items": [{"slug": "seed_lingcao", "displayName": "特制灵草种子"}]}, "seed_lingcao"), "特制灵草种子")


func test_alchemy_page_hides_recipe_slug() -> void:
	var page := CavePage.new()
	add_child_autofree(page)
	page.bind({
		"spiritStones": 10,
		"items": [{"id": "s1", "itemSlug": "seed_lingcao", "quantity": 2, "isStack": true}],
		"dongfu": {
			"plotCount": 1,
			"alchemyQueueLength": 2,
			"woodItemSlug": "wood_lingmu",
			"plots": [{"slot": 0, "seedSlug": null, "herbSlug": null, "plantedAt": null, "matureAt": null, "status": "empty"}],
			"alchemy": [],
			"claimable": {"plots": 0, "alchemy": 0},
		},
	}, {
		"globals": {"dongfu": {
			"plotCount": 1,
			"alchemyQueueLength": 2,
			"seeds": [{"seedSlug": "seed_lingcao", "herbSlug": "herb_lingcao", "growSeconds": 60}],
			"recipes": [{
				"recipeSlug": "pill_cultivate",
				"outputItemSlug": "pill_cultivate",
				"outputQty": 1,
				"craftSeconds": 30,
				"spiritStones": 0,
				"costs": [{"itemSlug": "herb_lingcao", "count": 2}],
			}],
		}},
		"items": [],
	})
	var enter := page.find_child("Enter_alchemy", true, false) as BaseButton
	assert_not_null(enter)
	enter.pressed.emit()
	var visible := _visible_text(page)
	assert_string_contains(visible, "修为丹")
	assert_string_contains(visible, "灵草")
	assert_false(_has_slug(visible, "pill_cultivate"))
	assert_false(_has_slug(visible, "herb_lingcao"))
	var garden := page.find_child("Enter_garden", true, false)
	assert_null(garden, "炼丹子页不应再显示总览进入按钮")
	page.find_child("BackButton", true, false).pressed.emit()
	var plant := page.find_child("Enter_garden", true, false) as BaseButton
	plant.pressed.emit()
	var plot_plant := page.find_child("Plant_0", true, false) as BaseButton
	plot_plant.pressed.emit()
	var picker := _visible_text(page)
	assert_string_contains(picker, "灵草种子")
	assert_false(_has_slug(picker, "seed_lingcao"))


func test_proto_mock_content_fills_dongfu_display_names() -> void:
	assert_true(ProtoMock.available(), "演示数据集应存在")
	var content := ProtoMock.content()
	var wanted := {
		"seed_lingcao": "灵草种子",
		"seed_qingxin": "清心草种子",
		"herb_lingcao": "灵草",
		"herb_qingxin": "清心草",
		"pill_cultivate": "修为丹",
		"pill_atk_temp": "攻击临时丹",
		"pill_def_temp": "防御临时丹",
		"wood_lingmu": "灵木",
	}
	for slug in wanted.keys():
		var name := ""
		for row in content.get("items", []):
			if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == str(slug):
				name = str((row as Dictionary).get("displayName", ""))
				break
		assert_eq(name, str(wanted[slug]), "content.items[%s].displayName" % str(slug))


func _visible_text(root: Node) -> String:
	var parts: PackedStringArray = []
	_collect_text(root, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is Button:
		parts.append((node as Button).text)
	for child in node.get_children():
		_collect_text(child, parts)


func _has_slug(text: String, slug: String) -> bool:
	return text.contains(slug)
