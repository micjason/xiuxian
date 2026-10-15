extends SceneTree
## 把 MainTheme.make() 导出为 res://resources/theme/xiuxian_theme.tres。
## 修改 ui_tokens.gd 或 main_theme.gd 后运行：
##   godot --headless --path game --script res://scripts/dev/export_theme.gd


func _initialize() -> void:
	var theme := MainTheme.make()
	var error := ResourceSaver.save(theme, MainTheme.THEME_PATH)
	if error != OK:
		push_error("导出主题失败：%s" % error_string(error))
		quit(1)
		return
	print("已导出 %s" % MainTheme.THEME_PATH)
	quit()
