class_name InventoryRules
extends RefCounted

const MAX_STACK := 99
const MAX_LOG := 50


static func find_stack(state: CultivationState, uid: int) -> ItemStack:
	if state == null or uid <= 0:
		return null
	for stack in state.inventory:
		if stack.uid == uid:
			return stack
	return null


static func bag_used(state: CultivationState) -> int:
	return filter_stacks(state, null, "all").size()


static func is_full(state: CultivationState) -> bool:
	return state != null and bag_used(state) >= state.inventory_capacity


static func filter_stacks(
	state: CultivationState,
	adventure: AdventureConfig,
	kind: String
) -> Array[ItemStack]:
	var found: Array[ItemStack] = []
	if state == null:
		return found
	for stack in state.inventory:
		if state.equipped.contains_uid(stack.uid):
			continue
		if kind.is_empty() or kind == "all":
			found.append(stack)
			continue
		var item := adventure.item_by_id(stack.item_id) if adventure != null else null
		if item != null and item.kind == kind:
			found.append(stack)
	return found


static func add_item(
	state: CultivationState,
	config: AdventureConfig,
	item: ItemDef,
	count: int,
	policy: String
) -> Dictionary:
	var result := {"added": 0, "skipped": 0, "discarded": ""}
	if state == null or item == null or count <= 0:
		return result
	var remaining := count
	if item.stackable:
		for stack in state.inventory:
			if stack.item_id != item.id or stack.count >= MAX_STACK:
				continue
			var room := MAX_STACK - stack.count
			var take := mini(room, remaining)
			stack.count += take
			remaining -= take
			result.added = int(result.added) + take
			if remaining <= 0:
				return result
	while remaining > 0:
		if not is_full(state):
			var stack := ItemStack.new()
			state.next_item_uid += 1
			stack.uid = state.next_item_uid
			stack.item_id = item.id
			stack.count = 1 if not item.stackable else mini(remaining, MAX_STACK)
			state.inventory.append(stack)
			remaining -= stack.count
			result.added = int(result.added) + stack.count
			continue
		if policy == GameSettings.POLICY_DISCARD_LOWEST:
			var discarded := _discard_lowest(state, config)
			if discarded.is_empty():
				result.skipped = int(result.skipped) + remaining
				return result
			result.discarded = discarded
			continue
		result.skipped = int(result.skipped) + remaining
		return result
	return result


static func discard(state: CultivationState, uid: int) -> bool:
	var stack := find_stack(state, uid)
	if stack == null or stack.locked:
		return false
	if state.equipped.contains_uid(uid):
		return false
	state.inventory = state.inventory.filter(func(item: ItemStack) -> bool:
		return item.uid != uid
	)
	return true


static func toggle_lock(state: CultivationState, uid: int) -> bool:
	var stack := find_stack(state, uid)
	if stack == null:
		return false
	stack.locked = not stack.locked
	return true


static func inspect_text(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	stack: ItemStack
) -> String:
	if state == null or adventure == null or stack == null:
		return ""
	var item := adventure.item_by_id(stack.item_id)
	if item == null:
		return ""
	if item.is_equipment():
		return _inspect_equipment(state, idle, adventure, stack, item)
	if item.is_skill_book():
		return _inspect_skill_book(state, idle, adventure, item, stack)
	return _inspect_stackable(item, stack)


