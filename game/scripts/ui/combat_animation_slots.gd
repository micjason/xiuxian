class_name CombatAnimationSlots
extends RefCounted
## Replaceable art contract: res://anim_q/combat_slots/{player,boss}/{slot}.tscn
## Scenes may implement play_slot(slot, event, speed). No scene participates in combat rules.
const SLOTS := ["idle", "attack", "skill", "ult", "hit", "win", "lose"]
var host: Control
var fx: Node2D
var speed := 1.0
var _instances: Dictionary = {}

func setup(arena: Control, fallback: Node2D) -> void:
	host = arena
	fx = fallback

func play_slot(side: String, slot: String, event: Dictionary = {}) -> void:
	if not SLOTS.has(slot):
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
	# Existing hero/monster rigs + sword/slash/flash are the placeholders.
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
