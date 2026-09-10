class_name GameSettings
extends RefCounted

const POLICY_SKIP := "skip"
const POLICY_DISCARD_LOWEST := "discard_lowest"

var battle_log_enabled: bool = true
var bag_full_policy: String = POLICY_SKIP
var sound_volume: float = 1.0


func to_dictionary() -> Dictionary:
	return {
		"battle_log_enabled": battle_log_enabled,
		"bag_full_policy": bag_full_policy,
		"sound_volume": sound_volume,
	}


static func from_dictionary(data: Dictionary) -> GameSettings:
	var settings := GameSettings.new()
	settings.battle_log_enabled = bool(data.get("battle_log_enabled", true))
	var policy := str(data.get("bag_full_policy", POLICY_SKIP)).strip_edges()
	settings.bag_full_policy = policy if policy == POLICY_DISCARD_LOWEST else POLICY_SKIP
	settings.sound_volume = clampf(float(data.get("sound_volume", 1.0)), 0.0, 1.0)
	return settings
