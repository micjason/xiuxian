class_name StageLayer
extends RefCounted

const OUTER := 0
const INNER := 1
const BOSS := 2
const INNER_KILLS := 80
const BOSS_KILLS := 120

const DISPLAY := {
	OUTER: "外围",
	INNER: "深处",
	BOSS: "头目",
}


static func display_name(layer: int) -> String:
	return str(DISPLAY.get(layer, "外围"))


static func monster_scale(layer: int) -> float:
	match layer:
		INNER:
			return 1.35
		BOSS:
			return 1.6
	return 1.0


static func loot_scale(layer: int) -> float:
	return 1.0 + 0.25 * float(maxi(layer, 0))
