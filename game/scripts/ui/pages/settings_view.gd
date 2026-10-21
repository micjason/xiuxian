class_name SettingsView
extends RefCounted
## 设置面板（点左上角头像打开；屏幕正中的通用弹窗，正式美术之后换皮）：
## 账号信息、音乐 / 音效开关（本机保存，LocalSettings）、版本号 + 检查更新、暂未开放的入口（点了提示）、素材致谢、退出登录（二次确认）。
## 面板只负责界面，具体动作发信号给外壳（play_screen）处理。

signal logout_confirmed
signal check_update_requested
signal locked_pressed(feature: String)
signal credits_requested

## 暂未开放的入口（点了提示「功能暂未开放」）。
const LOCKED_ROWS := ["修改密码", "绑定手机", "兑换码", "客服", "用户协议与隐私政策"]
const LOCKED_TEXT := LockedFeature.TEXT
const LINK_HEIGHT := 100  # 比 H_TOUCH 矮一点，一屏放得下；仍有 ≈38dp

var popup: GamePopup
var _info: Dictionary = {}


func _init(target_popup: GamePopup) -> void:
	popup = target_popup


## info: {username, playerId, realm, version, versionCode, server}
func open(info: Dictionary) -> void:
	_info = info
	popup.clear_content()
	popup.set_dim_closes(true)
	var account := UiKit.card("账号")
	account.panel.name = "SettingsAccount"
	popup.body.add_child(account.panel)
	account.body.add_child(_pair("账号", _text(info.get("username", ""), "未知")))
	account.body.add_child(_pair("玩家 ID", _text(info.get("playerId", ""), "—")))
	account.body.add_child(_pair("境界", _text(info.get("realm", ""), "—")))
	var server := _text(info.get("server", ""), "")
	if not server.is_empty():
		account.body.add_child(_pair("服务器", server))
	var sound := UiKit.card("声音")
	popup.body.add_child(sound.panel)
	sound.body.add_child(_toggle_row("MusicToggle", "音乐", LocalSettings.music_on(), LocalSettings.set_music_on))
	sound.body.add_child(_toggle_row("SfxToggle", "音效", LocalSettings.sfx_on(), LocalSettings.set_sfx_on))
	var about := UiKit.card("版本")
	popup.body.add_child(about.panel)
	var version_row := UiKit.hbox(UiTokens.SP_2)
	var version := UiKit.label(version_text(info), UiTokens.FS_BODY, UiTokens.TEXT)
	version.name = "SettingsVersion"
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	version_row.add_child(version)
	var check := UiKit.button("检查更新", MainTheme.VAR_PRIMARY)
	check.name = "CheckUpdateButton"
	check.size_flags_horizontal = Control.SIZE_SHRINK_END
	check.custom_minimum_size.x = 240
	check.pressed.connect(func() -> void: check_update_requested.emit())
	version_row.add_child(check)
	about.body.add_child(version_row)
	var more := UiKit.card("更多")
	popup.body.add_child(more.panel)
	for feature in LOCKED_ROWS:
		var row := _link_row(feature)
		row.name = "Locked_%s" % feature
		row.pressed.connect(func() -> void: locked_pressed.emit(feature))
		more.body.add_child(row)
	var credits := _link_row("素材致谢")
	credits.name = "CreditsRow"
	credits.pressed.connect(func() -> void: credits_requested.emit())
	more.body.add_child(credits)
	popup.set_actions([
		{"text": "退出登录", "variation": MainTheme.VAR_DANGER, "close": false, "callback": confirm_logout},
		{"text": "关闭", "variation": MainTheme.VAR_SECONDARY},
	])
	popup.actions.get_child(0).name = "LogoutButton"
	popup.open_popup("设置", true)


## 退出登录二次确认：取消回到设置面板，确定才真的退出。
func confirm_logout() -> void:
	popup.clear_content()
	popup.set_dim_closes(false)
	var text := UiKit.wrap_label("退出后需要重新登录，可以登录别的账号。\n修为都存在服务器上，不会丢。", UiTokens.FS_BODY, UiTokens.TEXT)
	text.name = "LogoutConfirmText"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.body.add_child(text)
	popup.set_actions([
		{"text": "取消", "variation": MainTheme.VAR_SECONDARY, "close": false, "callback": func() -> void: open(_info)},
		{"text": "退出登录", "variation": MainTheme.VAR_DANGER, "callback": func() -> void:
			popup.set_dim_closes(true)
			logout_confirmed.emit()},
	])
	popup.open_popup("确定退出登录？", true)


static func version_text(info: Dictionary) -> String:
	var version := _text(info.get("version", ""), "—")
	var code := int(info.get("versionCode", 0))
	return "当前版本 %s（%d）" % [version, code] if code > 0 else "当前版本 %s" % version


static func _text(value: Variant, fallback: String) -> String:
	var text := "" if value == null else str(value).strip_edges()
	return fallback if text.is_empty() else text


func _pair(key: String, value: String) -> Control:
	var row := UiKit.hbox(UiTokens.SP_2)
	var left := UiKit.label(key, UiTokens.FS_BODY, UiTokens.TEXT_MUTED)
	left.custom_minimum_size.x = 200
	row.add_child(left)
	var right := UiKit.label(value, UiTokens.FS_BODY, UiTokens.TEXT)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.clip_text = true
	right.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(right)
	return row


func _toggle_row(node_name: String, text: String, on: bool, setter: Callable) -> Control:
	var row := UiKit.hbox(UiTokens.SP_2)
	var label := UiKit.label(text, UiTokens.FS_BODY, UiTokens.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var toggle := QKit.toggle(on) as QToggle
	toggle.name = node_name
	toggle.pressed.connect(func() -> void:
		toggle.set_on(not toggle.is_on)
		setter.call(toggle.is_on))
	row.add_child(toggle)
	return row


func _link_row(text: String) -> Button:
	var row := UiKit.button(text, MainTheme.VAR_GHOST, LINK_HEIGHT)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var arrow := UiKit.label("›", UiTokens.FS_H1, UiTokens.TEXT_MUTED)
	arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	arrow.offset_left = -48
	arrow.offset_right = -16
	arrow.offset_top = -30
	arrow.offset_bottom = 30
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	return row
