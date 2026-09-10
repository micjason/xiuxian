class_name LootRng
extends RefCounted

const MOD := 2147483647


static func next_seed(seed: int) -> int:
	var current := seed if seed > 0 else 1
	return (current * 1103515245 + 12345) & MOD


static func roll(seed: int) -> Dictionary:
	var next := next_seed(seed)
	return {
		"seed": next,
		"value": float(next) / float(MOD),
	}
