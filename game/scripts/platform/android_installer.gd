class_name AndroidInstaller
extends RefCounted

const PLUGIN_NAME := "XiuxianUpdater"

var _plugin: Object


func _init() -> void:
	if Engine.has_singleton(PLUGIN_NAME):
		_plugin = Engine.get_singleton(PLUGIN_NAME)


func get_version_name() -> String:
	if _plugin != null:
		return str(_plugin.getVersionName())
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func get_version_code() -> int:
	if _plugin != null:
		return int(_plugin.getVersionCode())
	return 0


func is_supported() -> bool:
	return OS.has_feature("android") and _plugin != null


func can_request_package_installs() -> bool:
	return is_supported() and bool(_plugin.canRequestPackageInstalls())


func request_install_permission() -> void:
	if is_supported():
		_plugin.requestInstallPermission()


func install_apk(project_path: String) -> bool:
	if not is_supported():
		return false
	var absolute_path := ProjectSettings.globalize_path(project_path)
	return bool(_plugin.installApk(absolute_path))
