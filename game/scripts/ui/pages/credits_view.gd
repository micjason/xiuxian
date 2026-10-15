class_name CreditsView
extends RefCounted
## 致谢与版本弹层：列出所有第三方素材的名称、作者、授权（数据来自 res://assets/credits.json，
## 与仓库根目录的 ASSETS_LICENSES.md 同步）。需要署名的素材（CC BY）在这里显示署名。

const CREDITS_PATH := "res://assets/credits.json"


static func load_credits() -> Dictionary:
	if not FileAccess.file_exists(CREDITS_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func show_credits(popup: GamePopup) -> void:
	popup.clear_content()
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	popup.body.add_child(UiKit.label("修仙  %s" % version, UiTokens.FS_BODY_L, UiTokens.TEXT))
	var data := load_credits()
	if data.is_empty():
		popup.body.add_child(UiKit.wrap_label("致谢文件缺失：%s" % CREDITS_PATH, UiTokens.FS_CAPTION, UiTokens.DANGER))
	else:
		popup.body.add_child(UiKit.wrap_label(str(data.get("intro", "")), UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
		for group in data.get("groups", []):
			var card := UiKit.card(str(group.get("title", "")))
			popup.body.add_child(card.panel)
			var note := str(group.get("note", ""))
			if not note.is_empty():
				card.body.add_child(UiKit.wrap_label(note, UiTokens.FS_MICRO, UiTokens.WARNING))
			for line in group.get("lines", []):
				card.body.add_child(UiKit.wrap_label(str(line), UiTokens.FS_MICRO, UiTokens.TEXT))
	popup.set_actions([{"text": "关闭", "variation": MainTheme.VAR_PRIMARY}])
	popup.open_popup("致谢与版本")
