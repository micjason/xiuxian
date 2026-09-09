class_name CultivationSession
extends RefCounted

signal state_changed
signal offline_settled(result: SettlementResult)
signal breakthrough_succeeded(from_name: String, to_name: String, new_rate: float)

const CONFIG_PATH := "res://resources/config/idle_rules.json"
const ONLINE_CAP_SECONDS := 0

var time_service: TimeService
var config: IdleConfig
var save_service: SaveService
var state: CultivationState
var app_version: String
var last_offline_result: SettlementResult
var journal := CultivationJournal.new()


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
		journal.add("踏入修行，当前境界为 %s。" % config.starting_realm().display_name)
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
	if last_offline_result.clock_rewound:
		journal.add("检测到时间回拨，未扣除修为。")
		offline_settled.emit(last_offline_result)
		return
	if last_offline_result.gained > 0.0:
		var line := "闭关归来，获得修为 %s，结算 %s" % [
			CultivationFormat.amount(last_offline_result.gained),
			CultivationFormat.duration_hours(last_offline_result.applied_seconds),
		]
		if last_offline_result.hit_cap:
			line += "，已顶到 %s 上限" % CultivationFormat.duration_hours(config.offline_cap_seconds)
		journal.add(line)
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
