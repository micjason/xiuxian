extends GutTest
## 技能表现降级和换装整图 key。不播放战斗特效。


func test_fx_keeps_real_type_when_the_resource_exists() -> void:
	var ready: Array = ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]
	assert_eq(SkillFxFallback.resolve_type("ice", ready), "ice")
	assert_eq(SkillFxFallback.resolve_type("gold_light", ready), "gold_light")


func test_fx_falls_back_only_when_the_resource_is_missing() -> void:
	var bases: Array = ["slash", "thunder", "fire", "heal_circle"]
	assert_eq(SkillFxFallback.resolve_type("ice", bases), "thunder")
	assert_eq(SkillFxFallback.resolve_type("wind", bases), "slash")
	assert_eq(SkillFxFallback.resolve_type("poison", bases), "fire")
	assert_eq(SkillFxFallback.resolve_type("gold_light", bases), "slash")
	assert_eq(SkillFxFallback.resolve_type("shield", bases), "heal_circle")
	assert_eq(SkillFxFallback.resolve_type("meteor", bases), "slash")
	assert_eq(SkillFxFallback.resolve_type("gold", ["gold_light"]), "gold_light")


func test_icon_key_matches_fx_type_file_names() -> void:
	assert_eq(SkillFxFallback.icon_key("heal_circle"), "heal_circle")
	assert_eq(SkillFxFallback.icon_key("gold_light"), "gold_light")
	assert_eq(SkillFxFallback.icon_key("gold"), "gold_light")
	assert_eq(SkillFxFallback.icon_key("skill_heal"), "heal_circle")
	assert_eq(SkillFxFallback.icon_key(""), "")


func test_missing_appearance_has_no_texture_key() -> void:
	assert_eq(OutfitAppearance.key_of(null, "preview"), "")
	assert_eq(OutfitAppearance.texture(null, "preview"), null)


func test_appearance_keys_cover_preview_meditate_and_round_avatar() -> void:
	var appearance := {
		"quality": "blue",
		"previewKey": "preview_blue",
		"meditateKey": "meditate_blue",
		"avatarKey": "avatar_blue",
		"avatarRoundKey": "avatar_blue_round",
	}
	assert_eq(OutfitAppearance.key_of(appearance, "preview"), "preview_blue")
	assert_eq(OutfitAppearance.key_of(appearance, "meditate"), "meditate_blue")
	assert_eq(OutfitAppearance.key_of(appearance, "avatar_round"), "avatar_blue_round")
	assert_true(FileAccess.file_exists("res://assets/art/q/outfit/preview_blue.png"))
	assert_true(FileAccess.file_exists("res://assets/art/q/outfit/meditate/meditate_orange.png"))
	assert_true(FileAccess.file_exists("res://assets/art/q/outfit/avatar/avatar_green_round.png"))
	assert_true(FileAccess.file_exists("res://assets/art/q/icons/gold_light.png"))
	assert_true(FileAccess.file_exists("res://assets/art/q/icons/heal_circle.png"))
