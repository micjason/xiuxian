extends Control

const DATA_MARKER_PATH := "user://demo_install_marker.txt"
const TICK_SECONDS := 1.0

@onready var version_label: Label = %VersionLabel
@onready var upgrade_badge: Label = %UpgradeBadge
@onready var realm_label: Label = %RealmLabel
@onready var cultivation_label: Label = %CultivationLabel
@onready var rate_label: Label = %RateLabel
@onready var next_cost_label: Label = %NextCostLabel
@onready var cultivation_progress: ProgressBar = %CultivationProgress
@onready var breakthrough_button: Button = %BreakthroughButton
@onready var offline_label: Label = %OfflineLabel
@onready var status_label: Label = %StatusLabel
@onready var download_progress: ProgressBar = %DownloadProgress
@onready var check_button: Button = %CheckButton
@onready var install_button: Button = %InstallButton
@onready var update_dialog: ConfirmationDialog = %UpdateDialog
@onready var offline_dialog: AcceptDialog = %OfflineDialog
@onready var update_service: UpdateService = %UpdateService

var _session: CultivationSession
var _tick: Timer


func _ready() -> void:
	_session = CultivationSession.new()
	_session.state_changed.connect(_refresh_cultivation)
	_session.offline_settled.connect(_on_offline_settled)
	if not _session.start():
		status_label.text = "修炼配置读取失败。"
		return

	_tick = Timer.new()
	_tick.wait_time = TICK_SECONDS
	_tick.autostart = true
	_tick.timeout.connect(_session.tick_online)
	add_child(_tick)
	tree_exiting.connect(_session.tick_online)

	breakthrough_button.pressed.connect(_on_breakthrough_pressed)
	check_button.pressed.connect(update_service.check_for_update)
	install_button.pressed.connect(update_service.install_downloaded_update)
	update_dialog.confirmed.connect(update_service.download_update)
	update_service.status_changed.connect(_on_status_changed)
	update_service.update_available.connect(_on_update_available)
	update_service.no_update.connect(_on_no_update)
	update_service.download_progress_changed.connect(_on_download_progress_changed)
	update_service.download_ready.connect(_on_download_ready)
	update_service.failed.connect(_on_update_failed)

	var current_version := update_service.get_current_version()
	version_label.text = "版本 %s · %s" % [current_version, _load_or_create_data_marker()]
	upgrade_badge.visible = AppVersion.is_newer(current_version, "0.1.1")
	download_progress.value = 0.0
	_refresh_cultivation()
	get_tree().create_timer(0.8).timeout.connect(update_service.check_for_update)


func _refresh_cultivation() -> void:
	var realm := _session.current_realm()
	if realm == null or _session.state == null:
		return
	realm_label.text = realm.display_name
	cultivation_label.text = "修为 %s" % CultivationFormat.amount(_session.state.cultivation)
	rate_label.text = "修炼效率 %s" % CultivationFormat.rate(realm.gain_per_second)
	cultivation_progress.value = _session.progress() * 100.0
	if _session.next_realm() == null:
		next_cost_label.text = "已达当前最高境界，仍可继续积累修为。"
		breakthrough_button.disabled = true
		breakthrough_button.text = "已圆满"
	else:
		next_cost_label.text = "突破消耗 %s · 下一境界 %s" % [
			CultivationFormat.amount(realm.breakthrough_cost),
			_session.next_realm().display_name,
		]
		breakthrough_button.disabled = not _session.can_breakthrough()
		breakthrough_button.text = "突破"


func _on_breakthrough_pressed() -> void:
	if _session.try_breakthrough():
		offline_label.text = "突破成功，修炼效率提升。"


func _on_offline_settled(result: SettlementResult) -> void:
	if result.clock_rewound:
		offline_label.text = "检测到时间回拨，未扣除修为。"
		return
	if result.gained <= 0.0:
		offline_label.text = ""
		return
	var message := "闭关归来，获得修为 %s。" % CultivationFormat.amount(result.gained)
	if result.hit_cap:
		message += "本次只计算了 %s。" % CultivationFormat.duration_hours(
			_session.config.offline_cap_seconds
		)
	offline_label.text = message
	offline_dialog.dialog_text = message
	offline_dialog.popup_centered(Vector2i(820, 480))


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _on_update_available(info: Dictionary) -> void:
	check_button.disabled = false
	var notes := str(info.get("release_notes", ""))
	if notes.is_empty():
		notes = "包含新的可玩内容。"
	update_dialog.dialog_text = "新版本：%s\n\n%s\n\n是否立即下载？" % [
		str(info.get("version", "")),
		notes,
	]
	update_dialog.popup_centered(Vector2i(820, 620))


func _on_no_update(_version: String) -> void:
	check_button.disabled = false


func _on_download_progress_changed(progress: float) -> void:
	check_button.disabled = true
	download_progress.value = progress * 100.0


func _on_download_ready(_path: String) -> void:
	check_button.disabled = false
	install_button.visible = true
	update_service.install_downloaded_update()


func _on_update_failed(_message: String) -> void:
	check_button.disabled = false


func _load_or_create_data_marker() -> String:
	if FileAccess.file_exists(DATA_MARKER_PATH):
		var saved_marker := FileAccess.get_file_as_string(DATA_MARKER_PATH).strip_edges()
		if not saved_marker.is_empty():
			return saved_marker + "（已保留）"
	var marker := "首次安装 %s" % update_service.get_current_version()
	var file := FileAccess.open(DATA_MARKER_PATH, FileAccess.WRITE)
	if file == null:
		return "无法写入"
	file.store_string(marker)
	return marker
