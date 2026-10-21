class_name NoticeQueue
extends RefCounted

## 后台公告排队：心跳（/me/state.notices）带来的公告一次弹一条，按优先级、时间、编号排。
## 只认「acknowledge」（公告）模板：版本更新由 UpdatePrompt 查 latest.json 弹，离线收益由「闭关归来」弹。

const TEMPLATE_ANNOUNCEMENT := "acknowledge"

var current: Dictionary = {}
var _waiting: Array[Dictionary] = []
var _session_hidden: Array[String] = []


func sync(notices: Array) -> void:
	var incoming: Array[Dictionary] = []
	for item in notices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var notice: Dictionary = item
		if str(notice.get("template", "")) != TEMPLATE_ANNOUNCEMENT:
			continue
		var id := str(notice.get("id", ""))
		if id.is_empty() or _session_hidden.has(id):
			continue
		incoming.append(notice)
	var incoming_ids: Array[String] = []
	for notice in incoming:
		incoming_ids.append(str(notice.get("id", "")))
	var kept: Array[Dictionary] = []
	for notice in _waiting:
		if incoming_ids.has(str(notice.get("id", ""))):
			kept.append(notice)
	_waiting = kept
	for notice in incoming:
		var id := str(notice.get("id", ""))
		if id == str(current.get("id", "")) or _contains(id):
			continue
		_waiting.append(notice)
	if current.is_empty():
		_present()


## 关掉当前这条。hide_for_session：本次运行不再弹（点了「知道了」，服务器记下之前的心跳可能还带着它）。
func close_current(hide_for_session: bool) -> void:
	var id := str(current.get("id", ""))
	if hide_for_session and not id.is_empty():
		_session_hidden.append(id)
	current = {}
	_present()


func _present() -> void:
	if _waiting.is_empty():
		return
	_waiting.sort_custom(_before)
	current = _waiting.pop_front()


func _contains(id: String) -> bool:
	for notice in _waiting:
		if str(notice.get("id", "")) == id:
			return true
	return false


func _before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority < right_priority
	var left_time := str(left.get("triggeredAt", ""))
	var right_time := str(right.get("triggeredAt", ""))
	if left_time != right_time:
		return left_time < right_time
	return str(left.get("id", "")) < str(right.get("id", ""))
