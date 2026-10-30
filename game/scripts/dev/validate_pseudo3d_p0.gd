extends SceneTree

func _initialize() -> void:
	var ok := true
	for p in [
		"res://anim_q/battle_boss/boss_battle.gd",
		"res://anim_q/battle_hero/hero_battle.gd",
		"res://anim_q/battle_idle/monster_rig.gd",
		"res://anim_q/skill_fx/slash_fx.gd",
		"res://anim_q/battle_boss/boss_battle.tscn",
		"res://anim_q/battle_hero/hero_battle.tscn",
		"res://anim_q/battle_idle/monster_rig.tscn",
		"res://anim_q/skill_fx/slash_fx.tscn",
		"res://anim_q/battle_boss/fx/fx_contact_shadow.png",
		"res://anim_q/battle_boss/fx/fx_shockwave.png",
		"res://anim_q/battle_boss/fx/fx_dust_puff.png",
		"res://anim_q/battle_hero/art/fx_contact_shadow.png",
		"res://anim_q/battle_idle/fx/fx_contact_shadow.png",
	]:
		var r = ResourceLoader.load(p)
		print("LOAD ", p, " => ", r)
		if r == null:
			ok = false
	if not ok:
		quit(1)
		return
	call_deferred("_run_checks")

func _run_checks() -> void:
	var scn: PackedScene = load("res://anim_q/battle_boss/boss_battle.tscn")
	var n: Node2D = scn.instantiate()
	root.add_child(n)
	# wait one frame for @onready
	await process_frame
	await process_frame
	print("shake_light=", n.get("shake_light"), " shake_strong=", n.get("shake_strong"))
	print("has _kick_feel=", n.has_method("_kick_feel"), " has _play_land_fx=", n.has_method("_play_land_fx"))
	n.call("_kick_feel", 4.0, 0.12, 1, 1.02, 0.1)
	print("hitstop=", n.get("_hitstop"), " punch=", n.get("_punch_peak"))
	n.call("_play_land_fx", Vector2(100, 200))
	var shock = n.get("_shock")
	print("shock=", shock, " vis=", shock.visible if shock else false)
	var behind = n.get("_ult_behind")
	var flags = n.get("_ult_is_behind")
	var bc := 0
	if flags != null:
		for f in flags:
			if bool(f):
				bc += 1
	print("ult_behind=", behind, " behind_swords=", bc)
	var slash_scn: PackedScene = load("res://anim_q/skill_fx/slash_fx.tscn")
	var slash = slash_scn.instantiate()
	root.add_child(slash)
	await process_frame
	print("slash z Arc2=", slash.get_node("Root/Arc2").z_index, " Arc=", slash.get_node("Root/Arc").z_index)
	# hero contact shadow texture path
	var hero_scn: PackedScene = load("res://anim_q/battle_hero/hero_battle.tscn")
	var hero = hero_scn.instantiate()
	root.add_child(hero)
	await process_frame
	var sh: Sprite2D = hero.get_node("Shadow")
	print("hero_shadow_tex=", sh.texture.resource_path if sh.texture else "null")
	print("P0_VALIDATE OK")
	quit(0)
