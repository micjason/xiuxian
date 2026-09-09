@tool
extends EditorPlugin

var _export_plugin: XiuxianAndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = XiuxianAndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class XiuxianAndroidExportPlugin extends EditorExportPlugin:
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid


	func _get_android_libraries(
		_platform: EditorExportPlatform,
		debug: bool
	) -> PackedStringArray:
		var variant := "debug" if debug else "release"
		return PackedStringArray([
			"xiuxian_android_updater/bin/%s/XiuxianUpdater-%s.aar" % [variant, variant]
		])


	func _get_name() -> String:
		return "XiuxianUpdater"
