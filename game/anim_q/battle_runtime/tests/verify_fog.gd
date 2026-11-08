extends SceneTree
class FallbackSpy extends Node2D:
	var event: Dictionary = {}
	func on_event(value: Dictionary) -> void: event = value
var failures: Array[String] = []
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		printerr("FAIL: ", message)
func _run() -> void:
	var page = load("res://scripts/ui/pages/fog_battle_page.gd").new()
	root.add_child(page)
	page.size = Vector2(1032, 1948)
	await process_frame
	await process_frame
	page.open_battle({"win":true, "durationSeconds":12, "player":{"hp":1200}, "monster":{"hp":1800,"name":"雾境守卫"}, "log":[{"t":1.0,"side":"player","kind":"attack","damage":100,"targetHpAfter":1700}]})
	check(page is TimelineBattlePage and page.fight is BattleTimeline, "Fog wrapper retains official authoritative timeline")
	var hero = page._arena.get_node_or_null("UnifiedPlayerActor")
	var boss = page._arena.get_node_or_null("UnifiedBossActor")
	check(hero != null and boss != null, "one persistent unified slot actor per side")
	if hero == null or boss == null:
		page.queue_free()
		quit(1)
		return
	hero.capture_mode = true
	boss.capture_mode = true
	page.set_process(false)
	check(page._slots._actors.size() == 2 and page._slots._instances.is_empty(), "no seven-copy visibility switching")
	check(is_equal_approx(hero.position.y, boss.position.y) and hero.position.x < boss.position.x, "same mid-arena feet line and wide left/right gap")
	check(hero.body_rect().size.y <= 280 and boss.body_rect().size.y <= 300, "fighters fit smaller flex arena")
	check(hero.body_rect().position.y >= 0 and boss.body_rect().end.y < page._arena.size.y, "both bodies lie inside arena")
	check(not page._hero_art.visible and not page._boss_art.visible, "old TextureRect placeholders hidden")
	check(not page._fx.hero_rig.visible and not page._fx.boss.visible and page._fx.visible, "old rig bodies hidden, FX service alive")
	var pose: int = hero.fighter.sprite.frame
	var breath: Vector2 = hero.fighter.sprite.scale
	hero.advance_presentation(0.25)
	boss.advance_presentation(0.25)
	check(hero.fighter.sprite.frame == pose and hero.fighter.sprite.sprite_frames.get_frame_count("idle") == 1, "idle never walks in place")
	check(not breath.is_equal_approx(hero.fighter.sprite.scale), "idle breath lives in code")
	page._slots.play_slot("player", "attack", {"side":"player","damage":100})
	hero.advance_presentation(0.1)
	check(hero.fighter.state == "attack" and absf(hero.fighter.displacement.x) > 1, "attack frames and bounded inertial lunge")
	check(boss.fighter.state == "idle", "attack slot itself never invents target hit")
	page._slots.play_slot("boss", "hit", {"side":"player","damage":100})
	check(boss.fighter.state == "hit" and boss.blast.visible, "only explicit incoming hit plays recoil and blast")
	var impact_position: Vector2 = boss.fighter.displacement
	boss.advance_presentation(0.03)
	check(boss.fighter.displacement == impact_position, "impact pause before acceleration")
	boss.advance_presentation(0.8)
	check(boss.fighter.state == "idle" and not boss.blast.visible, "hit self-recovers to stance")
	page._slots.play_slot("boss", "hit", {"damage":0})
	check(boss.fighter.state == "idle", "zero damage does not react")
	page._slots.play_slot("boss", "hit", {"damage":100,"dodged":true})
	check(boss.fighter.state == "idle", "dodge does not trigger unsolicited hit")
	page._slots.play_slot("player", "skill", {"side":"player","kind":"skill","damage":500})
	check(hero.fighter.state == "cast", "skill starts with cast frames")
	check(is_equal_approx(hero.skill_delay, float(page._fx.skill_impact_delay())), "skill flight uses current official impact timing")
	hero.advance_presentation(hero.skill_delay * 0.5)
	check(hero.fighter.state == "skill", "skill proceeds to attack frames")
	hero.advance_presentation(hero.skill_delay * 0.25)
	check(hero.sword.visible, "separate traveling sword FX")
	hero.advance_presentation(1.0)
	check(hero.fighter.state == "idle" and not hero.sword.visible, "skill ends in breath without timeline idle event")
	page._slots.play_slot("boss", "ult", {"side":"boss","kind":"ult"})
	check(boss.fighter.state == "cast", "boss has readable skill windup")
	boss.advance_presentation(2.0)
	check(boss.fighter.state == "idle", "boss skill also self-recovers")
	page._slots.play_slot("player", "attack", {"side":"player"})
	page._set_speed(2)
	var before: float = hero.action_time
	hero.advance_presentation(0.1)
	check(absf(hero.action_time - before - 0.2) < 0.0001 and boss.playback_speed == 2, "×2 propagates immediately to both persistent actors")
	page._set_speed(3)
	check(hero.playback_speed == 3 and boss.playback_speed == 3, "×3 remains supported")
	page._set_speed(1)
	page._slots.play_slot("player", "win", {"reason":"defeated"})
	check(hero.fighter.state == "victory" and page._fx.is_result_playing(), "result animation keeps original banner/wait contract")
	page._slots.play_slot("boss", "lose")
	check(boss.fighter.state == "down", "boss defeat maps to down pose")
	# Existing FX reset re-shows boss; our presenter must suppress it again before drawing.
	page._fx.reset()
	hero._process(0)
	boss._process(0)
	check(not page._fx.boss.visible and not page._fx.hero_rig.visible, "no duplicate sprites after fallback reset")
	check(page._fx._hero_rect.is_equal_approx(hero.body_rect()) and page._fx._boss_rect.is_equal_approx(boss.body_rect()), "HP/status anchors follow actor feet")
	page._slots.play_slot("player", "idle")
	check(hero.fighter.velocity == Vector2.ZERO and hero.fighter.state == "idle", "new session resets inertia")
	check(page.fight.player_hp == 1200 and page.fight.boss_hp == 1800, "presentation never changes authoritative HP")
	# Official timeline still owns timestamps and logs.
	page.step(0.5)
	check(page.fight.log.is_empty(), "no local sample battle replaces server log")
	page.step(0.6)
	check(page.fight.log.size() == 1 and page.fight.boss_hp == 1700, "server event consumed by BattleTimeline")
	await create_timer(0.3).timeout
	check(page._shown_boss_hp == 1700, "official delayed impact updates HUD")
	page.abort()
	page._slots.play_slot("player", "win")
	page.open_stage({}, {}, {"slug":"preview","displayName":"预览"}, {}, "")
	check(hero.fighter.state == "idle" and boss.fighter.state == "idle", "new stage preview does not retain last result pose")
	var adapter := CombatAnimationSlots.new()
	var spy := FallbackSpy.new()
	root.add_child(spy)
	adapter.host = page._arena
	adapter.fx = spy
	adapter.play_slot("missing-side", "attack", {"side":"boss","damage":7})
	check(spy.event.get("damage") == 7 and spy.event.get("kind") == "attack", "missing unified scene retains existing fallback contract")
	spy.queue_free()
	page.queue_free()
	await process_frame
	if failures.is_empty(): print("FOG_VERIFY_PASS: wrapper/timeline, persistent actors, no duplicates, frames/FX, breath/inertia/recover, anchors, speed and result contract")
	quit(0 if failures.is_empty() else 1)
