extends GutTest
## 美术资源入口：每个被代码引用的框体、图标、背景、字体都在，授权文档覆盖到每个文件。

const SLOT_IDS := ["weapon", "helmet", "clothes", "gloves", "shoes", "accessory", "artifact", "pet"]
const BG_NAMES := ["home", "login", "bag", "character", "skill", "stage_1", "stage_2", "stage_3", "stage_4", "stage_5", "stage_6"]


func test_every_nine_slice_texture_exists_and_margins_fit() -> void:
	for key in ArtLib.NINE:
		var tex := ArtLib.ui(key)
		assert_not_null(tex, "缺少框体贴图 %s" % key)
		if tex == null:
			continue
		var margin: Array = ArtLib.NINE[key]
		assert_lt(int(margin[0]) * 2, tex.get_width(), "%s 左右边距超过贴图宽度" % key)
		assert_lt(int(margin[1]) * 2, tex.get_height(), "%s 上下边距超过贴图高度" % key)
		var box := ArtLib.nine(key)
		assert_true(box is StyleBoxTexture)
		assert_eq(box.texture, tex)
		assert_eq(box.texture_margin_left, margin[0])
		assert_eq(box.texture_margin_top, margin[1])


func test_icons_for_every_slot_category_and_boss_pool_exist() -> void:
	for slot_id in SLOT_IDS:
		assert_true(ArtLib.has_icon(ArtLib.slot_icon_name(slot_id)), "部位 %s 缺图标" % slot_id)
	for category in ["equip", "material", "pill", "other"]:
		assert_true(ArtLib.has_icon(ArtLib.category_icon_name(category)), category)
	assert_true(ArtLib.has_icon(ArtLib.category_icon_name("other", "skill_book")))
	for name in ["res_cultivation", "res_enhance", "tab_cultivate", "tab_adventure", "tab_character", "tab_bag", "tab_skill"]:
		assert_true(ArtLib.has_icon(name), name)
	assert_eq(ArtLib.boss_icon_name("枯木妖"), ArtLib.boss_icon_name("枯木妖"), "同一个首领永远是同一张头像")
	assert_true(ArtLib.has_icon(ArtLib.boss_icon_name("寒潭蛟")))


func test_backgrounds_exist_and_are_portrait() -> void:
	for name in BG_NAMES:
		var tex := ArtLib.bg(name)
		assert_not_null(tex, "缺少背景 %s" % name)
		if tex != null:
			assert_gt(tex.get_height(), tex.get_width(), "%s 应是竖屏图" % name)


func test_fonts_load_and_cover_cjk_with_a_system_fallback() -> void:
	for font in [ArtLib.body_font(), ArtLib.title_font(), ArtLib.bold_font()]:
		assert_not_null(font)
		assert_gt((font as Font).get_string_size("修炼历练行囊功法", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x, 100.0)
	var title := ArtLib.title_font() as FontVariation
	assert_eq(title.base_font.resource_path, ArtLib.FONT_TITLE)
	assert_eq(title.fallbacks.size(), 1, "包内字体没有的字交给系统字体")


func test_missing_art_returns_null_without_substituting() -> void:
	assert_null(ArtLib.icon("definitely_not_an_icon"))
	assert_false(ArtLib.has_icon("definitely_not_an_icon"))


func test_every_shipped_art_file_is_listed_in_the_license_file() -> void:
	var text := FileAccess.get_file_as_string("res://assets/ASSETS_LICENSES.md")
	assert_gt(text.length(), 500)
	for dir in ["res://assets/art/icons", "res://assets/art/bg", "res://assets/fonts"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".import") or file.ends_with(".uid") or file.ends_with(".txt"):
				continue
			var stem := file.get_basename().get_basename() if file.ends_with(".woff2") else file.get_basename()
			var covered := text.contains(stem) or text.contains(dir.get_file() + "/")
			assert_true(covered, "%s 没有写进 ASSETS_LICENSES.md" % file)


func test_credits_file_has_groups_with_licenses() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/credits.json"))
	assert_true(parsed is Dictionary)
	var groups: Array = (parsed as Dictionary).get("groups", [])
	assert_gte(groups.size(), 4)
	for group in groups:
		assert_ne(str(group.get("title", "")), "")
		assert_gt((group.get("lines", []) as Array).size(), 0, "每组都要有署名文字")


## ---- 物品图标回退 ----

func _gear(slug: String, slot_id: String, order: int = 1) -> Dictionary:
	return {"slug": slug, "slot_id": slot_id, "kind": "equipment", "category": "equip", "required_realm_order": order}


func _only(existing: Array) -> Callable:
	return func(path: String) -> bool: return existing.has(path)


func test_realm_id_comes_from_slug_then_from_realm_order() -> void:
	assert_eq(ArtLib.item_realm_id(_gear("gear_foundation_weapon_blue", "weapon")), "foundation")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 1)), "qi")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 3)), "qi")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 4)), "foundation")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 7)), "core")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 0)), "", "不知道境界就不猜")
	assert_eq(ArtLib.item_realm_id(_gear("sword_2", "weapon", 99)), "")
	assert_eq(ArtLib.item_realm_id(_gear("gear_bogus_weapon_white", "weapon", 4)), "foundation", "slug 里的境界不认识时看境界序号")


