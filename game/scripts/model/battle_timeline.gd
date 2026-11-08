class_name BattleTimeline
extends BossFight
## Playback only: never rolls or calculates damage. All HP/status/rage snapshots belong to the server.
var _timeline: Array = []
var _cursor := 0
var _outcome: Dictionary = {}
var rage := 0.0
var rage_max := 100.0
var statuses: Array = []

func load_session(session: Dictionary) -> void:
	_outcome = session.get("battle", {})
	var playback: Dictionary = session.get("playback", {})
	rage_max = maxf(1, float(playback.get("rageMax", 100)))
	setup(playback.get("player", {}), playback.get("monster", {}), 1.0, float(playback.get("timeLimitSeconds", 45)), {})
	_timeline = _outcome.get("log", [])
	_cursor = 0
	duration = float(_outcome.get("durationSeconds", time_limit))
	finished = false
	t = 0.0
	events.clear()
	log.clear()

func advance_to(target: float) -> void:
	if finished:
		return
	t = minf(target, duration)
	while _cursor < _timeline.size():
		var event: Dictionary = _timeline[_cursor]
		if float(event.get("t", 0)) > t:
			break
		if event.has("playerHpAfter"):
			player_hp = float(event.playerHpAfter)
		elif str(event.get("side", "")) == "boss":
			player_hp = float(event.get("targetHpAfter", player_hp))
		if event.has("bossHpAfter"):
			boss_hp = float(event.bossHpAfter)
		elif str(event.get("side", "")) == "player":
			boss_hp = float(event.get("targetHpAfter", boss_hp))
		rage = float(event.get("rageAfter", 0))
		statuses = event.get("statuses", [])
		events.append(event)
		log.append(event)
		_cursor += 1
	if target >= duration and _cursor >= _timeline.size():
		finished = true
		win = bool(_outcome.get("win", false))
		reason = str(_outcome.get("reason", "defeated"))

func has_ult() -> bool:
	return true

func ult_charge() -> float:
	return clampf(rage / rage_max, 0, 1)

func tap() -> bool:
	return false
