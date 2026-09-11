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
var long_term_config: LongTermConfig
var config_service: ConfigService
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
	adventure_rules: AdventureConfig = null,
	long_term_rules: LongTermConfig = null
) -> void:
	time_service = clock if clock != null else TimeService.new()
	save_service = save if save != null else SaveService.new()
	config = rules
	adventure = adventure_rules
	long_term_config = long_term_rules
	app_version = version if not version.is_empty() else _read_app_version()


func start() -> bool:
	config_service = ConfigService.new()
	if not config_service.load_all():
		push_error("Game config is missing or invalid.")
		return false
	if config == null:
		config = config_service.idle
	if adventure == null:
		adventure = config_service.adventure
	if long_term_config == null:
		long_term_config = config_service.long_term
	if (
		config == null
		or config.starting_realm() == null
		or adventure == null
		or long_term_config == null
	):
		push_error("Idle or adventure config is missing or invalid.")
		return false

	state = save_service.load_state()
	if state == null or config.realm_by_id(state.realm_id) == null:
		state = _new_state()
		journal.add("踏入修行，当前境界为 %s。" % config.starting_realm().display_name)
		journal.add("已选定关卡：%s。" % adventure.starting_stage().display_name)
	else:
		state.apply_adventure_defaults(adventure, long_term_config)
		_sanitize_progress()
		_expire_pills()
		_settle_offline()
	_persist()
	state_changed.emit()
	return true


func tick_online() -> void:
	if state == null:
		return
	_expire_pills()
	var realm := current_realm()
	if realm == null:
		return
	var elapsed := time_service.elapsed_seconds(state.last_settled_unix)
	if elapsed <= 0:
		if elapsed < 0:
			state.last_settled_unix = time_service.now_unix()
			_persist()
		return
	CultivationRules.apply_elapsed(state, cultivate_rate(), elapsed, ONLINE_CAP_SECONDS)
	_apply_combat(elapsed)
	_apply_long_term(elapsed)
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
	state.sanitize_running(adventure, next_realm.order)
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
	return CombatRules.player_stats(state, config, adventure, long_term_config)


func current_stage() -> StageDef:
	return adventure.stage_by_id(state.current_stage_id) if state != null and adventure != null else null


func next_stage() -> StageDef:
	return adventure.next_stage(current_stage()) if adventure != null else null


func can_challenge_next() -> bool:
	var nxt := next_stage()
	return CombatRules.can_enter(state, config, nxt, player_stats(), false, adventure)


func challenge_next() -> String:
	var nxt := next_stage()
	var reason := CombatRules.enter_reason(state, config, nxt, player_stats(), false, adventure)
	if not reason.is_empty():
		return reason
	if not state.unlocked_stage_ids.has(nxt.id):
		state.unlocked_stage_ids.append(nxt.id)
	state.current_stage_id = nxt.id
	state.set_layer(nxt.id, StageLayer.OUTER)
	journal.add("踏入关卡：%s。" % nxt.display_name)
	InventoryRules.append_log(state, "开始历练 %s。" % nxt.display_name)
	_persist()
	state_changed.emit()
	return ""


func select_stage(stage_id: String) -> String:
	var stage := adventure.stage_by_id(stage_id) if adventure != null else null
	var reason := CombatRules.enter_reason(state, config, stage, player_stats(), true, adventure)
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
	var realm := current_realm()
	if realm != null and realm.order < skill.min_realm_order:
		return "境界不足，无法参悟 %s。" % skill.display_name
	var rank := state.skill_rank_of(skill.id)
	if rank >= 2:
		return "已小成 %s。" % skill.display_name
	if rank <= 0:
		stack.count -= 1
		if stack.count <= 0:
			state.inventory = state.inventory.filter(func(item: ItemStack) -> bool:
				return item.uid != uid
			)
		state.set_skill_rank(skill.id, 1)
		_try_auto_run(skill)
		journal.add("参悟入门：%s（%s）。" % [skill.display_name, SkillRank.display_name(skill.rank)])
		_persist()
		state_changed.emit()
		return ""
	if InventoryRules.count_item(state, item.id) < 2:
		return "小成需要再交 2 本 %s。" % item.display_name
	if not InventoryRules.consume_count(state, item.id, 2):
		return "残页不足。"
	state.set_skill_rank(skill.id, 2)
	journal.add("功法小成：%s。" % skill.display_name)
	_persist()
	state_changed.emit()
	return ""


func assign_cave_labor(resource_id: String, amount: int) -> bool:
	var changed := LongTermRules.assign_labor(
		state.long_term.cave,
		long_term_config,
		state.long_term.sect,
		state.long_term.ascension,
		resource_id,
		amount
	)
	if changed:
		_persist_and_emit()
	return changed


