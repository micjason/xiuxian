class_name AnnouncementPrompt
extends RefCounted
## 后台「公告」弹窗（和「发现新版本」同一种屏幕正中的小弹窗）：标题 = 公告标题，正文可滚动，按钮「知道了」。
## 关掉（按钮或点遮罩）就算读过：play_screen 告诉服务器（POST /me/notices/:id/dismiss），以后的心跳不再带它。

signal acknowledged(notice_id: String)

var popup: GamePopup
var showing_id := ""


func _init(target_popup: GamePopup) -> void:
	popup = target_popup
	popup.closed.connect(_on_closed)


static func title_for(notice: Dictionary) -> String:
	var payload: Dictionary = notice.get("payload", {}) if typeof(notice.get("payload", null)) == TYPE_DICTIONARY else {}
	var title := str(payload.get("title", "")).strip_edges()
	return "公告" if title.is_empty() else title


static func body_for(notice: Dictionary) -> String:
	var payload: Dictionary = notice.get("payload", {}) if typeof(notice.get("payload", null)) == TYPE_DICTIONARY else {}
	return str(payload.get("body", "")).strip_edges()


func show_notice(notice: Dictionary) -> void:
	showing_id = str(notice.get("id", ""))
	popup.clear_content()
	popup.set_dim_closes(true)
	var body := UiKit.wrap_label(body_for(notice), UiTokens.FS_BODY, UiTokens.TEXT)
	body.name = "AnnouncementBody"
	popup.body.add_child(body)
	popup.set_actions([{"text": "知道了", "variation": MainTheme.VAR_PRIMARY}])
	popup.open_popup(title_for(notice), true)


func _on_closed() -> void:
	if showing_id.is_empty():
		return
	var id := showing_id
	showing_id = ""
	acknowledged.emit(id)
