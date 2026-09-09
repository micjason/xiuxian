extends Control

const DATA_MARKER_PATH := "user://demo_install_marker.txt"

@onready var version_label: Label = %VersionLabel
@onready var upgrade_badge: Label = %UpgradeBadge
@onready var data_marker_label: Label = %DataMarkerLabel
@onready var status_label: Label = %StatusLabel
@onready var download_progress: ProgressBar = %DownloadProgress
@onready var check_button: Button = %CheckButton
@onready var install_button: Button = %InstallButton
@onready var update_dialog: ConfirmationDialog = %UpdateDialog
@onready var update_service: UpdateService = %UpdateService


func _ready() -> void:
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
	version_label.text = "当前版本：%s" % current_version
	upgrade_badge.visible = AppVersion.is_newer(current_version, "0.1.0")
	data_marker_label.text = "本地数据标记：%s" % _load_or_create_data_marker()
	download_progress.value = 0.0
	get_tree().create_timer(0.8).timeout.connect(update_service.check_for_update)


func _on_status_changed(message: String) -> void:
	status_label.text = message


func _on_update_available(info: Dictionary) -> void:
	check_button.disabled = false
	var notes := str(info.get("release_notes", ""))
	if notes.is_empty():
		notes = "包含新的 Demo 页面版本。"
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
