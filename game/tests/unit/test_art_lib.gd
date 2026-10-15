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
