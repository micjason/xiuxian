extends GutTest
## 交付的美术必须和清单一致：九宫格贴图宽高 > 2 × 边距（清单规则），ArtLib 取图的名字都能找到文件。


func test_nine_slice_textures_are_larger_than_twice_their_margins() -> void:
	for key in ArtLib.NINE:
		if not ArtLib.has_ui(key):
			continue  # 没有这张图的由代码占位，不在这里报错（第 3 轮之后 NINE 里的都已交付，页面标题牌 page_title_plate 是仓库自带的）
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
		if tex.resource_path.contains("/art/q/"):
			var want := {"cultivate": Vector2i(1080, 1368), "adventure": Vector2i(1080, 960), "cave": Vector2i(1080, 2340)}
			var q_name := str(ArtLib.Q_BG_ALIAS.get(name, name))
			assert_eq(Vector2i(tex.get_width(), tex.get_height()), want.get(q_name, Vector2i(1080, tex.get_height())), "%s → Q 版 %s" % [name, q_name])
		else:
			assert_eq(Vector2i(tex.get_width(), tex.get_height()), Vector2i(1080, 2400), name)


func test_ultimate_button_art_is_present() -> void:
	for name in ["ult_btn_ready", "ult_btn_cooldown", "ult_btn_disabled"]:
		assert_true(ArtLib.has_ui(name), name)
		assert_eq(ArtLib.ui(name).get_width(), 220, name)


func test_round3_art_has_the_checklist_sizes_and_is_wired() -> void:
	var sizes := {
		"splash_1080x1920": Vector2i(1080, 1920),
		"popup_breakthrough_header": Vector2i(960, 420),
		"panel_popup_scroll": Vector2i(984, 1350),
		"ribbon_title": Vector2i(256, 96),
		"bar_frame": Vector2i(192, 56),
		"ult_btn_cooldown": Vector2i(220, 220),
		"formation": Vector2i(768, 768),
		"logo_title": Vector2i(900, 420),
	}
	for name in sizes:
		assert_true(ArtLib.has_ui(name), name)
		var tex := ArtLib.ui(name)
		assert_eq(Vector2i(tex.get_width(), tex.get_height()), sizes[name], name)
	assert_true(ArtLib.has_icon("ui_hourglass"), "沙漏图标")
	assert_true(ArtLib.has_ui("page_title_plate"), "页面标题牌")


func test_splash_and_all_four_launcher_icons_are_configured() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/boot_splash/image")), "res://assets/art/ui/splash_1080x1920.png")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var section := "preset.0.options"
	for key in ["launcher_icons/main_192x192", "launcher_icons/adaptive_foreground_432x432", "launcher_icons/adaptive_background_432x432", "launcher_icons/adaptive_monochrome_432x432"]:
		var path := str(cfg.get_value(section, key, ""))
		assert_ne(path, "", key)
		assert_true(ResourceLoader.exists(path), "%s → %s" % [key, path])
	assert_string_contains(str(cfg.get_value("preset.0", "exclude_filter", "")), "scripts/dev/**", "开发场景不进 APK")
	assert_string_contains(str(cfg.get_value("preset.0", "exclude_filter", "")), "scenes/dev/**")
