class_name TimelineBattlePage
extends BattlePage
## Shared stage/fog runtime; layout is inherited from the UI-owned BattlePage.
## Server journal is persisted before any attack is played. No local simulation is used in live combat.
signal start_requested(stage: String)
signal settle_requested(combat_id: String, mode: String)
var combat_id := ""
var source := "stage"
var _session_data: Dictionary = {}
var _can_skip := false
var _skip: Button
var _statuses: Label
var _enemy_status: Label
var _hero_hp: ProgressBar
var _slots := CombatAnimationSlots.new()
var _generation := 0
var _impacts := 0
var _next_impact_at := 0.0
var _shown_player_hp := 1.0
var _shown_boss_hp := 1.0
var _shown_statuses: Array = []
var _allowed_speeds: Array = [1, 2, 3]

func _ready() -> void:
	_slots.setup(_arena, _fx)
	_fx.set("external_numbers", true)
	for connection in _speed_button.pressed.get_connections():
		_speed_button.pressed.disconnect(connection.callable)
	_speed_button.pressed.connect(_cycle_speed)
	_skip = UiKit.button("跳过战斗", MainTheme.VAR_SECONDARY, 72)
	_skip.name = "SkipBattle"
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.position = Vector2(-230, 12)
	_skip.size = Vector2(220, 72)
	_skip.visible = false
	_skip.pressed.connect(func() -> void: _request_finish("skip"))
	_arena.add_child(_skip)
	_statuses = QKit.outlined("", 28, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 5)
	_statuses.name = "CombatStatusIcons"
	_statuses.position = Vector2(24, 100)
	_statuses.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_statuses)
	_enemy_status = QKit.outlined("", 28, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 5)
	_enemy_status.name = "EnemyStatusIcons"
	_enemy_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arena.add_child(_enemy_status)
	_hero_hp = ProgressBar.new()
	_hero_hp.name = "HeroHpBar"
	_hero_hp.show_percentage = false
	_hero_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_hp.size = Vector2(240, 18)
	_hero_hp.add_theme_stylebox_override("fill", QSkin.custom(Color("52cfb0"), Color.TRANSPARENT, 0, 8))
	_hero_hp.add_theme_stylebox_override("background", QSkin.custom(Color("60402b"), Color.TRANSPARENT, 0, 8))
	_arena.add_child(_hero_hp)
	var spacer := get_node_or_null("TabOverhangSpacer") as Control
	if spacer != null:
		spacer.visible = false
	_load_speed()

func open_stage(state: Dictionary, content: Dictionary, stage: Dictionary, gate: Dictionary, realm: String) -> void:
	_generation += 1
	_impacts = 0
	combat_id = ""
	source = "stage"
	_session_data = {}
	super.open_stage(state, content, stage, gate, realm)
	# No stat preview panel; UI teammate owns the base layout and its final spacing.
	_controls.visible = false
	if _skip != null:
		_skip.visible = false
	if _statuses != null:
		_statuses.text = ""

func open_session(session: Dictionary, state: Dictionary, content: Dictionary, start_now: bool = true) -> void:
	_generation += 1
	_impacts = 0
	_next_impact_at = 0
	_session_data = session
	combat_id = str(session.get("combatId", ""))
	source = str(session.get("source", "stage"))
	var playback: Dictionary = session.get("playback", {})
	var mon: Dictionary = playback.get("monster", {})
	var target: Dictionary = session.get("target", {})
	var stage := {"slug": str(target.get("stageSlug", mon.get("id", "fog"))), "displayName": "异空间 · " + str(mon.get("name", "敌人")) if source == "fog" else str(_stage.get("displayName", "历练挑战")), "requiredRealmOrder": 0, "bosses": [mon]}
	# Base opens the confirmed visual layout only; replace its preview immediately with timeline playback.
	super.open_stage(state, content, stage, {}, str(state.get("realmName", "")))
	fight = BattleTimeline.new()
	(fight as BattleTimeline).load_session(session)
	_shown_player_hp = fight.player_max_hp
	_shown_boss_hp = fight.boss_max_hp
	_shown_statuses = []
	_allowed_speeds = (playback.get("speeds", [1,2,3]) as Array).map(func(value: Variant) -> int: return int(value))
	if _allowed_speeds.is_empty():
		_allowed_speeds = [1,2,3]
	_set_speed(speed)
	_can_skip = bool(playback.get("canSkip", false))
	_skip.visible = _can_skip
	_statuses.text = ""
	_controls.visible = false
	if source == "fog":
		(_boss_realm.get_parent() as Control).visible = false
	_refresh_bars(false)
	_refresh_time()
	if start_now:
		phase = Phase.RUNNING
		_clock = 0.0
		_start_button.visible = false
		_fx.play_intro()
		_append_feed("info", "服务器时间轴 · 全自动战斗")
		_slots.play_slot("player", "idle")
		_slots.play_slot("boss", "idle")