func test_gear_candidates_follow_slug_then_realm_slot_then_slot() -> void:
	assert_eq(ArtLib.item_icon_candidates(_gear("gear_qi_weapon_white", "weapon")), ["gear_qi_weapon_white", "gear_qi_weapon", "gear_weapon"])
	assert_eq(ArtLib.item_icon_candidates(_gear("sword_0", "weapon", 0)), ["sword_0", "gear_weapon"], "没有境界信息就跳过境界层")


func test_gear_lookup_walks_the_chain_until_a_file_exists() -> void:
	var item := _gear("gear_core_shoes_purple", "shoes", 7)
	var base := ArtLib.ITEM_DIR
	assert_eq(ArtLib.item_icon(item, _only([base + "gear_core_shoes_purple.png", base + "gear_core_shoes.png", base + "gear_shoes.png"]))["source"], "gear_core_shoes_purple")
	assert_eq(ArtLib.item_icon(item, _only([base + "gear_core_shoes.png", base + "gear_shoes.png"]))["source"], "gear_core_shoes")
	assert_eq(ArtLib.item_icon(item, _only([base + "gear_shoes.png", base + "gear_qi_shoes.png"]))["source"], "gear_shoes", "别的境界的图不能拿来顶替")
	var hit := ArtLib.item_icon(item, _only([base + "gear_core_shoes.png"]))
	assert_false(bool(hit["tint"]), "彩色回退图不染色")
	var none := ArtLib.item_icon(item, _only([]))
	assert_eq(none["source"], "placeholder")
	assert_true(bool(none["tint"]), "占位剪影按品质染色")
	assert_not_null(none["texture"], "占位剪影是现成的 icons/slot_shoes")


func test_gear_never_falls_back_to_another_slot() -> void:
	var item := _gear("gear_qi_helmet_white", "helmet")
	var base := ArtLib.ITEM_DIR
	assert_eq(ArtLib.item_icon(item, _only([base + "gear_qi_weapon.png", base + "gear_weapon.png"]))["source"], "placeholder")


func _plain(slug: String, kind: String) -> Dictionary:
	return {"slug": slug, "slot_id": "", "kind": kind, "category": "other", "required_realm_order": 1}


