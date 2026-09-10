class_name CultivationSession
extends RefCounted

signal state_changed
signal offline_settled(result: SettlementResult)
signal breakthrough_succeeded(from_name: String, to_name: String, new_rate: float)

const CONFIG_PATH := "res://resources/config/idle_rules.json"
const ADVENTURE_PATH := "res://resources/config/adventure.json"
const ONLINE_CAP_SECONDS := 0

var time_service: TimeService
var config: IdleConfig
var adventure: AdventureConfig
var save_service: SaveService
var state: CultivationState
var app_version: String
var last_offline_result: SettlementResult
var last_combat_result: CombatSettlement
var journal := CultivationJournal.new()


func _init(
	clock: TimeService = null,
	save: SaveService = null,
	rules: IdleConfig = null,
	version: String = "",
	adventure_rules: AdventureConfig = null
) -> void:
	time_service = clock if clock != null else TimeService.new()
	save_service = save if save != null else SaveService.new()
	config = rules
	adventure = adventure_rules
	app_version = version if not version.is_empty() else _read_app_version()


func start() -> bool:
	if config == null:
		config = IdleConfig.from_resource(CONFIG_PATH)
	if adventure == null:
		adventure = AdventureConfig.from_resource(ADVENTURE_PATH)
	if config == null or config.starting_realm() == null or adventure == null:
		push_error("Idle or adventure config is missing or invalid.")
		return false

	state = save_service.load_state()
	if state == null or config.realm_by_id(state.realm_id) == null:
		state = _new_state()
		journal.add("踏入修行，当前境界为 %s。" % config.starting_realm().display_name)
		journal.add("已选定关卡：%s。" % adventure.starting_stage().display_name)
	else:
		state.apply_adventure_defaults(adventure)
		_sanitize_progress()
		_settle_offline()
	_persist()
	state_changed.emit()
	return true


func tick_online() -> void:
	if state == null:
		return
	var realm := current_realm()
	if realm == null:
		return
	var elapsed := time_service.elapsed_seconds(state.last_settled_unix)
	if elapsed <= 0:
		if elapsed < 0:
			state.last_settled_unix = time_service.now_unix()
			_persist()
		return
	CultivationRules.apply_elapsed(state, realm.gain_per_second, elapsed, ONLINE_CAP_SECONDS)
	_apply_combat(elapsed)
	state.last_settled_unix = time_service.now_unix()
	_persist()
	state_changed.emit()


func try_breakthrough() -> bool:
	var current := current_realm()
	var next_realm := config.next_realm(current)
	if current == null or next_realm == null:
		return false
	var from_name := current.display_name
	if not CultivationRules.breakthrough(state, current, next_realm):
		return false
	journal.add("突破成功：%s → %s，效率变为 %s" % [
		from_name,
		next_realm.display_name,
		CultivationFormat.rate(next_realm.gain_per_second),
	])
	_persist()
	state_changed.emit()
	breakthrough_succeeded.emit(from_name, next_realm.display_name, next_realm.gain_per_second)
	return true


func current_realm() -> RealmDef:
	return config.realm_by_id(state.realm_id) if state != null and config != null else null


func next_realm() -> RealmDef:
	return config.next_realm(current_realm())


func can_breakthrough() -> bool:
	return CultivationRules.can_breakthrough(state, current_realm())


func progress() -> float:
	return CultivationRules.progress_to_next(state, current_realm())


func player_stats() -> CombatStats:
	return CombatRules.player_stats(state, config, adventure)


func current_stage() -> StageDef:
	return adventure.stage_by_id(state.current_stage_id) if state != null and adventure != null else null


func next_stage() -> StageDef:
	return adventure.next_stage(current_stage()) if adventure != null else null


func can_challenge_next() -> bool:
	var nxt := next_stage()
	return CombatRules.can_enter(state, config, nxt, player_stats(), false)


func challenge_next() -> String:
	var nxt := next_stage()
	var reason := CombatRules.enter_reason(state, config, nxt, player_stats(), false)
	if not reason.is_empty():
		return reason
	if not state.unlocked_stage_ids.has(nxt.id):
		state.unlocked_stage_ids.append(nxt.id)
	state.current_stage_id = nxt.id
	journal.add("踏入关卡：%s。" % nxt.display_name)
	InventoryRules.append_log(state, "开始历练 %s。" % nxt.display_name)
	_persist()
	state_changed.emit()
	return ""


func select_stage(stage_id: String) -> String:
	var stage := adventure.stage_by_id(stage_id) if adventure != null else null
	var reason := CombatRules.enter_reason(state, config, stage, player_stats(), true)
	if not reason.is_empty():
		return reason
	state.current_stage_id = stage.id
	InventoryRules.append_log(state, "转往 %s 挂机。" % stage.display_name)
	_persist()
	state_changed.emit()
	return ""