func upgrade_cave_building(building_id: String) -> bool:
	var changed := LongTermRules.upgrade_building(
		state.long_term.economy,
		state.long_term.cave,
		long_term_config,
		building_id
	)
	if changed:
		_persist_and_emit()
	return changed


func join_sect(sect_id: String) -> bool:
	var changed := LongTermRules.join_sect(
		state.long_term.sect,
		state.long_term.cave,
		long_term_config,
		sect_id
	)
	if changed:
		_persist_and_emit()
	return changed


func recruit_sect_npc(npc_id: String) -> bool:
	var changed := LongTermRules.recruit_npc(
		state.long_term.sect,
		long_term_config,
		npc_id
	)
	if changed:
		LongTermRules.unlock_sect_recipes(
			state.long_term.sect,
			state.long_term.craft,
			long_term_config
		)
		_persist_and_emit()
	return changed


func claim_sect_position(position_id: String) -> bool:
	var changed := LongTermRules.claim_position(
		state.long_term.sect,
		long_term_config,
		position_id
	)
	if changed:
		_persist_and_emit()
	return changed


func queue_recipe(recipe_id: String, amount: int = 1) -> bool:
	var changed := LongTermRules.queue_recipe(
		state.long_term.economy,
		state.long_term.craft,
		state.long_term.sect,
		long_term_config,
		recipe_id,
		amount
	)
	if changed:
		_persist_and_emit()
	return changed


func research_recipe(recipe_id: String) -> Dictionary:
	var result := LongTermRules.research_recipe(
		state.long_term.economy,
		state.long_term.craft,
		long_term_config,
		recipe_id,
		state.long_term.run_seconds + state.long_term.ascension.ascension_count * 10_007
	)
	if bool(result.get("attempted", false)):
		_persist_and_emit()
	return result


func decompose_recipe(recipe_id: String, amount: int = 1) -> bool:
	var changed := LongTermRules.decompose(
		state.long_term.economy,
		long_term_config,
		recipe_id,
		amount
	)
	if changed:
		_persist_and_emit()
	return changed


func recycle_old_materials() -> Dictionary[String, float]:
	var recycled: Dictionary[String, float] = {}
	var kept: Array[ItemStack] = []
	var resource_ids := ["lumen_moss", "clear_dew", "vein_sand", "hollow_wood"]
	for stack in state.inventory:
		var definition := adventure.item_by_id(stack.item_id)
		if definition == null or not definition.is_material() or stack.locked:
			kept.append(stack)
			continue
		var resource_id: String = resource_ids[
			abs(stack.item_id.hash()) % resource_ids.size()
		]
		var value := float(stack.count * maxi(definition.min_realm_order + 1, 1))
		state.long_term.economy.add(resource_id, value)
		recycled[resource_id] = recycled.get(resource_id, 0.0) + value
	state.inventory = kept
	if not recycled.is_empty():
		journal.add("洞府回收旧材料，转化为 %d 类基础资源。" % recycled.size())
		_persist_and_emit()
	return recycled


func run_expedition(expedition_id: String) -> Dictionary:
	var result := LongTermRules.run_expedition(
		state.long_term.economy,
		state.long_term.expedition,
		state.long_term.sect,
		state.long_term.beast,
		long_term_config,
		expedition_id,
		_expedition_base_power(),
		state.long_term.expedition.encounter_index + state.long_term.run_seconds
	)
	if bool(result.get("success", false)):
		_persist_and_emit()
	return result


func expedition_power() -> int:
	return LongTermRules.expedition_power(
		_expedition_base_power(),
		state.long_term.sect,
		state.long_term.beast,
		long_term_config
	)


func set_auto_expedition(expedition_id: String) -> bool:
	var changed := LongTermRules.set_auto_expedition(
		state.long_term.expedition,
		long_term_config,
		expedition_id
	)
	if changed:
		_persist_and_emit()
	return changed


func claim_beast(beast_id: String) -> bool:
	var changed := LongTermRules.claim_beast(
		state.long_term.beast,
		state.long_term.expedition,
		long_term_config,
		beast_id
	)
	if changed:
		_persist_and_emit()
	return changed


func deploy_beast(beast_id: String) -> bool:
	var changed := LongTermRules.deploy_beast(state.long_term.beast, beast_id)
	if changed:
		_persist_and_emit()
	return changed


func feed_beast(beast_id: String, servings: int = 1) -> int:
	var experience := LongTermRules.feed_beast(
		state.long_term.economy,
		state.long_term.beast,
		long_term_config,
		beast_id,
		servings
	)
	if experience > 0:
		_persist_and_emit()
	return experience


func can_soft_ascend() -> bool:
	return LongTermRules.can_soft_ascend(
		state.long_term.economy,
		state.long_term.cave,
		state.long_term.sect,
		state.long_term.craft,
		state.long_term.beast,
		state.long_term.expedition,
		long_term_config,
		_current_realm_order(),
		state.long_term.run_seconds
	)