func _on_start() -> void:
	if phase != Phase.READY:
		return
	if combat_id.is_empty():
		phase = Phase.SUBMITTING
		_start_button.disabled = true
		start_requested.emit(stage_slug)
	else:
		phase = Phase.RUNNING
		_start_button.visible = false

func _cycle_speed() -> void:
	var at := _allowed_speeds.find(int(speed))
	_set_speed(float(_allowed_speeds[(at + 1) % _allowed_speeds.size()]), true)

func _set_speed(value: float, remember: bool = false) -> void:
	speed = clampf(roundf(value), 1, 3)
	if not _allowed_speeds.has(int(speed)):
		speed = float(_allowed_speeds[0])
	# x3 has no baked asset; use the same button with a readable ×3 overlay.
	if _speed_button != null:
		_speed_button.texture_normal = ArtLib.qui("btn_speed_x1") if speed == 1 else ArtLib.qui("btn_speed_x2") if speed == 2 else null
		_speed_fallback.visible = speed == 3 or _speed_button.texture_normal == null
		_speed_fallback.text = "×%d" % int(speed)
	_slots.speed = speed
	if _fx != null:
		_fx.set("playback_speed", speed)
	if remember:
		var cfg := ConfigFile.new()
		cfg.load(SPEED_PREF_PATH)
		cfg.set_value("battle", "speed", speed)
		cfg.save(SPEED_PREF_PATH)

func _load_speed() -> void:
	var cfg := ConfigFile.new()
	var value := 1.0
	if cfg.load(SPEED_PREF_PATH) == OK:
		value = float(cfg.get_value("battle", "speed", 1.0))
	_set_speed(value)

func _advance(seconds: float) -> void:
	if not fight is BattleTimeline:
		return
	_clock += seconds
	fight.advance_to(_clock)
	for event in fight.take_events():
		_launch_event(event)
	_refresh_time()
	_refresh_ult()
	_refresh_statuses()
	if fight.finished and _impacts == 0 and phase == Phase.RUNNING:
		_request_finish("complete")

func _launch_event(event: Dictionary) -> void:
	var side := str(event.get("side", "player"))
	var slot := str(event.get("kind", "attack"))
	_slots.play_slot(side, slot, event)
	var now := float(Time.get_ticks_msec()) / 1000.0
	var delay := (float(_fx.call("skill_impact_delay")) if slot in ["skill", "ult"] else 0.22) / speed
	var at := maxf(now + delay, _next_impact_at + 0.06 / speed)
	_next_impact_at = at
	_impacts += 1
	_impact_after(event, at - now, _generation)

func _impact_after(event: Dictionary, seconds: float, generation: int) -> void:
	await get_tree().create_timer(seconds).timeout
	if generation != _generation:
		return
	var target := "player" if str(event.get("side", "")) == "boss" else "boss"
	if not bool(event.get("dodged", false)):
		_slots.play_slot(target, "hit", event)
	_float_damage(event)
	_shown_player_hp = float(event.get("playerHpAfter", _shown_player_hp if target == "boss" else event.get("targetHpAfter", _shown_player_hp)))
	_shown_boss_hp = float(event.get("bossHpAfter", _shown_boss_hp if target == "player" else event.get("targetHpAfter", _shown_boss_hp)))
	_shown_statuses = event.get("statuses", [])
	_refresh_bars(true)
	_refresh_statuses()
	var text := _event_text(event)
	_append_feed("ult" if str(event.get("kind", "")) in ["skill", "ult"] else "hurt" if target == "player" else "hit", BattleReport.escape(text))
	_report.add_line(BattleReport.Kind.PLAIN, text, 0)
	_impacts -= 1

func _event_text(event: Dictionary) -> String:
	var attacker := _boss_name if str(event.get("side", "")) == "boss" else "你"
	if bool(event.get("dodged", false)):
		return "%s出手，对方闪避" % attacker
	var action := str(event.get("name", "功法")) if str(event.get("kind", "")) == "skill" else "怒气强击" if str(event.get("kind", "")) == "ult" else "普攻"
	var text := "%s · %s%s，造成 %d 伤害" % [attacker, action, "（暴击）" if bool(event.get("critical", false)) else "", BagModel.shown(float(event.get("damage", 0)))]
	if float(event.get("healed", 0)) > 0:
		text += "，回血 +%d" % BagModel.shown(float(event.healed))
	if float(event.get("absorbed", 0)) > 0:
		text += "，护盾抵挡 %d" % BagModel.shown(float(event.absorbed))
	return text

