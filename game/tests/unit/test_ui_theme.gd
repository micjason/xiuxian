extends GutTest
## 设计令牌与主题的约束测试：对比度、最小字号、触控尺寸、导出主题与代码一致、安全区换算、战报格式。

const MIN_TEXT_CONTRAST := 4.5


func test_text_tokens_are_readable_on_card_surface() -> void:
	var surface := UiTokens.SURFACE_SOLID
	for entry in [
		["TEXT", UiTokens.TEXT],
		["TEXT_MUTED", UiTokens.TEXT_MUTED],
		["GOLD", UiTokens.GOLD],
		["SUCCESS", UiTokens.SUCCESS],
		["WARNING", UiTokens.WARNING],
		["DANGER", UiTokens.DANGER],
		["INFO", UiTokens.INFO],
		["JADE", UiTokens.JADE],
	]:
		var ratio := UiTokens.contrast(entry[1], surface)
		assert_gte(ratio, MIN_TEXT_CONTRAST, "%s 在卡片上对比度 %.2f 低于 4.5" % [entry[0], ratio])


func test_button_text_is_readable_on_its_fill() -> void:
	# Q 版：主按钮底是橙色 PRIMARY_*，按钮上的字是深色 ON_PRIMARY（美术按钮上的白字另带可可描边）
	for fill in [UiTokens.PRIMARY_FILL, UiTokens.PRIMARY_HOVER, UiTokens.PRIMARY_PRESSED]:
		assert_gte(UiTokens.contrast(UiTokens.ON_PRIMARY, fill), MIN_TEXT_CONTRAST)


func test_rarity_and_report_colors_are_readable() -> void:
	for index in UiTokens.RARITY_COLORS.size():
		assert_gte(UiTokens.contrast(UiTokens.RARITY_COLORS[index], UiTokens.SURFACE_SOLID), MIN_TEXT_CONTRAST, "稀有度 %d" % index)
	for color in [
		UiTokens.REPORT_DAMAGE_DEALT,
		UiTokens.REPORT_DAMAGE_TAKEN,
		UiTokens.REPORT_HEAL,
		UiTokens.REPORT_CRIT,
		UiTokens.REPORT_BUFF,
		UiTokens.REPORT_DEBUFF,
		UiTokens.REPORT_SYSTEM,
		UiTokens.REPORT_MISS,
	]:
		assert_gte(UiTokens.contrast(color, UiTokens.SURFACE_INNER), MIN_TEXT_CONTRAST, color.to_html(false))


func test_rarity_has_five_distinct_tiers() -> void:
	# 批次②：白→橙 5 档，红（仙品）已去掉
	assert_eq(UiTokens.RARITY_NAMES.size(), 5)
	assert_eq(UiTokens.RARITY_COLORS.size(), 5)
	assert_eq(UiTokens.RARITY_FILLS.size(), 5)
	for i in UiTokens.RARITY_COLORS.size():
		for j in range(i + 1, UiTokens.RARITY_COLORS.size()):
			assert_ne(UiTokens.RARITY_COLORS[i], UiTokens.RARITY_COLORS[j])


func test_type_scale_and_touch_sizes_keep_the_floor() -> void:
	for size in [UiTokens.FS_HUGE, UiTokens.FS_DISPLAY, UiTokens.FS_VALUE, UiTokens.FS_H1, UiTokens.FS_H2, UiTokens.FS_HERO, UiTokens.FS_BODY_L, UiTokens.FS_BODY, UiTokens.FS_CAPTION, UiTokens.FS_MICRO]:
		assert_gte(size, 32, "字号不得小于 32")
	assert_gte(UiTokens.H_TOUCH, 120)
	assert_gte(UiTokens.H_CTA, UiTokens.H_TOUCH)
	assert_gte(UiTokens.H_TAB, UiTokens.H_TOUCH)


