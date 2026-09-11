class_name CombatRules
extends RefCounted

const DEFENSE_FACTOR := 0.4
const MONSTER_DEFENSE_FACTOR := 0.5
const DEFAULT_RESPAWN := 0.5


static func player_stats(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig
) -> CombatStats:
	return player_stats_with_loadout(
		state,
		idle,
		adventure,
		state.equipped if state != null else null
	)


static func player_stats_with_loadout(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	loadout: EquipmentLoadout
) -> CombatStats:
	var stats := CombatStats.new()
	if state == null or adventure == null:
		return stats
	var realm := idle.realm_by_id(state.realm_id) if idle != null else null
	var base := adventure.realm_stats(state.realm_id if realm == null else realm.id)
	if base != null:
		stats.attack = base.attack
		stats.defense = base.defense
		stats.hp = base.hp
		stats.interval = base.interval
	if loadout == null:
		return stats
	for slot in EquipSlot.ORDER:
		var uid := loadout.uid_for(slot)
		var stack := InventoryRules.find_stack(state, uid)
		if stack == null:
			continue
		var item := adventure.item_by_id(stack.item_id)
		if item != null and item.is_equipment():
			stats.add(item.to_stats())
	for skill_id in state.learned_skill_ids:
		var skill := adventure.skill_by_id(skill_id)
		if skill != null:
			stats.add(skill.to_stats())
	stats.apply_speed_to_interval()
	return stats


static func can_enter(
	state: CultivationState,
	idle: IdleConfig,
	stage: StageDef,
	stats: CombatStats,
	require_unlocked: bool = true
) -> bool:
	return enter_reason(state, idle, stage, stats, require_unlocked).is_empty()


static func enter_reason(
	state: CultivationState,
	idle: IdleConfig,
	stage: StageDef,
	stats: CombatStats,
	require_unlocked: bool = true
) -> String:
	if stage == null:
		return "关卡不存在。"
	var realm := idle.realm_by_id(state.realm_id) if idle != null and state != null else null
	if realm != null and realm.order < stage.min_realm_order:
		return "境界不足，无法踏入 %s。" % stage.display_name
	if stats == null or stats.power() + 0.0001 < stage.min_power:
		return "战力不足，需 %.0f 才能挑战 %s。" % [stage.min_power, stage.display_name]
	if require_unlocked and state != null and not state.unlocked_stage_ids.has(stage.id) and stage.order > 0:
		return "尚未解开 %s。" % stage.display_name
	return ""


static func time_to_kill(player: CombatStats, monster: CombatStats) -> float:
	if player == null or monster == null or player.interval <= 0.0:
		return -1.0
	var damage := maxf(1.0, player.attack - monster.defense * DEFENSE_FACTOR)
	return monster.hp / (damage / player.interval)


static func time_to_die(player: CombatStats, monster: CombatStats) -> float:
	if player == null or monster == null or monster.interval <= 0.0:
		return -1.0
	var damage := maxf(0.0, monster.attack - player.defense * MONSTER_DEFENSE_FACTOR)
	if damage <= 0.0:
		return INF
	return player.hp / (damage / monster.interval)


static func settle(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	elapsed_seconds: int
) -> CombatSettlement:
	var result := CombatSettlement.new()
	if state == null or adventure == null or elapsed_seconds <= 0:
		return result
	var stage := adventure.stage_by_id(state.current_stage_id)
	if stage == null or stage.monsters.is_empty():
		return result
	var player := player_stats(state, idle, adventure)
	var remaining := float(elapsed_seconds) + maxf(state.combat_remainder, 0.0)
	var respawn := adventure.respawn_seconds
	if respawn <= 0.0:
		respawn = DEFAULT_RESPAWN
	var loot_counts: Dictionary = {}
	var sample_limit := 8
	while remaining > 0.0001:
		var monster := _pick_monster(stage, state)
		var kill_time := time_to_kill(player, monster.to_stats())
		var die_time := time_to_die(player, monster.to_stats())
		if kill_time <= 0.0 or die_time <= kill_time:
			result.retreated = true
			InventoryRules.append_log(state, "不敌 %s，已退回调息。" % monster.display_name)
			result.lines.append("不敌 %s，已退回调息。" % monster.display_name)
			break
		var cycle := kill_time + respawn
		if remaining + 0.0001 < cycle:
			break
		remaining -= cycle
		result.kills += 1
		if result.kills <= sample_limit:
			var line := "斩杀 %s。" % monster.display_name
			InventoryRules.append_log(state, line)
			result.lines.append(line)
		_roll_drops(state, adventure, monster, loot_counts, result)
	if result.kills > sample_limit:
		var more := "另有 %d 场战斗已并入结算。" % (result.kills - sample_limit)
		InventoryRules.append_log(state, more)
		result.lines.append(more)
	for item_id in loot_counts.keys():
		var item := adventure.item_by_id(str(item_id))
		if item == null:
			continue
		result.loot_names.append("%s ×%d" % [item.display_name, int(loot_counts[item_id])])
	if result.kills > 0:
		_unlock_next(state, idle, adventure, player)
	state.combat_remainder = 0.0 if result.retreated else remaining
	return result


static func _pick_monster(stage: StageDef, state: CultivationState) -> MonsterDef:
	var roll := LootRng.roll(state.loot_seed)
	state.loot_seed = int(roll.seed)
	var index := int(floor(float(roll.value) * float(stage.monsters.size())))
	index = clampi(index, 0, stage.monsters.size() - 1)
	return stage.monsters[index]


static func _roll_drops(
	state: CultivationState,
	adventure: AdventureConfig,
	monster: MonsterDef,
	loot_counts: Dictionary,
	result: CombatSettlement
) -> void:
	for drop in monster.drops:
		var chance := float(drop.get("chance", 0.0))
		var count := int(drop.get("count", 1))
		var item_id := str(drop.get("item_id", ""))
		if chance <= 0.0 or count <= 0 or item_id.is_empty():
			continue
		chance *= adventure.loot_chance_scale
		var roll := LootRng.roll(state.loot_seed)
		state.loot_seed = int(roll.seed)
		if float(roll.value) > chance:
			continue
		var item := adventure.item_by_id(item_id)
		if item == null:
			continue
		var added: Dictionary = InventoryRules.add_item(
			state,
			adventure,
			item,
			count,
			state.settings.bag_full_policy
		)
		if int(added.added) > 0:
			loot_counts[item_id] = int(loot_counts.get(item_id, 0)) + int(added.added)
			if not str(added.discarded).is_empty():
				InventoryRules.append_log(state, "行囊已满，丢弃 %s。" % str(added.discarded))
		if int(added.skipped) > 0:
			result.bag_skipped += int(added.skipped)
			InventoryRules.append_log(state, "行囊已满，%s 未能入袋。" % item.display_name)


static func _unlock_next(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	player: CombatStats
) -> void:
	var stage := adventure.stage_by_id(state.current_stage_id)
	if stage == null or not stage.has_next():
		return
	var next_stage := adventure.stage_by_id(stage.next_id)
	if next_stage == null or state.unlocked_stage_ids.has(next_stage.id):
		return
	var realm := idle.realm_by_id(state.realm_id) if idle != null else null
	if realm != null and realm.order < next_stage.min_realm_order:
		return
	if player.power() + 0.0001 < next_stage.min_power:
		return
	state.unlocked_stage_ids.append(next_stage.id)
	InventoryRules.append_log(state, "已可挑战 %s。" % next_stage.display_name)
