class_name CultivationSession
extends RefCounted

signal state_changed
signal offline_settled(result: SettlementResult)

const CONFIG_PATH := "res://resources/config/idle_rules.json"
const ONLINE_CAP_SECONDS := 0

var time_service: TimeService
var config: IdleConfig
var save_service: SaveService
var state: CultivationState
var app_version: String
var last_offline_result: SettlementResult


func _init(
	clock: TimeService = null,
	save: SaveService = null,
	rules: IdleConfig = null,
	version: String = ""
) -> void:
	time_service = clock if clock != null else TimeService.new()
	save_service = save if save != null else SaveService.new()
	config = rules
	app_version = version if not version.is_empty() else _read_app_version()


func start() -> bool:
	if config == null:
		config = IdleConfig.from_resource(CONFIG_PATH)
	if config == null or config.starting_realm() == null:
		push_error("Idle config is missing or invalid.")
		return false

	state = save_service.load_state()
	if state == null or config.realm_by_id(state.realm_id) == null:
		state = _new_state()
	else:
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
	state.last_settled_unix = time_service.now_unix()
	_persist()
	state_changed.emit()


func try_breakthrough() -> bool:
	var current := current_realm()
	var next_realm := config.next_realm(current)
	if not CultivationRules.breakthrough(state, current, next_realm):
		return false
	_persist()
	state_changed.emit()
	return true


func current_realm() -> RealmDef:
	return config.realm_by_id(state.realm_id) if state != null and config != null else null


func next_realm() -> RealmDef:
	return config.next_realm(current_realm())


func can_breakthrough() -> bool:
	return CultivationRules.can_breakthrough(state, current_realm())


func progress() -> float:
	return CultivationRules.progress_to_next(state, current_realm())


func _settle_offline() -> void:
	var realm := current_realm()
	var elapsed := time_service.elapsed_seconds(state.last_settled_unix)
	last_offline_result = CultivationRules.apply_elapsed(
		state,
		realm.gain_per_second,
		elapsed,
		config.offline_cap_seconds
	)
	state.last_settled_unix = time_service.now_unix()
	if last_offline_result.gained > 0.0 or last_offline_result.clock_rewound:
		offline_settled.emit(last_offline_result)


func _new_state() -> CultivationState:
	var created := CultivationState.new()
	created.cultivation = 0.0
	created.realm_id = config.starting_realm().id
	created.last_settled_unix = time_service.now_unix()
	return created


func _persist() -> void:
	save_service.save_state(state, app_version, app_version, time_service.now_unix())


func _read_app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
