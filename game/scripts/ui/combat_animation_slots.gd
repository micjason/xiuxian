class_name CombatAnimationSlots
extends RefCounted
## Replaceable art contract: res://anim_q/combat_slots/{player,boss}/{slot}.tscn
## actor.tscn is an optional persistent per-side presenter; legacy per-slot scenes still work.
## If neither exists, default actors use supplied sheet poses + an articulated enemy mesh.
## Scenes may implement play_slot(slot, event, speed). No scene participates in combat rules.
const SLOTS := ["idle", "attack", "skill", "ult", "hit", "win", "lose"]
const Cast := preload("res://anim_q/battle_runtime/scripts/combat_cast.gd")
var host: Control
var fx: Node2D
var speed := 1.0:
	set(value):
		speed = value
		for actor: Node in _actors.values():
			if is_instance_valid(actor) and actor.has_method("set_playback_speed"):
				actor.call("set_playback_speed", value)
var _instances: Dictionary = {}
var _actors: Dictionary = {}
var cast: Node2D

func setup(arena: Control, fallback: Node2D) -> void:
	host = arena
	fx = fallback
	for side in ["player", "boss"]:
		_unified_actor(side)
	if _actors.is_empty():
		cast = Cast.new()
		cast.setup(host, fx)

func reset_cast() -> void:
	if not _actors.is_empty():
		for side in _actors:
			var actor: Node = _actors[side]
			if is_instance_valid(actor) and actor.has_method("play_slot"):
				actor.call("play_slot", "idle", {}, speed)
		return
	if cast != null:
		cast.reset_cast()

func _unified_actor(side: String) -> Node:
	if _actors.has(side) and is_instance_valid(_actors[side]):
		return _actors[side]
	var path := "res://anim_q/combat_slots/%s/actor.tscn" % side
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var actor := scene.instantiate()
	if not actor.has_method("play_slot"):
		actor.free()
		return null
	actor.name = "UnifiedPlayerActor" if side == "player" else "UnifiedBossActor"
	host.add_child(actor)
	_actors[side] = actor
	if actor.has_method("setup_presentation"):
		actor.call("setup_presentation", host, fx)
	actor.call("play_slot", "idle", {}, speed)
	return actor

func actor_rect(side: String, default_rect: Rect2) -> Rect2:
	var actor: Node = _actors.get(side)
	if is_instance_valid(actor) and actor.has_method("body_rect"):
		return actor.call("body_rect")
	return default_rect

func play_slot(side: String, slot: String, event: Dictionary = {}) -> void:
	if not SLOTS.has(slot):
		return
	var actor := _unified_actor(side)
	if actor != null:
		actor.call("play_slot", slot, event, speed)
		# Preserve the base page's result-banner/wait contract while the actor owns bodies.
		if side == "player" and slot in ["win", "lose"]:
			fx.call("play_result", slot == "win", str(event.get("reason", "")))
		return
	var key := "%s/%s" % [side, slot]
	var path := "res://anim_q/combat_slots/%s.tscn" % key
	if ResourceLoader.exists(path):
		if not _instances.has(key):
			var scene := load(path) as PackedScene
			if scene != null:
				_instances[key] = scene.instantiate()
				host.add_child(_instances[key])
		for other_key in _instances:
			var other: Node = _instances[other_key]
			if str(other_key).begins_with(side + "/") and other is CanvasItem:
				(other as CanvasItem).visible = str(other_key) == key
		var node: Node = _instances.get(key)
		if node != null and node.has_method("play_slot"):
			node.call("play_slot", slot, event, speed)
			return
	# Default actors use supplied sheet poses + an articulated enemy mesh.
	if cast != null:
		cast.play_slot(side, slot, event, speed)
	# Reuse existing sword/slash/flash only; hidden old rigs never render.
	if slot in ["attack", "skill", "ult"]:
		var shown := event.duplicate()
		shown["kind"] = "ult" if slot in ["skill", "ult"] else "attack"
		fx.call("on_event", shown)
	elif slot == "hit":
		if side == "boss" and fx.get("boss") != null:
			fx.get("boss").call("hit", 1.0)
		elif side == "player" and fx.get("hero_rig") != null:
			fx.get("hero_rig").call("play_hit", false)
	elif slot in ["win", "lose"] and side == "player":
		fx.call("play_result", slot == "win", str(event.get("reason", "")))
