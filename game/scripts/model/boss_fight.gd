class_name BossFight
extends RefCounted
## 首领战预演（客户端画面）。公式、事件顺序和服务端 simulateBossFight 逐项一致：
## - 普攻伤害 = 攻击² / (攻击 + k × 防御)，按双方出手间隔轮流出手；
## - 大招 = 额外一次伤害 floor(普攻伤害 × 倍率)，第一次冷却 first_cooldown，之后冷却从“释放那一刻”算起；
## - 冷却好以后的 window 秒内，玩家点击就在点击那一刻释放（手动），没点就在窗口结束时自动释放；
## - 冷却没好时点击无效；同一时刻先结算玩家普攻、再大招、最后首领出手；超过时限算超时。
## 画面只是预演：真正的胜负、掉落以服务器重算为准。点击的时间（从开战算起的秒数）记在 taps 里，
## 战斗结束后随挑战请求以 ultTaps 上报。
## 数值全部用服务器给的小数，不在这里取整；显示时再取整。

const MAX_TAPS := 50

var player := {"attack": 0.0, "defense": 0.0, "hp": 1.0, "interval": 1.0}
var boss := {"attack": 0.0, "defense": 0.0, "hp": 1.0, "interval": 1.0}
var defense_constant := 1.0
var time_limit := 45.0
## 空字典 = 没有大招。键：multBp、cooldownSeconds、firstCooldownSeconds、autoCastWindowSeconds。
var ult := {}

var t := 0.0
var player_max_hp := 1.0
var player_hp := 1.0
var boss_max_hp := 1.0
var boss_hp := 1.0
var finished := false
var win := false
var reason := ""
var duration := 0.0
## 已被接受的大招点击时间（秒）。
var taps: Array[float] = []
## 每次释放：{t, manual, damage}。
var casts: Array[Dictionary] = []
## 新发生的事件（取走后清空）：{t, side: player|boss, damage, kind?: "ult"}。
var events: Array[Dictionary] = []
## 全部事件，给战报用。
var log: Array[Dictionary] = []

var _player_next := 0.0
var _boss_next := 0.0
var _ult_ready := INF
var _ult_next := INF
var _ult_last_cast := 0.0


static func hit_damage(attack: float, defense: float, constant: float) -> float:
	if attack <= 0.0:
		return 0.0
	return (attack * attack) / (attack + constant * maxf(defense, 0.0))


## 用 /me/state、/content/current 和关卡里的首领开一场预演。stage 没有首领时返回 null。
static func from_state(state: Dictionary, content: Dictionary, stage: Dictionary) -> BossFight:
	var bosses: Array = stage.get("bosses", [])
	if bosses.is_empty() or typeof(bosses[0]) != TYPE_DICTIONARY:
		return null
	var combat: Dictionary = {}
	var globals: Variant = content.get("globals", {})
	if typeof(globals) == TYPE_DICTIONARY and typeof((globals as Dictionary).get("combat", null)) == TYPE_DICTIONARY:
		combat = (globals as Dictionary).get("combat", {})
	var fight := BossFight.new()
	fight.setup(
		{"attack": float(state.get("attack", 0)), "defense": float(state.get("defense", 0)), "hp": float(state.get("hp", 1)), "interval": float(state.get("interval", 1))},
		bosses[0] as Dictionary,
		float(combat.get("defenseConstant", 1.0)),
		float(combat.get("timeLimitSeconds", 45.0)),
		state.get("ult", {}) if typeof(state.get("ult", null)) == TYPE_DICTIONARY else {},
	)
	return fight


func setup(player_side: Dictionary, boss_side: Dictionary, constant: float, limit: float, ult_config: Dictionary) -> void:
	player = {"attack": float(player_side.get("attack", 0)), "defense": float(player_side.get("defense", 0)), "hp": float(player_side.get("hp", 1)), "interval": maxf(float(player_side.get("interval", 1)), 0.05)}
	boss = {"attack": float(boss_side.get("attack", 0)), "defense": float(boss_side.get("defense", 0)), "hp": float(boss_side.get("hp", 1)), "interval": maxf(float(boss_side.get("interval", 1)), 0.05)}
	defense_constant = constant
	time_limit = limit
	ult = ult_config if float(ult_config.get("multBp", 0)) > 0.0 else {}
	player_max_hp = float(player.hp)
	player_hp = player_max_hp
	boss_max_hp = float(boss.hp)
	boss_hp = boss_max_hp
	_player_next = float(player.interval)
	_boss_next = float(boss.interval)
	if has_ult():
		_ult_ready = float(ult.get("firstCooldownSeconds", 8.0))
		_ult_next = _ult_ready + auto_window()


