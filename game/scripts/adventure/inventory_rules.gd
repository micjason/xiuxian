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


static func is_full(state: CultivationState) -> bool:
	return state != null and state.inventory.size() >= state.inventory_capacity


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
