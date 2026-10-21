extends GutTest


func _notice(id: String, priority: int, at: String, template: String = "acknowledge") -> Dictionary:
	return {"id": id, "type": "announcement", "priority": priority, "template": template, "triggeredAt": at, "payload": {"title": id, "body": "正文"}}


func test_smaller_priority_then_earlier_time_shows_first_and_the_next_waits() -> void:
	var queue := NoticeQueue.new()
	var notices := [_notice("b", 2, "2026-10-21T02:00:00.000Z"), _notice("a", 2, "2026-10-21T01:00:00.000Z"), _notice("urgent", 1, "2026-10-21T03:00:00.000Z")]
	queue.sync(notices)
	assert_eq(queue.current.get("id"), "urgent")
	queue.sync(notices)
	assert_eq(queue.current.get("id"), "urgent")
	queue.close_current(true)
	assert_eq(queue.current.get("id"), "a")
	queue.close_current(true)
	assert_eq(queue.current.get("id"), "b")


func test_only_announcements_are_shown() -> void:
	var queue := NoticeQueue.new()
	queue.sync([
		_notice("release-36", 1, "2026-10-21T00:00:00.000Z", "confirm"),
		_notice("income-x", 1, "2026-10-21T00:00:00.000Z", "reward"),
		_notice("weird", 1, "2026-10-21T00:00:00.000Z", "sparkle"),
		_notice("hello", 2, "2026-10-21T00:00:00.000Z"),
	])
	assert_eq(queue.current.get("id"), "hello")
	queue.close_current(true)
	assert_true(queue.current.is_empty())


func test_dismissed_notice_stays_hidden_for_the_session_even_if_a_stale_heartbeat_brings_it_back() -> void:
	var queue := NoticeQueue.new()
	var notice := _notice("hello", 2, "2026-10-21T00:00:00.000Z")
	queue.sync([notice])
	queue.close_current(true)
	queue.sync([notice])
	assert_true(queue.current.is_empty())


func test_an_announcement_turned_off_in_the_admin_leaves_the_waiting_list() -> void:
	var queue := NoticeQueue.new()
	queue.sync([_notice("a", 2, "2026-10-21T00:00:00.000Z"), _notice("b", 2, "2026-10-21T01:00:00.000Z")])
	queue.sync([_notice("a", 2, "2026-10-21T00:00:00.000Z")])
	queue.close_current(true)
	assert_true(queue.current.is_empty())