func upgrade_outpost(outpost_id: String) -> bool:
	var changed := LongTermRules.upgrade_outpost(
		state.long_term.economy,
		state.long_term.ascension,
		long_term_config,
		outpost_id
	)
	if changed:
		_persist_and_emit()
	return changed


func claim_ending(ending_id: String) -> bool:
	var changed := LongTermRules.claim_ending(
		state.long_term.ascension,
		long_term_config,
		ending_id
	)
	if changed:
		journal.add("终局达成：%s。" % long_term_config.ending_by_id(ending_id).display_name)
		_persist_and_emit()
	return changed


func soft_ascend() -> bool:
	if not LongTermRules.soft_ascend(
		state.long_term.economy,
		state.long_term.cave,
		state.long_term.sect,
		state.long_term.craft,
		state.long_term.beast,
		state.long_term.expedition,
		state.long_term.ascension,
		long_term_config,
		_current_realm_order(),
		state.long_term.run_seconds
	):
		return false
	var retained := state.long_term
	var settings := GameSettings.from_dictionary(state.settings.to_dictionary())
	state = _new_state()
	state.long_term = retained
	state.long_term.run_seconds = 0
	state.settings = settings
	journal.add("斩断尘缘，携传承踏入新一世。")
	_persist_and_emit()
	return true


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


func cultivate_rate() -> float:
	_expire_pills()
	var realm := current_realm()
	if realm == null:
		return 0.0
	var rate := realm.gain_per_second
	if state != null and adventure != null and not state.running_heart_id.is_empty():
		var heart := adventure.skill_by_id(state.running_heart_id)
		if heart != null:
			rate *= heart.cultivate_factor(state.skill_rank_of(heart.id))
	if state != null and state.qi_pill_until > time_service.now_unix():
		rate *= 1.15
	if state != null:
		rate *= LongTermRules.cultivate_factor(state.long_term, long_term_config)
	return rate


func run_skill(skill_id: String) -> String:
	var skill := adventure.skill_by_id(skill_id) if adventure != null else null
	if skill == null:
		return "没有这门功法。"
	if state.skill_rank_of(skill.id) <= 0:
		return "尚未参悟 %s。" % skill.display_name
	var realm := current_realm()
	if realm != null and realm.order < skill.min_realm_order:
		return "境界不足，无法运转 %s。" % skill.display_name
	if skill.is_heart():
		state.running_heart_id = skill.id
	else:
		var arts: PackedStringArray = state.running_art_ids.duplicate()
		if arts.has(skill.id):
			journal.add("继续运转 %s。" % skill.display_name)
			_persist()
			state_changed.emit()
			return ""
		var slots := SkillRole.art_slot_count(realm.order if realm != null else 0)
		if arts.size() < slots:
			arts.append(skill.id)
		elif arts.size() > 0:
			arts[0] = skill.id
		else:
			arts = PackedStringArray([skill.id])
		state.running_art_ids = arts
	journal.add("开始运转 %s。" % skill.display_name)
	_persist()
	state_changed.emit()
	return ""


func stop_skill(skill_id: String) -> String:
	if state == null or skill_id.is_empty():
		return "没有这门功法。"
	if state.running_heart_id == skill_id:
		state.running_heart_id = ""
	else:
		var kept := PackedStringArray()
		for running_id in state.running_art_ids:
			if running_id != skill_id:
				kept.append(running_id)
		state.running_art_ids = kept
	var skill := adventure.skill_by_id(skill_id) if adventure != null else null
	journal.add("停下 %s。" % (skill.display_name if skill != null else "功法"))
	_persist()
	state_changed.emit()
	return ""


func promote_skill(skill_id: String) -> String:
	var skill := adventure.skill_by_id(skill_id) if adventure != null else null
	if skill == null:
		return "没有这门功法。"
	var book := adventure.item_by_id(skill.book_id)
	if book == null:
		return "残页已模糊，无法参悟。"
	var stack := _first_book_stack(skill.id)
	if stack == null:
		return "行囊中没有这本残页。"
	return learn_skill_from(stack.uid)