func has_ult() -> bool:
	return not ult.is_empty()


func auto_window() -> float:
	return float(ult.get("autoCastWindowSeconds", 2.0))


func player_damage() -> float:
	return hit_damage(float(player.attack), float(boss.defense), defense_constant)


func boss_damage() -> float:
	return hit_damage(float(boss.attack), float(player.defense), defense_constant)


func ult_damage() -> float:
	return floorf(player_damage() * float(ult.get("multBp", 0)) / 10000.0)


## 向前推进到开战后 target 秒，按事件先后结算。
func advance_to(target: float) -> void:
	if finished:
		return
	while not finished:
		var next := minf(minf(_player_next, _boss_next), _ult_next)
		if next > time_limit:
			if target >= time_limit:
				_finish(false, "timeout", time_limit)
			break
		if next > target:
			break
		_step(next)
	if not finished:
		t = maxf(t, target)


func _step(at: float) -> void:
	t = at
	if _player_next == at:
		var dmg := player_damage()
		boss_hp = maxf(0.0, boss_hp - dmg)
		_push({"t": at, "side": "player", "damage": dmg, "targetHpAfter": boss_hp})
		_player_next += float(player.interval)
		if boss_hp <= 0.0:
			_finish(true, "win", at)
			return
	if _ult_next == at:
		_cast(at, false)
		if finished:
			return
	if _boss_next == at and boss_hp > 0.0:
		var hurt := boss_damage()
		player_hp = maxf(0.0, player_hp - hurt)
		_push({"t": at, "side": "boss", "damage": hurt, "targetHpAfter": player_hp})
		_boss_next += float(boss.interval)
		if player_hp <= 0.0:
			_finish(false, "defeated", at)


func _cast(at: float, manual: bool) -> void:
	var dmg := ult_damage()
	boss_hp = maxf(0.0, boss_hp - dmg)
	_push({"t": at, "side": "player", "damage": dmg, "targetHpAfter": boss_hp, "kind": "ult"})
	casts.append({"t": at, "manual": manual, "damage": dmg})
	_ult_last_cast = at
	_ult_ready = at + float(ult.get("cooldownSeconds", 0))
	_ult_next = _ult_ready + auto_window()
	if boss_hp <= 0.0:
		_finish(true, "win", at)


func _push(event: Dictionary) -> void:
	events.append(event)
	log.append(event)


func _finish(won: bool, why: String, at: float) -> void:
	finished = true
	win = won
	reason = why
	duration = at
	t = at


## 玩家点大招。冷却没好、已结束、没有大招时忽略并返回 false；成功时记下点击时间。
func tap() -> bool:
	if finished or not has_ult() or taps.size() >= MAX_TAPS:
		return false
	# 留 2e-5 秒余量并按 1e-5 秒向上取整：上报的时间一定落在服务器的“冷却好 ~ 窗口结束”之间，不会被浮点误差判成冷却前。
	if t < _ult_ready + 0.00002 or t > _ult_next - 0.00002:
		return false
	var at := ceilf(t * 100000.0) / 100000.0
	taps.append(at)
	_cast(at, true)
	return true


func ult_ready() -> bool:
	return has_ult() and not finished and t >= _ult_ready


## 冷却进度 0..1（1 = 冷却完毕）。
func ult_progress() -> float:
	if not has_ult():
		return 0.0
	if t >= _ult_ready:
		return 1.0
	var total := maxf(_ult_ready - _ult_last_cast, 0.001)
	return clampf((t - _ult_last_cast) / total, 0.0, 1.0)


## 还要多久冷却好（已好 = 0）。
func ult_cooldown_left() -> float:
	return maxf(0.0, _ult_ready - t) if has_ult() else 0.0


## 冷却好以后距离自动释放还有多久（没好 = -1）。
func ult_auto_left() -> float:
	if not ult_ready():
		return -1.0
	return maxf(0.0, _ult_next - t)


func take_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


## 上报给服务器的点击时间。
func upload_taps() -> Array:
	var out: Array = []
	for value in taps:
		out.append(value)
	return out