func _float_damage(event: Dictionary) -> void:
	var text := "闪避" if bool(event.get("dodged", false)) else "%s-%d" % ["暴击 " if bool(event.get("critical", false)) else "", BagModel.shown(float(event.get("damage", 0)))]
	var color := Color("ffe060") if bool(event.get("critical", false)) else Color("b8e8ff") if bool(event.get("dodged", false)) else Color.WHITE
	var label := QKit.outlined(text, 46, color, Color("472818"), 7, HORIZONTAL_ALIGNMENT_CENTER)
	label.position = Vector2(30 if str(event.get("side", "")) == "boss" else _arena.size.x * 0.5, _arena.size.y * 0.45)
	label.size = Vector2(430, 70)
	_float_layer.add_child(label)
	_float_layer.move_to_front()
	var tween := create_tween().set_parallel(true).set_speed_scale(speed)
	tween.tween_property(label, "position:y", label.position.y - 90, 0.8)
	tween.tween_property(label, "modulate:a", 0, 0.4).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)

func _refresh_bars(animate: bool = true) -> void:
	if not fight is BattleTimeline:
		super._refresh_bars(animate)
		return
	_boss_bar.set_hp(_shown_boss_hp, fight.boss_max_hp, animate)
	_push_boss_hp_ratio(_shown_boss_hp / maxf(1, fight.boss_max_hp))
	# No intermediate attack/defense panel. A small floating HP label keeps the hero readable.
	if _statuses != null:
		_refresh_statuses()

func _refresh_statuses() -> void:
	if _statuses == null or not fight is BattleTimeline:
		return
	var own: PackedStringArray = []
	var enemy: PackedStringArray = []
	for raw in _shown_statuses:
		var status: Dictionary = raw
		if float(status.get("expiresAt", 0)) <= fight.t:
			continue
		var label: String = {"attack_up": "↑攻", "defense_down": "↓防", "shield": "◇盾"}.get(str(status.get("kind", "")), "")
		var tag := "%s %.0fs" % [label, ceilf(float(status.get("expiresAt", 0)) - fight.t)]
		if str(status.get("side", "")) == "player":
			own.append(tag)
		else:
			enemy.append(tag)
	var hero_rect: Rect2 = _fx.get("_hero_rect")
	var boss_rect: Rect2 = _fx.get("_boss_rect")
	_statuses.position = Vector2(maxf(12, hero_rect.position.x), maxf(80, hero_rect.position.y - 70))
	_statuses.text = " · ".join(own)
	_enemy_status.position = Vector2(maxf(12, boss_rect.position.x), maxf(90, boss_rect.position.y - 30))
	_enemy_status.text = " · ".join(enemy)
	_hero_hp.position = Vector2(maxf(12, hero_rect.position.x + 30), minf(_arena.size.y - 24, hero_rect.end.y - 10))
	_hero_hp.value = clampf(_shown_player_hp / maxf(1, fight.player_max_hp), 0, 1) * 100

func _request_finish(mode: String) -> void:
	if combat_id.is_empty():
		return
	phase = Phase.SUBMITTING
	_skip.visible = false
	settle_requested.emit(combat_id, mode)

func abort() -> void:
	_generation += 1
	_impacts = 0
	phase = Phase.READY
	# Logout/disconnect only stop presentation; explicit retreat calls server before leaving.

func show_submit_error(message: String) -> void:
	_append_feed("end", "网络未确认，重试只取同一场结果：" + BattleReport.escape(message))
	phase = Phase.READY
	_start_button.visible = true
	_start_button.disabled = false
	UiKit.set_cta(_start_button, "重试读取结果", "服务器已保存战斗")

func show_result(result: Dictionary, name_of: Callable) -> void:
	_skip.visible = false
	var won := bool(result.get("battle", {}).get("win", false))
	_slots.play_slot("player", "win" if won else "lose", result.get("battle", {}))
	_slots.play_slot("boss", "lose" if won else "win", result.get("battle", {}))
	super.show_result(result, name_of)
	# Fog is consumed on victory: return to the exact pre-fight map instead of a meaningless retry.
	if source == "fog":
		var again := _result_body.find_child("RetryButton", true, false) as Button
		if again != null:
			again.visible = false


func sheet_anchor() -> Control:
	return get_node_or_null("ReportPanel") as Control
