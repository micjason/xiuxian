extends GutTest
## 交付的美术必须和清单一致：九宫格贴图宽高 > 2 × 边距（清单规则），ArtLib 取图的名字都能找到文件。


func test_nine_slice_textures_are_larger_than_twice_their_margins() -> void:
	for key in ArtLib.NINE:
		if not ArtLib.has_ui(key):
			continue  # 还没交付的（panel_popup_scroll、ribbon_title 等）由代码占位，不在这里报错
		var spec: Array = ArtLib.NINE[key]
		var tex := ArtLib.ui(key)
		assert_not_null(tex, key)
		assert_gt(tex.get_width(), 2 * int(spec[0]), "%s 宽 %d 必须大于 2×左右边距 %d" % [key, tex.get_width(), spec[0]])
		assert_gt(tex.get_height(), 2 * int(spec[1]), "%s 高 %d 必须大于 2×上下边距 %d" % [key, tex.get_height(), spec[1]])


func test_tab_and_slot_icons_exist_for_every_tab_and_gear_slot() -> void:
	for name in ["tab_cultivate", "tab_adventure", "tab_character", "tab_bag", "tab_skill", "tab_cave"]:
		assert_true(ArtLib.has_icon(name), name)
	for slot in ArtLib.GEAR_SLOT_IDS:
		assert_true(ArtLib.has_icon("slot_" + slot), slot)


func test_delivered_item_fallbacks_cover_every_rule_target() -> void:
	for realm in ArtLib.REALM_IDS.slice(0, 3):
		for slot in ArtLib.GEAR_SLOT_IDS:
			assert_true(ResourceLoader.exists("res://assets/art/items/gear_%s_%s.png" % [realm, slot]), "%s/%s" % [realm, slot])
	for slot in ArtLib.GEAR_SLOT_IDS:
		assert_true(ResourceLoader.exists("res://assets/art/items/gear_%s.png" % slot), slot)
	for rule in ArtLib.ITEM_KIND_RULES:
		assert_true(ResourceLoader.exists("res://assets/art/items/%s.png" % rule[2]), str(rule[2]))
	for fallback in ArtLib.ITEM_KIND_OTHER.values():
		assert_true(ResourceLoader.exists("res://assets/art/items/%s.png" % fallback), str(fallback))


func test_backgrounds_are_the_delivered_1080x2400_art() -> void:
	for name in ["home", "character", "bag", "skill", "battle", "breakthrough", "login", "stage_1", "stage_2", "stage_3", "stage_4", "stage_5", "stage_6"]:
		var tex := ArtLib.bg(name)
		assert_not_null(tex, name)
		assert_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(1080, 2400), name)


func test_ultimate_button_art_is_present() -> void:
	for name in ["ult_btn_ready", "ult_btn_cooldown", "ult_btn_disabled"]:
		assert_true(ArtLib.has_ui(name), name)
		assert_eq(ArtLib.ui(name).get_width(), 220, name)
