extends GutTest
## 换装战斗贴图能否进 HeroRig，以及路径门闩（不实例化战斗场景）。

const BossBattle := preload("res://anim_q/battle_boss/boss_battle.gd")


func test_player_fight_pose_allows_hero_rig() -> void:
	assert_true(BossBattle.hero_tex_allows_rig("res://assets/art/q/sprites/player_fight.png"))
	assert_true(BossBattle.hero_tex_allows_rig("res://anim_q/battle_hero/art/player_fight.png"))


func test_outfit_preview_allows_hero_rig() -> void:
	assert_true(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/preview_white.png"))
	assert_true(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/preview_orange.png"))
	assert_true(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/preview_blue.png"))


func test_meditate_and_avatar_outfit_do_not_drive_battle_rig() -> void:
	assert_false(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/meditate/meditate_orange.png"))
	assert_false(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/avatar/avatar_orange_round.png"))
	assert_false(BossBattle.hero_tex_allows_rig("res://assets/art/q/icons/avatar_meditate.png"))
	assert_false(BossBattle.hero_tex_allows_rig(""))


func test_appearance_preview_keys_still_resolve() -> void:
	var appearance := {
		"quality": "orange",
		"previewKey": "preview_orange",
		"meditateKey": "meditate_orange",
		"avatarRoundKey": "avatar_orange_round",
	}
	assert_eq(OutfitAppearance.key_of(appearance, "preview"), "preview_orange")
	assert_eq(OutfitAppearance.key_of(appearance, "meditate"), "meditate_orange")
	assert_true(BossBattle.hero_tex_allows_rig("res://assets/art/q/outfit/%s.png" % OutfitAppearance.key_of(appearance, "preview")))
