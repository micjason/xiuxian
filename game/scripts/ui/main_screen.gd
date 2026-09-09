extends Control

const DATA_MARKER_PATH := "user://demo_install_marker.txt"
const TICK_SECONDS := 1.0

@onready var version_label: Label = %VersionLabel
@onready var upgrade_badge: Label = %UpgradeBadge
@onready var realm_label: Label = %RealmLabel
@onready var realm_path: Label = %RealmPath
@onready var cultivation_label: Label = %CultivationLabel
@onready var rate_label: Label = %RateLabel
@onready var next_cost_label: Label = %NextCostLabel
@onready var next_realm_label: Label = %NextRealmLabel
@onready var cultivation_progress: ProgressBar = %CultivationProgress
@onready var breakthrough_button: Button = %BreakthroughButton
@onready var breakthrough_banner: Label = %BreakthroughBanner
@onready var journal_label: Label = %JournalLabel
@onready var offline_label: Label = %OfflineLabel
@onready var status_label: Label = %StatusLabel
@onready var download_progress: ProgressBar = %DownloadProgress
@onready var check_button: Button = %CheckButton
@onready var install_button: Button = %InstallButton
@onready var update_dialog: ConfirmationDialog = %UpdateDialog
@onready var offline_dialog: AcceptDialog = %OfflineDialog
@onready var update_service: UpdateService = %UpdateService
@onready var flash: ColorRect = %Flash
@onready var seal_ring: Panel = %SealRing
@onready var seal_inner: Panel = %SealInner
@onready var progress_hint: Label = %ProgressHint
@onready var cultivation_card: PanelContainer = %CultivationCard
@onready var stats_card: PanelContainer = %StatsCard
@onready var journal_card: PanelContainer = %JournalCard
@onready var update_card: PanelContainer = %UpdateCard

var _session: CultivationSession
var _tick: Timer
var _banner_tween: Tween
var _ready_pulse: Tween


func _ready() -> void:
	theme = MainTheme.make()
	cultivation_card.add_theme_stylebox_override("panel", MainTheme.hero_panel())
	stats_card.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	journal_card.add_theme_stylebox_override("panel", MainTheme.inner_panel())
	update_card.add_theme_stylebox_override("panel", MainTheme.footer_panel())
	seal_ring.add_theme_stylebox_override("panel", MainTheme.seal_ring())
	seal_inner.add_theme_stylebox_override("panel", MainTheme.seal_inner())
	_style_secondary_button(check_button)
	_style_secondary_button(install_button)
	download_progress.visible = false

	_session = CultivationSession.new()
	_session.state_changed.connect(_refresh_cultivation)
	_session.offline_settled.connect(_on_offline_settled)
	_session.breakthrough_succeeded.connect(_on_breakthrough_succeeded)
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
	upgrade_badge.visible = AppVersion.is_newer(current_version, "0.1.3")
	download_progress.value = 0.0
	breakthrough_banner.visible = false
	flash.modulate.a = 0.0
	realm_label.resized.connect(func() -> void:
		realm_label.pivot_offset = realm_label.size * 0.5
	)
	_start_seal_pulse()
	_refresh_cultivation()
	get_tree().create_timer(0.8).timeout.connect(update_service.check_for_update)


func _refresh_cultivation() -> void:
	var realm := _session.current_realm()
	if realm == null or _session.state == null:
		return
	realm_label.text = realm.display_name
	realm_path.text = _session.config.display_path(realm)
	cultivation_label.text = CultivationFormat.amount(_session.state.cultivation)
	rate_label.text = CultivationFormat.rate(realm.gain_per_second)
	cultivation_progress.value = _session.progress() * 100.0
	journal_label.text = _session.journal.as_text()
	var next_realm := _session.next_realm()
	if next_realm == null:
		next_cost_label.text = "—"
		next_realm_label.text = "已至顶峰"
		progress_hint.text = "已至当前示意表最高境界"
		breakthrough_button.disabled = true
		breakthrough_button.text = "已圆满"
		cultivation_progress.add_theme_stylebox_override("fill", MainTheme.progress_fill(false))
		_set_ready_pulse(false)
	else:
		next_cost_label.text = CultivationFormat.amount(realm.breakthrough_cost)
		next_realm_label.text = next_realm.display_name
		var remaining := maxf(0.0, realm.breakthrough_cost - _session.state.cultivation)
		if remaining <= 0.001:
			progress_hint.text = "修为已足，可突破至 %s" % next_realm.display_name
		else:
			progress_hint.text = "距突破还需 %s" % CultivationFormat.amount(remaining)
		var can_break := _session.can_breakthrough()
		breakthrough_button.disabled = not can_break
		breakthrough_button.text = "突破境界" if can_break else "修为不足"
		cultivation_progress.add_theme_stylebox_override("fill", MainTheme.progress_fill(can_break))
		_set_ready_pulse(can_break)