func test_non_gear_categories_are_derived_from_kind_and_slug() -> void:
	var cases := {
		"enh_stone_low": ["material", "mat_stone"], "enh_stone_high": ["material", "mat_stone"],
		"mat_spirit_grass": ["material", "mat_herb"], "mat_beast_bone": ["material", "mat_bone"], "mat_unknown": ["material", "mat_other"],
		"book_skill_qi_atk_yellow": ["skill_book", "book_atk"], "book_skill_core_def_heaven": ["skill_book", "book_def"],
		"book_skill_foundation_hp_earth": ["skill_book", "book_hp"], "book_tuna": ["skill_book", "book_other"],
		"pill_qi_0": ["pill", "pill_qi"], "pill_body_0": ["pill", "pill_body"], "pill_x": ["pill", "pill_other"],
	}
	for slug in cases:
		var item := _plain(slug, cases[slug][0])
		assert_eq(ArtLib.item_icon_candidates(item), [slug, cases[slug][1]], slug)
	assert_eq(ArtLib.item_kind_fallback(_gear("gear_qi_weapon_white", "weapon")), "", "装备没有类别回退")
	assert_eq(ArtLib.item_kind_fallback(_plain("x", "unknown_kind")), "")


func test_non_gear_never_uses_gear_files_and_ends_in_placeholder() -> void:
	var item := _plain("enh_stone_mid", "material")
	var base := ArtLib.ITEM_DIR
	assert_eq(ArtLib.item_icon(item, _only([base + "gear_weapon.png", base + "gear_qi_weapon.png"]))["source"], "placeholder")
	assert_eq(ArtLib.item_icon(item, _only([base + "mat_stone.png"]))["source"], "mat_stone")
	assert_eq(ArtLib.item_icon(item, _only([base + "mat_stone.png", base + "enh_stone_mid.png"]))["source"], "enh_stone_mid", "自己的图优先")


func test_item_without_slug_still_resolves() -> void:
	var result := ArtLib.item_icon({"slot_id": "weapon", "kind": "equipment", "category": "equip"}, _only([]))
	assert_eq(result["source"], "placeholder")
	assert_eq(ArtLib.item_icon_candidates({}), [] as Array[String])


func test_fallback_filenames_match_the_artist_spec() -> void:
	var names := ArtLib.fallback_filenames()
	assert_eq(names.size(), 35, "18 境界×部位 + 6 部位 + 11 非装备")
	assert_eq(names.size(), _unique_count(names), "文件名不能重复")
	assert_true(names.has("gear_qi_weapon") and names.has("gear_core_accessory") and names.has("gear_shoes"))
	assert_false(names.has("gear_infant_weapon"), "元婴、化神原型阶段不画")
	for name in ["mat_stone", "mat_herb", "mat_bone", "mat_other", "book_atk", "book_def", "book_hp", "book_other", "pill_qi", "pill_body", "pill_other"]:
		assert_true(names.has(name), name)
	for slot in ArtLib.GEAR_SLOT_IDS:
		assert_not_null(SlotConfig.find(slot).get("id"), "部位 %s 必须在 SlotConfig 里" % slot)
		assert_true(SlotConfig.is_equippable(slot))


func _unique_count(values: Array) -> int:
	var seen := {}
	for value in values:
		seen[value] = true
	return seen.size()


func test_every_shipped_item_file_uses_a_fallback_name_or_a_slug() -> void:
	var allowed := ArtLib.fallback_filenames()
	assert_true(DirAccess.dir_exists_absolute("res://assets/art/items"), "items 目录必须存在（美术交图的位置）")
	for file in DirAccess.get_files_at("res://assets/art/items"):
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue
		var stem := file.get_basename()
		var looks_like_slug := stem.begins_with("gear_") or stem.begins_with("book_") or stem.begins_with("enh_stone_") or stem.begins_with("pill_") or stem.begins_with("mat_")
		assert_true(allowed.has(stem) or looks_like_slug, "%s 文件名不在回退清单里" % file)


func test_switch_textures_are_requested_by_the_documented_names() -> void:
	assert_eq(ArtLib.SWITCH_ON, "switch_on")
	assert_eq(ArtLib.SWITCH_OFF, "switch_off")
	var on_tex := ArtLib.switch_tex(true)
	if on_tex != null:
		assert_eq(on_tex.get_size(), Vector2(160, 80))
