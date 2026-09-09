class_name CultivationRules
extends RefCounted

const COST_EPSILON := 0.0001


static func apply_elapsed(
	state: CultivationState,
	gain_per_second: float,
	elapsed_seconds: int,
	cap_seconds: int
) -> SettlementResult:
	var result := SettlementResult.new()
	result.clock_rewound = elapsed_seconds < 0
	var raw_seconds: int = maxi(elapsed_seconds, 0)
	result.hit_cap = cap_seconds > 0 and raw_seconds > cap_seconds
	result.applied_seconds = cap_seconds if result.hit_cap else raw_seconds
	result.gained = gain_per_second * float(result.applied_seconds)
	state.cultivation = maxf(state.cultivation + result.gained, 0.0)
	return result


static func can_breakthrough(state: CultivationState, realm: RealmDef) -> bool:
	if state == null or realm == null or not realm.has_next():
		return false
	return state.cultivation + COST_EPSILON >= realm.breakthrough_cost


static func breakthrough(
	state: CultivationState,
	current: RealmDef,
	next_realm: RealmDef
) -> bool:
	if next_realm == null or not can_breakthrough(state, current):
		return false
	if current.next_id != next_realm.id:
		return false
	state.cultivation = maxf(state.cultivation - current.breakthrough_cost, 0.0)
	state.realm_id = next_realm.id
	return true


static func progress_to_next(state: CultivationState, realm: RealmDef) -> float:
	if state == null or realm == null or not realm.has_next():
		return 1.0
	if realm.breakthrough_cost <= 0.0:
		return 0.0
	return clampf(state.cultivation / realm.breakthrough_cost, 0.0, 1.0)