func test_exported_theme_matches_code() -> void:
	var exported: Theme = load(MainTheme.THEME_PATH)
	assert_not_null(exported, "缺少导出的主题，请运行 scripts/dev/export_theme.gd")
	var built := MainTheme.make()
	for variation in [MainTheme.VAR_PRIMARY, MainTheme.VAR_SECONDARY, MainTheme.VAR_TAB, MainTheme.VAR_TAB_ACTIVE, MainTheme.VAR_CHOICE, MainTheme.VAR_CHOICE_SELECTED, MainTheme.VAR_TITLE, MainTheme.VAR_SUBTLE]:
		assert_true(exported.is_type_variation(variation, variation_base(variation)), "%s 变体缺失" % variation)
		assert_eq(exported.get_font_size("font_size", variation), built.get_font_size("font_size", variation), "%s 字号不一致" % variation)
		assert_eq(exported.get_color("font_color", variation), built.get_color("font_color", variation), "%s 字色不一致" % variation)
	# 主按钮现在是九宫格贴图：金色实心底，贴图来自 ArtLib
	var exported_fill := exported.get_stylebox("normal", MainTheme.VAR_PRIMARY) as StyleBoxTexture
	assert_not_null(exported_fill, "主按钮应是 StyleBoxTexture")
	var built_fill := ArtLib.nine("btn_primary_normal") as StyleBoxTexture
	assert_eq(exported_fill.texture, built_fill.texture, "Q 版主按钮切图 btn_orange_124")
	assert_eq(exported_fill.texture_margin_left, built_fill.texture_margin_left)
	var exported_font := exported.get_font("font", MainTheme.VAR_TITLE) as FontVariation
	assert_not_null(exported_font, "标题字体应是随包的毛笔字体")
	assert_eq(exported_font.base_font.resource_path, ArtLib.FONT_TITLE)
	assert_eq((exported.default_font as FontVariation).base_font.resource_path, ArtLib.FONT_BODY)


func variation_base(variation: StringName) -> StringName:
	if str(variation).ends_with("Label"):
		return &"Label"
	return &"Button"


func test_safe_area_is_zero_on_desktop_and_scaled_on_phones() -> void:
	var full := UiSafeArea.compute(Rect2i(0, 0, 1080, 2400), Vector2i(1080, 2400), 1.0)
	assert_eq(full, Vector4.ZERO)
	# 屏幕 1260 像素宽、画布 1080：比例 0.857；顶部刘海 100px，底部手势条 60px
	var notch := UiSafeArea.compute(Rect2i(0, 100, 1260, 2540), Vector2i(1260, 2700), 1080.0 / 1260.0)
	assert_almost_eq(notch.y, 85.7, 0.2)
	assert_almost_eq(notch.w, 51.4, 0.2)
	assert_eq(notch.x, 0.0)


func test_safe_area_ignores_invalid_data_and_caps_extremes() -> void:
	assert_eq(UiSafeArea.compute(Rect2i(0, 0, 0, 0), Vector2i(1080, 1920), 1.0), Vector4.ZERO)
	var huge := UiSafeArea.compute(Rect2i(0, 900, 1080, 100), Vector2i(1080, 1920), 1.0)
	assert_eq(huge.y, UiSafeArea.MAX_INSET)
	assert_eq(huge.w, UiSafeArea.MAX_INSET)


func test_battle_report_lines_carry_symbols_and_escape_markup() -> void:
	var damage := BattleReport.format_line(BattleReport.Kind.DAMAGE_DEALT, "击中 寒潭蛟", 412)
	assert_true(damage.contains("−412"))
	assert_true(damage.contains(UiTokens.REPORT_DAMAGE_DEALT.to_html(false)))
	var crit := BattleReport.format_line(BattleReport.Kind.CRIT, "击中", 1096)
	assert_true(crit.contains("★"))
	assert_true(crit.contains("[b]"))
	assert_true(BattleReport.format_line(BattleReport.Kind.HEAL, "恢复", 320).contains("＋320"))
	var hostile := BattleReport.format_line(BattleReport.Kind.PLAIN, "[url=x]点我[/url]")
	assert_false(hostile.contains("[url"))
	assert_true(BattleReport.format_line(BattleReport.Kind.DAMAGE_DEALT, "x", 123456).contains("12.3万"))