func _on_breakthrough_pressed() -> void:
	_session.try_breakthrough()


func _on_breakthrough_succeeded(from_name: String, to_name: String, new_rate: float) -> void:
	breakthrough_banner.text = "突破成功  %s → %s\n修炼效率提升至 %s" % [
		from_name,
		to_name,
		CultivationFormat.rate(new_rate),
	]
	breakthrough_banner.visible = true
	offline_label.text = ""
	_play_breakthrough_flash()
	_refresh_cultivation()


func _style_secondary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", MainTheme.ghost_button())
	button.add_theme_stylebox_override("hover", MainTheme._box(Color(0.14, 0.16, 0.13, 1), MainTheme.GOLD, 1, 20, 0, 14, 12))
	button.add_theme_stylebox_override("pressed", MainTheme._box(Color(0.1, 0.12, 0.1, 1), Color(0.5, 0.42, 0.22, 1), 1, 20, 0, 14, 12))
	button.add_theme_color_override("font_color", MainTheme.GOLD)
	button.add_theme_color_override("font_hover_color", MainTheme.IVORY)
	button.add_theme_color_override("font_pressed_color", MainTheme.GOLD)


func _set_ready_pulse(enabled: bool) -> void:
	if enabled:
		if _ready_pulse != null:
			return
		_ready_pulse = create_tween()
		_ready_pulse.set_loops()
		_ready_pulse.tween_property(breakthrough_button, "modulate", Color(1.12, 1.08, 0.92, 1), 0.7)
		_ready_pulse.tween_property(breakthrough_button, "modulate", Color.WHITE, 0.7)
		return
	if _ready_pulse != null:
		_ready_pulse.kill()
		_ready_pulse = null
	breakthrough_button.modulate = Color.WHITE


func _start_seal_pulse() -> void:
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(seal_ring, "modulate:a", 0.55, 1.8).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(seal_ring, "modulate:a", 1.0, 1.8).set_trans(Tween.TRANS_SINE)


func _play_breakthrough_flash() -> void:
	if _banner_tween != null:
		_banner_tween.kill()
	flash.modulate = Color(MainTheme.GOLD.r, MainTheme.GOLD.g, MainTheme.GOLD.b, 0.0)
	realm_label.modulate = MainTheme.GOLD
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(flash, "modulate:a", 0.28, 0.12)
	_banner_tween.tween_property(realm_label, "scale", Vector2(1.08, 1.08), 0.12)
	_banner_tween.chain()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(flash, "modulate:a", 0.0, 0.45)
	_banner_tween.tween_property(realm_label, "scale", Vector2.ONE, 0.35)
	_banner_tween.tween_property(realm_label, "modulate", MainTheme.JADE, 0.45)


func _on_offline_settled(result: SettlementResult) -> void:
	offline_label.text = OfflineCopy.banner(result)
	var message := OfflineCopy.dialog(result, _session.config.offline_cap_seconds)
	if message.is_empty():
		_refresh_cultivation()
		return
	offline_dialog.dialog_text = message
	offline_dialog.popup_centered(Vector2i(780, 460))
	_refresh_cultivation()


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
	update_dialog.popup_centered(Vector2i(780, 520))


func _on_no_update(_version: String) -> void:
	check_button.disabled = false


func _on_download_progress_changed(progress: float) -> void:
	check_button.disabled = true
	download_progress.visible = true
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