static func _inspect_equipment(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	stack: ItemStack,
	item: ItemDef
) -> String:
	var current := CombatRules.player_stats(state, idle, adventure)
	var preview_loadout := EquipmentLoadout.from_dictionary(state.equipped.to_dictionary())
	preview_loadout.set_uid(item.slot, stack.uid)
	var preview := CombatRules.player_stats_with_loadout(state, idle, adventure, preview_loadout)
	var worn_stack := find_stack(state, state.equipped.uid_for(item.slot))
	var worn := adventure.item_by_id(worn_stack.item_id) if worn_stack != null else null
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s · %s · %s" % [
		QualityId.display_name(item.quality),
		EquipSlot.display_name(item.slot),
		item.kind_display_name(),
	])
	if not item.affixes.is_empty():
		lines.append("词条  %s" % " · ".join(item.affixes))
	var live := item.to_stats(stack)
	var extra: PackedStringArray = PackedStringArray()
	if stack.merge_level > 0:
		extra.append("合+%d" % stack.merge_level)
	if stack.tempered:
		extra.append("已温养")
	if not extra.is_empty():
		lines.append(" · ".join(extra))
	lines.append("攻%s  防%s  速%s  气血%s" % [
		CultivationFormat.amount(live.attack),
		CultivationFormat.amount(live.defense),
		CultivationFormat.amount(live.speed),
		CultivationFormat.amount(live.hp),
	])
	lines.append("装备战力 %s" % CultivationFormat.amount(item.gear_power(stack)))
	if find_merge_partner(state, stack.uid) != null:
		lines.append("可与另一件同名同阶合并。")
	var realm := idle.realm_by_id(state.realm_id) if idle != null else null
	if state.equipped.contains_uid(stack.uid):
		lines.append("正在穿戴。")
	elif realm != null and realm.order < item.min_realm_order:
		lines.append("境界不足，无法穿戴。")
	else:
		lines.append("可以穿戴。")
	if worn == null:
		lines.append("该槽位空着。")
	else:
		lines.append("已穿 %s  攻%s 防%s 速%s" % [
			worn.display_name,
			CultivationFormat.amount(worn.attack),
			CultivationFormat.amount(worn.defense),
			CultivationFormat.amount(worn.speed),
		])
	lines.append("换上后 攻%s 防%s 速%s  战力 %s → %s（%s）" % [
		_signed(preview.attack - current.attack),
		_signed(preview.defense - current.defense),
		_signed(preview.speed - current.speed),
		CultivationFormat.amount(current.power()),
		CultivationFormat.amount(preview.power()),
		_signed(preview.power() - current.power()),
	])
	return "\n".join(lines)


static func _inspect_stackable(item: ItemDef, stack: ItemStack) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("%s · %s" % [QualityId.display_name(item.quality), item.kind_display_name()])
	if stack.count > 1:
		lines.append("持有 ×%d" % stack.count)
	if not item.description.is_empty():
		lines.append(item.description)
	elif item.is_pill():
		if item.id == "pill_qi_0":
			lines.append("服后 10 分钟，修为效率 ×1.15。")
		elif item.id == "pill_body_0":
			lines.append("服后 10 分钟，防御 ×1.20。")
		else:
			lines.append("可服用，时效十分钟。")
	elif item.is_material():
		lines.append("可温养一件未穿装备一次：3 灵草 + 1 兽骨。不改品质。")
	else:
		lines.append(item.display_name)
	return "\n".join(lines)


static func _inspect_skill_book(
	state: CultivationState,
	idle: IdleConfig,
	adventure: AdventureConfig,
	item: ItemDef,
	stack: ItemStack
) -> String:
	var skill := adventure.skill_by_id(item.skill_id)
	if skill == null:
		return "残页已模糊。"
	var current := CombatRules.player_stats(state, idle, adventure)
	var lines: PackedStringArray = PackedStringArray()
	var realm := idle.realm_by_id(state.realm_id) if idle != null else null
	var rank := state.skill_rank_of(skill.id)
	if rank >= 2:
		lines.append("已小成，再参悟不会加强。")
	elif rank == 1:
		lines.append("已入门。再交 2 本可小成。")
	elif realm != null and realm.order < skill.min_realm_order:
		lines.append("境界不足，无法参悟。")
	else:
		lines.append("可以参悟入门。")
	if stack.count > 1:
		lines.append("持有 ×%d" % stack.count)
	var preview := CombatRules.player_stats(state, idle, adventure)
	if rank <= 0:
		preview.add(skill.to_stats(1))
	elif rank == 1:
		preview.add(skill.to_stats(2))
		preview.attack -= skill.attack
		preview.defense -= skill.defense
		preview.hp -= skill.hp
	lines.append("学后 攻%s 防%s 血%s  战力 %s → %s（%s）" % [
		_signed(preview.attack - current.attack),
		_signed(preview.defense - current.defense),
		_signed(preview.hp - current.hp),
		CultivationFormat.amount(current.power()),
		CultivationFormat.amount(preview.power()),
		_signed(preview.power() - current.power()),
	])
	return "\n".join(lines)


