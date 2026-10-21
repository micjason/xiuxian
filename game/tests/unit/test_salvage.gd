extends GutTest
## 第五批（SPEC_Q §17.2 / 17.3 / 17.5 / 17.9）：分解弹窗选择逻辑、精粹预览、紫/橙二次确认、强化消耗、满包提示。

var _content: Dictionary


func before_each() -> void:
	_content = ProtoMock.content()


func _bag(scene: String = "full") -> BagModel:
	return BagModel.from_state(ProtoMock.state(scene), _content, {})


func _ids_of(model: SalvageModel, rarity: int) -> Array[String]:
	var out: Array[String] = []
	for item in model.items:
		if int(item.rarity) == rarity:
			out.append(str(item.id))
	return out


func test_lists_only_unworn_gear_sorted_by_quality_then_level() -> void:
	var bag := _bag()
	var model := SalvageModel.from_bag(bag)
	assert_gt(model.total(), 0)
	for item in model.items:
		assert_eq(str(item.category), "equip", "只列装备（精粹、突破石不列）")
		assert_false(bool(item.equipped), "已穿戴的不列")
	for i in range(1, model.items.size()):
		var a: Dictionary = model.items[i - 1]
		var b: Dictionary = model.items[i]
		assert_true(int(a.rarity) < int(b.rarity) or (int(a.rarity) == int(b.rarity) and int(a.enhance) <= int(b.enhance)), "品质↑、同品质强化等级↑")


func test_nothing_is_selected_when_opened_and_confirm_is_grey() -> void:
	var model := SalvageModel.from_bag(_bag())
	assert_eq(model.selected_count(), 0, "打开时默认一件都不选")
	assert_eq(model.total_gain(), 0)
	var state := model.confirm_state()
	assert_false(bool(state.enabled))
	assert_eq(str(state.sub), "请先选择装备")


func test_quality_chip_selects_all_then_clears_and_tracks_manual_changes() -> void:
	var model := SalvageModel.from_bag(_bag())
	var whites := _ids_of(model, 0)
	assert_gt(whites.size(), 1)
	model.toggle_quality(0)
	assert_eq(model.selected_of(0), whites.size())
	assert_true(model.chip_on(0))
	model.toggle(whites[0])
	assert_false(model.chip_on(0), "手动取消一件 → 胶囊自动熄灭")
	model.toggle(whites[0])
	assert_true(model.chip_on(0), "手动勾满 → 胶囊自动点亮")
	model.toggle_quality(0)
	assert_eq(model.selected_of(0), 0, "再点一次取消该品质全部")
	assert_false(model.chip_on(4) and model.count_of(4) == 0, "没有该品质时不亮")


func test_preview_uses_server_yields_and_refund_per_level() -> void:
	var model := SalvageModel.from_bag(_bag())
	var expect := 0
	var refund := 0
	for item in model.items:
		model.toggle(str(item.id))
		var base: int = [20, 60, 150, 400, 1000][int(item.rarity)]
		expect += base + int(item.enhance) * 40
		refund += int(item.enhance) * 40
	assert_eq(model.total_gain(), expect, "Σ品质产出 + Σ强化等级×40")
	assert_eq(model.total_refund(), refund)
	assert_gt(refund, 0, "演示满包里有强化过的装备")
	assert_eq(str(model.confirm_state().sub), "分解 %d 件" % model.total())


func test_slot_multiplier_and_override_change_the_preview() -> void:
	var content := _content.duplicate(true)
	var essence: Dictionary = content.globals.enhance.essence
	essence["slotMultBp"] = {"weapon": 15000}
	essence["slotOverrides"] = {"white": {"gloves": 7}}
	var rules := EnhanceModel.from_content(content)
	assert_eq(rules.essence_yield(0, "weapon", 0), 30, "白 20 × 武器 150%")
	assert_eq(rules.essence_yield(0, "gloves", 2), 7 + 80, "单独指定 7 + 2 级返还")
	assert_eq(rules.essence_yield(1, "helmet", 0), 60)


func test_essence_cost_follows_curve_and_per_level_table() -> void:
	var content := _content.duplicate(true)
	var rules := EnhanceModel.from_content(content)
	assert_true(rules.uses_essence())
	var mult := float(((content.globals.enhance.qualities as Dictionary).white as Dictionary).get("costMult", 1))
	assert_eq(rules.cost(0, 0), maxi(1, int(round(40 * mult))))
	(content.globals.enhance.essence as Dictionary)["costTable"] = {"white": [11, null, 33]}
	var table := EnhanceModel.from_content(content)
	assert_eq(table.cost(0, 0), 11)
	assert_eq(table.cost(0, 1), rules.cost(0, 1), "空格按曲线")
	assert_eq(table.cost(0, 2), 33)


