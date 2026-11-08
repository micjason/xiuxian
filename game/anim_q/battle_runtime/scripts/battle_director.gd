extends Node
## Standalone reference helper ONLY; live battles use BattleTimeline + CombatAnimationSlots.
## Never instantiate this director or its sample_result in a production battle page.
signal impact_event(event: Dictionary)
signal phase_changed(phase: String, event: Dictionary)
signal battle_ended
const DURATION := {"cast":0.65, "attack":0.38, "travel":0.55, "impact":0.30, "attack_end":0.16, "recover":0.50, "finish":0.65}
var stage: Node2D
var events: Array[Dictionary] = []
var state := "idle"
var phase_time := 0.0
var clock := 0.0
var index := 0
var active: Dictionary = {}
var running := false
var won := false
var opening := 0.7

func start(payload: Dictionary, visual_stage: Node2D) -> void:
	stage = visual_stage
	events.clear()
	var raw: Variant = payload.get("log", [])
	if raw is Array:
		for event in raw:
			if event is Dictionary and str(event.get("side", "")) in ["player", "boss", "enemy", "monster"]:
				events.append(event.duplicate(true))
	# Stable sorting: server array order remains authoritative for simultaneous hits.
	for i in range(1, events.size()):
		var event := events[i]
		var j := i - 1
		while j >= 0 and float(events[j].get("t", 0)) > float(event.get("t", 0)):
			events[j + 1] = events[j]
			j -= 1
		events[j + 1] = event
	index = 0
	clock = 0.0
	active = {}
	won = bool(payload.get("win", false))
	running = true
	stage.clear_effects()
	stage.hero.reset_fighter()
	stage.monster.reset_fighter()
	_enter("idle")

func advance(delta: float) -> void:
	# Fixed substeps make capture, ×2, and low FPS use exactly the same director.
	var left := maxf(delta, 0.0)
	while left > 0.000001:
		var step := minf(left, 1.0 / 120.0)
		_tick(step)
		left -= step

func _tick(delta: float) -> void:
	stage.advance(delta)
	if not running: return
	clock += delta
	phase_time += delta
	if state == "idle":
		if index >= events.size():
			_enter("finish")
		elif clock >= maxf(opening, float(events[index].get("t", 0))):
			active = events[index]
			index += 1
			_enter("cast" if str(active.get("kind", "")) in ["ult", "skill"] else "attack")
		return
	var duration := float(DURATION.get(state, 0.5))
	var player := str(active.get("side", "player")) == "player"
	if state == "travel": stage.travel(player, minf(phase_time / duration, 0.999))
	if state == "impact" and float(active.get("damage", 0)) > 0: stage.impact(player, minf(phase_time / duration, 0.999))
	if phase_time + 0.00001 < duration: return
	match state:
		"cast": _enter("attack")
		"attack": _enter("travel")
		"travel": _enter("impact")
		"impact": _enter("attack_end")
		"attack_end": _enter("recover")
		"recover": _enter("idle")
		"finish":
			running = false
			state = "finished"
			battle_ended.emit()

func _enter(next: String) -> void:
	state = next
	phase_time = 0.0
	var player := str(active.get("side", "player")) == "player"
	var attacker: Node2D = stage.hero if player else stage.monster
	var target: Node2D = stage.monster if player else stage.hero
	match state:
		"idle", "recover":
			stage.clear_effects()
			stage.hero.command("idle")
			stage.monster.command("idle")
		"cast": attacker.command("cast")
		"attack": attacker.command("skill" if str(active.get("kind", "")) in ["ult", "skill"] else "attack")
		"impact":
			stage.sword.hide()
			if float(active.get("damage", 0)) > 0:
				target.command("hit")
				stage.impact(player, 0.0)
			impact_event.emit(active)
		"attack_end":
			stage.clear_effects()
			attacker.command("recover")
		"finish":
			stage.clear_effects()
			stage.hero.command("victory" if won else "down")
			stage.monster.command("down" if won else "idle")
	phase_changed.emit(state, active)

static func sample_result(source: Dictionary = {}) -> Dictionary:
	var player: Dictionary = source.get("player", {}) if source.get("player", {}) is Dictionary else {}
	var monster: Dictionary = source.get("monster", {}) if source.get("monster", {}) is Dictionary else {}
	var ph := maxf(1.0, float(player.get("hp", 1200)))
	var mh := maxf(1.0, float(monster.get("hp", 1800)))
	var win := bool(source.get("win", true))
	var final_event := {"t":8.1, "side":"player" if win else "boss", "damage":mh * 700.0 / 1800.0 if win else ph * 0.85, "targetHpAfter":0}
	return {"win":win, "player":{"hp":ph}, "monster":{"name":monster.get("name", "雾境守卫"), "hp":mh}, "gained":[], "log":[
		{"t":0.8, "side":"player", "damage":mh * 320.0 / 1800.0, "targetHpAfter":mh * 1480.0 / 1800.0},
		{"t":3.0, "side":"player", "kind":"ult", "name":"苍岚剑气", "damage":mh * 780.0 / 1800.0, "targetHpAfter":mh * 700.0 / 1800.0},
		{"t":5.8, "side":"boss", "damage":ph * 0.15, "targetHpAfter":ph * 0.85},
		final_event]}
