class_name FogBattlePage
extends TimelineBattlePage
## Compatibility name only. Live map and stage navigation both use the same TimelineBattlePage instance.
signal finished(result: Dictionary)

func open_battle(result: Dictionary) -> void:
	var session := result if result.has("playback") else {"combatId": "legacy-capture", "source": "fog", "target": {}, "battle": result, "playback": {"player": result.get("player", {}), "monster": result.get("monster", {}), "timeLimitSeconds": result.get("durationSeconds", 45), "canSkip": false, "speeds": [1,2,3]}}
	open_session(session, {}, {})