func test_purple_or_orange_needs_second_confirm_only_white_green_blue_do_not() -> void:
	var model := SalvageModel.from_bag(_bag())
	model.toggle_quality(0)
	model.toggle_quality(1)
	model.toggle_quality(2)
	assert_false(model.needs_rare_confirm(), "只有白/绿/蓝直接分解")
	model.toggle_quality(3)
	assert_true(model.needs_rare_confirm())
	assert_eq(model.rare_line(), "包含 紫装 ×%d" % model.selected_of(3), "只含紫时只写紫")
	model.toggle_quality(4)
	assert_eq(model.rare_line(), "包含 紫装 ×%d · 橙装 ×%d" % [model.selected_of(3), model.selected_of(4)])
	var preview := model.rare_preview()
	assert_eq((preview.shown as Array).size(), model.rare_items().size())


func test_rare_preview_shows_three_and_more_when_over_four() -> void:
	var model := SalvageModel.new()
	for i in 6:
		model.items.append({"id": "r%d" % i, "rarity": 3 + i % 2, "enhance": i, "category": "equip", "decompose_exp": 400})
	for item in model.items:
		model.toggle(str(item.id))
	var preview := model.rare_preview()
	assert_eq((preview.shown as Array).size(), 3)
	assert_eq(int(preview.more), 3)
	assert_eq(SalvageModel.rare_caption({"rarity": 3, "enhance": 3}), "珍品 +3")
	assert_eq(SalvageModel.rare_caption({"rarity": 4, "enhance": 0}), "绝品")


func test_dialog_confirm_flow_keeps_selection_on_think_again() -> void:
	var dialog := SalvageDialog.new()
	dialog.animate = false
	add_child_autofree(dialog)
	dialog.open(_bag())
	assert_true(dialog.visible)
	assert_true((dialog.find_child("BagFullStrip", true, false) as Control).visible, "满包时显示满包提示条")
	watch_signals(dialog)
	dialog.press_confirm()
	assert_signal_emitted_with_parameters(dialog, "toast_requested", ["请先选择装备", false])
	assert_signal_not_emitted(dialog, "decompose_requested")
	dialog.toggle_quality(0)
	dialog.press_confirm()
	assert_signal_emitted(dialog, "decompose_requested", "只有白：直接分解")
	var whites: Array = get_signal_parameters(dialog, "decompose_requested")[0]
	assert_eq(whites.size(), dialog.model.selected_of(0))
	dialog.toggle_quality(3)
	var before := dialog.model.selected_count()
	dialog.press_confirm()
	assert_true(dialog.is_confirming_rare(), "含紫：先二次确认")
	assert_eq(get_signal_emit_count(dialog, "decompose_requested"), 1)
	dialog.rare_think_again()
	assert_false(dialog.is_confirming_rare())
	assert_eq(dialog.model.selected_count(), before, "再想想：保留勾选")
	dialog.press_confirm()
	dialog.rare_confirm()
	assert_eq(get_signal_emit_count(dialog, "decompose_requested"), 2)
	assert_eq((get_signal_parameters(dialog, "decompose_requested", 1)[0] as Array).size(), before)


func test_dialog_after_decompose_hides_strip_and_stays_open() -> void:
	var state := ProtoMock.state("full")
	var dialog := SalvageDialog.new()
	dialog.animate = false
	add_child_autofree(dialog)
	dialog.open(BagModel.from_state(state, _content, {}))
	dialog.toggle_quality(0)
	var ids := dialog.model.selected_ids()
	var result := ProtoMock.handle("/api/v1/me/items/decompose", {"itemIds": ids}, state, _content)
	assert_eq(int(result.code), 200)
	assert_gt(int(result.gainedEssence), 0)
	dialog.after_decompose(BagModel.from_state(state, _content, {}))
	assert_true(dialog.visible, "分解后弹窗不关")
	assert_false((dialog.find_child("BagFullStrip", true, false) as Control).visible, "不满了满包条消失")
	assert_eq(dialog.model.selected_count(), 0)


func test_stage_page_bag_hint_follows_used_vs_capacity() -> void:
	var full := ProtoMock.state("full")
	assert_true(StagePage.bag_is_full(full, _content))
	assert_false(StagePage.bag_is_full(ProtoMock.state("ready"), _content))
	assert_true(StagePage.bag_is_full({"bagCapacity": 3, "bagUsed": 3}, {}))
	assert_false(StagePage.bag_is_full({"bagCapacity": 3, "bagUsed": 2}, {}))
	var page := StagePage.new()
	add_child_autofree(page)
	page.bind(full, _content, "")
	assert_true(page.bag_hint().visible)
	watch_signals(page)
	page.bag_hint().pressed.emit()
	assert_signal_emitted(page, "salvage_requested", "点提示条直接打开分解界面")


func test_item_detail_shows_essence_cost_and_short_toast() -> void:
	var bag := _bag("ready")
	var item: Dictionary = {}
	for row in bag.items:
		if str(row.category) == "equip" and BagModel.can_enhance(row):
			item = row
			break
	var view := ItemDetailView.enhance_view(item, 5, true)
	assert_true(bool(view.essence))
	assert_false(bool(view.enough))
	var rich := ItemDetailView.enhance_view(item, 1000000, true)
	assert_true(bool(rich.enough))