func merge_item(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这件物品。"
	if state.equipped.contains_uid(uid):
		return "正在穿戴，先卸下再合并。"
	var item := adventure.item_by_id(stack.item_id) if adventure != null else null
	if item == null or not item.is_equipment():
		return "只有装备能合并。"
	if not InventoryRules.merge(state, uid):
		return "没有另一件同名同阶可合。"
	journal.add("合并 %s 至合+%d。" % [
		item.display_name,
		stack.merge_level,
	])
	_persist()
	state_changed.emit()
	return ""


func temper_item(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这件物品。"
	if state.equipped.contains_uid(uid):
		return "正在穿戴，先卸下再温养。"
	var item := adventure.item_by_id(stack.item_id) if adventure != null else null
	if item == null or not item.is_equipment():
		return "只有装备能温养。"
	if stack.tempered:
		return "这件已经温养过。"
	if not InventoryRules.temper(state, uid):
		return "温养需要 3 灵草与 1 兽骨。"
	journal.add("温养 %s。" % item.display_name)
	_persist()
	state_changed.emit()
	return ""


func consume_pill(uid: int) -> String:
	var stack := InventoryRules.find_stack(state, uid)
	if stack == null:
		return "行囊中没有这件物品。"
	var item := adventure.item_by_id(stack.item_id) if adventure != null else null
	if item == null or not item.is_pill():
		return "这不是丹药。"
	if item.id != "pill_qi_0" and item.id != "pill_body_0":
		return "这粒丹还不能服。"
	if not InventoryRules.consume_count(state, item.id, 1):
		return "丹药不足。"
	var until := time_service.now_unix() + 600
	if item.id == "pill_qi_0":
		state.qi_pill_until = until
		journal.add("服下回气丹，一时修为更勤。")
	else:
		state.body_pill_until = until
		journal.add("服下养体丹，一时皮肉更厚。")
	_persist()
	state_changed.emit()
	return ""


func select_layer(layer: int) -> String:
	var stage := current_stage()
	if stage == null:
		return "未选定关卡。"
	var wall := CombatRules.enter_reason(state, config, stage, player_stats(), true, adventure)
	if not wall.is_empty():
		return wall
	var reason := CombatRules.layer_reason(state, stage, layer)
	if not reason.is_empty():
		return reason
	state.set_layer(stage.id, layer)
	InventoryRules.append_log(state, "转往 %s%s 挂机。" % [stage.display_name, StageLayer.display_name(layer)])
	_persist()
	state_changed.emit()
	return ""


func _try_auto_run(skill: SkillDef) -> void:
	if skill == null or state == null:
		return
	if skill.is_heart() and state.running_heart_id.is_empty():
		state.running_heart_id = skill.id
		return
	if not skill.is_art():
		return
	var realm := current_realm()
	var slots := SkillRole.art_slot_count(realm.order if realm != null else 0)
	if state.running_art_ids.has(skill.id):
		return
	if state.running_art_ids.size() < slots:
		var arts: PackedStringArray = state.running_art_ids.duplicate()
		arts.append(skill.id)
		state.running_art_ids = arts


func _first_book_stack(skill_id: String) -> ItemStack:
	if state == null or adventure == null:
		return null
	for stack in state.inventory:
		var item := adventure.item_by_id(stack.item_id)
		if item != null and item.skill_id == skill_id:
			return stack
	return null


func _expire_pills() -> void:
	if state == null:
		return
	var now := time_service.now_unix()
	if state.qi_pill_until > 0 and state.qi_pill_until <= now:
		state.qi_pill_until = 0
	if state.body_pill_until > 0 and state.body_pill_until <= now:
		state.body_pill_until = 0


func _settle_offline() -> void:
	var realm := current_realm()
	var elapsed := time_service.elapsed_seconds(state.last_settled_unix)
	last_offline_result = CultivationRules.apply_elapsed(
		state,
		cultivate_rate(),
		elapsed,
		config.offline_cap_seconds
	)
	if last_offline_result.clock_rewound:
		state.last_settled_unix = time_service.now_unix()
		journal.add("检测到时间回拨，未扣除修为。")
		offline_settled.emit(last_offline_result)
		return
	_apply_combat(last_offline_result.applied_seconds)
	_apply_long_term(last_offline_result.applied_seconds)
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
	last_combat_result = CombatRules.settle(
		state,
		config,
		adventure,
		elapsed,
		long_term_config
	)


func _apply_long_term(elapsed: int) -> SettlementDelta:
	return SettlementEngine.settle_long_term(
		state,
		long_term_config,
		elapsed,
		_expedition_base_power()
	)


func _expedition_base_power() -> int:
	var stats := player_stats()
	return _current_realm_order() * 2 + floori(
		(stats.attack + stats.defense) / 10.0
	)


func _current_realm_order() -> int:
	for index in range(config.realms.size()):
		if config.realms[index].id == state.realm_id:
			return index
	return 0


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
	var realm := current_realm()
	state.sanitize_running(adventure, realm.order if realm != null else 0)
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
	created.apply_adventure_defaults(adventure, long_term_config)
	return created


func _persist() -> void:
	save_service.save_state(state, app_version, app_version, time_service.now_unix())


func _persist_and_emit() -> void:
	_persist()
	state_changed.emit()


func _read_app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