static func _signed(value: float) -> String:
	if is_zero_approx(value):
		return "持平"
	var prefix := "+" if value > 0.0 else ""
	return "%s%s" % [prefix, CultivationFormat.amount(value)]


static func find_merge_partner(state: CultivationState, uid: int) -> ItemStack:
	var stack := find_stack(state, uid)
	if stack == null or state == null:
		return null
	if state.equipped.contains_uid(uid) or stack.merge_level >= ItemStack.MAX_MERGE:
		return null
	for other in state.inventory:
		if other.uid == uid:
			continue
		if other.item_id != stack.item_id or other.merge_level != stack.merge_level:
			continue
		if state.equipped.contains_uid(other.uid):
			continue
		return other
	return null


static func merge(state: CultivationState, uid: int) -> bool:
	var stack := find_stack(state, uid)
	var partner := find_merge_partner(state, uid)
	if stack == null or partner == null:
		return false
	stack.merge_level = mini(stack.merge_level + 1, ItemStack.MAX_MERGE)
	state.inventory = state.inventory.filter(func(item: ItemStack) -> bool:
		return item.uid != partner.uid
	)
	return true


static func count_item(state: CultivationState, item_id: String) -> int:
	var total := 0
	if state == null:
		return 0
	for stack in state.inventory:
		if stack.item_id == item_id:
			total += stack.count
	return total


static func consume_count(state: CultivationState, item_id: String, amount: int) -> bool:
	if amount <= 0 or count_item(state, item_id) < amount:
		return false
	var remaining := amount
	var kept: Array[ItemStack] = []
	for stack in state.inventory:
		if remaining <= 0 or stack.item_id != item_id:
			kept.append(stack)
			continue
		if stack.count > remaining:
			stack.count -= remaining
			remaining = 0
			kept.append(stack)
		else:
			remaining -= stack.count
	if remaining > 0:
		return false
	state.inventory = kept
	return true


static func temper(state: CultivationState, uid: int) -> bool:
	var stack := find_stack(state, uid)
	if stack == null or stack.tempered or state.equipped.contains_uid(uid):
		return false
	if count_item(state, "mat_spirit_grass") < 3 or count_item(state, "mat_beast_bone") < 1:
		return false
	if not consume_count(state, "mat_spirit_grass", 3):
		return false
	if not consume_count(state, "mat_beast_bone", 1):
		return false
	stack.tempered = true
	return true


static func append_log(state: CultivationState, line: String) -> void:
	var cleaned := line.strip_edges()
	if state == null or cleaned.is_empty() or not state.settings.battle_log_enabled:
		return
	state.battle_log.append(cleaned)
	if state.battle_log.size() > MAX_LOG:
		state.battle_log = state.battle_log.slice(state.battle_log.size() - MAX_LOG)


static func _discard_lowest(state: CultivationState, config: AdventureConfig) -> String:
	var chosen: ItemStack = null
	var chosen_rank := 99
	for stack in state.inventory:
		if stack.locked or state.equipped.contains_uid(stack.uid):
			continue
		var item := config.item_by_id(stack.item_id) if config != null else null
		var rank := QualityId.rank(item.quality) if item != null else 0
		if rank < 0:
			rank = 0
		if chosen == null or rank < chosen_rank:
			chosen = stack
			chosen_rank = rank
	if chosen == null:
		return ""
	var name := chosen.item_id
	if config != null:
		var item := config.item_by_id(chosen.item_id)
		if item != null:
			name = item.display_name
	state.inventory = state.inventory.filter(func(item: ItemStack) -> bool:
		return item.uid != chosen.uid
	)
	return name