func equip_item(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这件物品。"
	var item := adventure.item_by_id(stack.item_id)
	if item == null or not item.is_equipment():
		return "这不是可穿戴的装备。"
	var realm := current_realm()
	if realm != null and realm.order < item.min_realm_order:
		return "境界不足，无法穿戴 %s。" % item.display_name
	state.equipped.set_uid(item.slot, uid)
	journal.add("穿上 %s。" % item.display_name)
	_persist()
	state_changed.emit()
	return ""


func unequip_slot(slot: String) -> bool:
	if state == null or not EquipSlot.is_valid(slot):
		return false
	state.equipped.set_uid(slot, 0)
	_persist()
	state_changed.emit()
	return true


func toggle_lock(uid: int) -> bool:
	if not InventoryRules.toggle_lock(state, uid):
		return false
	_persist()
	state_changed.emit()
	return true


func discard_item(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这件物品。"
	if stack.locked:
		return "已上锁，不能丢弃。"
	if state.equipped.contains_uid(uid):
		return "正在穿戴，不能丢弃。"
	var item := adventure.item_by_id(stack.item_id)
	if not InventoryRules.discard(state, uid):
		return "无法丢弃。"
	journal.add("丢弃 %s。" % (item.display_name if item != null else "物品"))
	_persist()
	state_changed.emit()
	return ""


func learn_skill_from(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这本残页。"
	var item := adventure.item_by_id(stack.item_id)
	if item == null or not item.is_skill_book():
		return "这不是功法残页。"
	var skill := adventure.skill_by_id(item.skill_id)
	if skill == null:
		return "残页已模糊，无法参悟。"
	if state.learned_skill_ids.has(skill.id):
		return "已学会 %s。" % skill.display_name
	var realm := current_realm()
	if realm != null and realm.order < skill.min_realm_order:
		return "境界不足，无法参悟 %s。" % skill.display_name
	stack.count -= 1
	if stack.count <= 0:
		state.inventory = state.inventory.filter(func(item: ItemStack) -> bool:
			return item.uid != uid
		)
	state.learned_skill_ids.append(skill.id)
	journal.add("参悟功法：%s（%s）。" % [skill.display_name, SkillRank.display_name(skill.rank)])
	_persist()
	state_changed.emit()
	return ""


func set_battle_log_enabled(enabled: bool) -> void:
	state.settings.battle_log_enabled = enabled
	_persist()
	state_changed.emit()


func set_bag_full_policy(policy: String) -> void:
	state.settings.bag_full_policy = (
		GameSettings.POLICY_DISCARD_LOWEST
		if policy == GameSettings.POLICY_DISCARD_LOWEST
		else GameSettings.POLICY_SKIP
	)
	_persist()
	state_changed.emit()


func set_sound_volume(value: float) -> void:
	state.settings.sound_volume = clampf(value, 0.0, 1.0)
	_persist()
	state_changed.emit()


func export_save_text() -> String:
	return save_service.export_text()


func item_def(item_id: String) -> ItemDef:
	return adventure.item_by_id(item_id) if adventure != null else null


func _settle_offline() -> void:
	var realm := current_realm()
	var elapsed := time_service.elapsed_seconds(state.last_settled_unix)
	last_offline_result = CultivationRules.apply_elapsed(
		state,
		realm.gain_per_second,
		elapsed,
		config.offline_cap_seconds
	)
	if last_offline_result.clock_rewound:
		state.last_settled_unix = time_service.now_unix()
		journal.add("检测到时间回拨，未扣除修为。")
		offline_settled.emit(last_offline_result)
		return
	_apply_combat(last_offline_result.applied_seconds)
	last_offline_result.combat_kills = last_combat_result.kills if last_combat_result != null else 0
	last_offline_result.combat_retreated = last_combat_result.retreated if last_combat_result != null else false
	last_offline_result.combat_loot = last_combat_result.loot_names if last_combat_result != null else PackedStringArray()
	last_offline_result.combat_bag_skipped = last_combat_result.bag_skipped if last_combat_result != null else 0
	state.last_settled_unix = time_service.now_unix()
	if last_offline_result.gained > 0.0:
		var line := "闭关归来，获得修为 %s，结算 %s" % [
			CultivationFormat.amount(last_offline_result.gained),
			CultivationFormat.duration_hours(last_offline_result.applied_seconds),
		]
		if last_offline_result.hit_cap:
			line += "，已顶到 %s 上限" % CultivationFormat.duration_hours(config.offline_cap_seconds)
		journal.add(line)
		if last_offline_result.combat_kills > 0:
			journal.add("此间斩杀 %d，战利品已入行囊。" % last_offline_result.combat_kills)
		offline_settled.emit(last_offline_result)


func _apply_combat(elapsed: int) -> void:
	last_combat_result = CombatRules.settle(state, config, adventure, elapsed)


func _sanitize_progress() -> void:
	var kept: Array[ItemStack] = []
	for stack in state.inventory:
		if adventure.item_by_id(stack.item_id) != null:
			kept.append(stack)
	state.inventory = kept
	for slot in EquipSlot.ORDER:
		var uid := state.equipped.uid_for(slot)
		if uid > 0 and InventoryRules.find_stack(state, uid) == null:
			state.equipped.set_uid(slot, 0)
	var learned := PackedStringArray()
	for skill_id in state.learned_skill_ids:
		if adventure.skill_by_id(skill_id) != null and not learned.has(skill_id):
			learned.append(skill_id)
	state.learned_skill_ids = learned
	if adventure.stage_by_id(state.current_stage_id) == null:
		state.current_stage_id = adventure.starting_stage().id
	var unlocked := PackedStringArray()
	for stage_id in state.unlocked_stage_ids:
		if adventure.stage_by_id(stage_id) != null and not unlocked.has(stage_id):
			unlocked.append(stage_id)
	if unlocked.is_empty():
		unlocked.append(adventure.starting_stage().id)
	state.unlocked_stage_ids = unlocked


func _new_state() -> CultivationState:
	var created := CultivationState.new()
	created.cultivation = 0.0
	created.realm_id = config.starting_realm().id
	created.last_settled_unix = time_service.now_unix()
	created.apply_adventure_defaults(adventure)
	return created


func _persist() -> void:
	save_service.save_state(state, app_version, app_version, time_service.now_unix())


func _read_app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
