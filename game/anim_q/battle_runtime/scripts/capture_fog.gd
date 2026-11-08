extends SceneTree
## REAL main.tscn -> existing fog navigation -> TimelineBattlePage.open_session.
## FogBattlePage.open_battle compatibility wrapper is separately exercised by verify_fog.gd.
## Run with --fixed-fps 30: timeline, slot actors and official impact timers share engine time.
func _initialize() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	call_deferred("_capture")

static func capture_session() -> Dictionary:
	return {"combatId":"capture-fog-unified", "source":"fog", "target":{"mapId":"fog_wenxin_valley"},
		"playback":{"player":{"hp":1200,"attack":180,"defense":60,"interval":1.0}, "monster":{"id":"capture_bear","name":"雾境守卫","hp":1800,"attack":90,"defense":40,"interval":1.5}, "timeLimitSeconds":45,"canSkip":true,"speeds":[1,2,3]},
		"battle":{"win":true,"reason":"defeated","durationSeconds":9.6,"log":[
			{"t":1.0,"side":"player","kind":"attack","damage":320,"targetHpAfter":1480,"playerHpAfter":1200,"bossHpAfter":1480},
			{"t":3.0,"side":"player","kind":"skill","name":"苍岚剑气","damage":780,"targetHpAfter":700,"playerHpAfter":1200,"bossHpAfter":700,"statuses":[{"kind":"attack_up","side":"player","expiresAt":5.8}]},
			{"t":5.8,"side":"boss","kind":"attack","damage":180,"targetHpAfter":1020,"playerHpAfter":1020,"bossHpAfter":700},
			{"t":8.0,"side":"player","kind":"attack","damage":700,"targetHpAfter":0,"playerHpAfter":1020,"bossHpAfter":0}]}}

func _capture() -> void:
	var out := ProjectSettings.globalize_path("res://anim_q/battle_runtime/preview")
	var frames := OS.get_environment("FOG_CAPTURE_DIR")
	if frames.is_empty(): frames = "/tmp/fog_unified_frames"
	DirAccess.make_dir_recursive_absolute(frames)
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for _i in 12: await process_frame
	if main._offline_popup != null: main._offline_popup.hide()
	main._popup.hide()
	main._timer.stop()
	main._show_page("fog")
	await process_frame
	main._on_fog_battle(capture_session())
	var page = main._battle_page
	page._set_speed(1)
	var hero = page._slots._actors.player
	var boss = page._slots._actors.boss
	print("FOG_UNIFIED_ARENA ", page._arena.size, " hero=", hero.body_rect(), " boss=", boss.body_rect())
	var captured: Dictionary = {}
	for i in 360:
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		if OS.get_environment("FOG_STILLS_ONLY") != "1":
			var err := image.save_jpg(frames + "/%04d.jpg" % i, 0.94)
			if err != OK:
				push_error("FOG_FRAME_WRITE_FAILED " + str(err))
				quit(1)
				return
		var still := ""
		if i == 45 and hero.action == "idle": still = "idle"
		if hero.action == "attack" and hero.action_time > 0.16 and page.fight.t < 2.0: still = "attack"
		if hero.action == "skill" and hero.fighter.state == "cast" and hero.action_time > 0.15: still = "cast"
		if hero.sword.visible and hero.action_time > hero.skill_delay * 0.8: still = "skill"
		if boss.blast.visible and boss.hit_time > 0.07 and page.fight.t > 3.0: still = "impact"
		if hero.blast.visible and hero.hit_time > 0.07: still = "hit"
		if hero.fighter.state == "idle" and hero.hit_time < 0.0 and page.fight.t > 6.5 and page.fight.t < 7.5: still = "recover"
		if hero.action == "win" and hero.action_time > 0.30: still = "finished"
		if not still.is_empty() and not captured.has(still):
			image.save_png(out + "/fog_" + still + ".png")
			captured[still] = i
			print("FOG_STILL ", still, " frame=", i, " t=", page.fight.t)
		if i % 60 == 0: print("FOG_CAPTURE_FRAME ", i)
	var report := {"scene":"res://scenes/main.tscn", "route":"fog navigation -> _on_fog_battle -> TimelineBattlePage.open_session", "wrapper_test":"verify_fog.gd: FogBattlePage.open_battle -> open_session", "width":1080,"height":2340,"fps":30,"frames":360,"stills":captured,"authoritative_events":page.fight.log.size(),"slot_actors":page._slots._actors.size(),"settled":page.phase == page.Phase.RESULT,"arena_size":str(page._arena.size)}
	var file := FileAccess.open(out + "/fog_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("FOG_CAPTURE_DONE ", JSON.stringify(report))
	var success: bool = captured.size() == 8 and page.fight.log.size() == 4
	main.queue_free()
	for _i in 4: await process_frame
	quit(0 if success else 1)
