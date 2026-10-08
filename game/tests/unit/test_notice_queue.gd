extends GutTest


func test_smaller_priority_shows_first_and_the_next_waits() -> void:
	var queue := NoticeQueue.new()
	queue.sync([
		{"id": "income", "priority": 3, "template": "reward", "triggeredAt": "2026-10-08T00:00:00.000Z"},
		{"id": "release-23", "priority": 1, "template": "confirm", "triggeredAt": "2026-10-08T00:00:01.000Z"},
	])
	assert_eq(queue.current.get("id"), "release-23")
	queue.sync([
		{"id": "income", "priority": 3, "template": "reward", "triggeredAt": "2026-10-08T00:00:00.000Z"},
		{"id": "release-23", "priority": 1, "template": "confirm", "triggeredAt": "2026-10-08T00:00:01.000Z"},
	])
	assert_eq(queue.current.get("id"), "release-23")
	queue.close_current(false)
	assert_eq(queue.current.get("id"), "income")


func test_unknown_template_does_not_block_the_queue() -> void:
	var queue := NoticeQueue.new()
	queue.sync([
		{"id": "weird", "priority": 1, "template": "sparkle", "triggeredAt": "2026-10-08T00:00:00.000Z"},
		{"id": "income", "priority": 3, "template": "reward", "triggeredAt": "2026-10-08T00:00:00.000Z"},
	])
	assert_eq(queue.current.get("id"), "income")


func test_download_hides_the_same_notice_for_this_session() -> void:
	var queue := NoticeQueue.new()
	var notice := {"id": "release-23", "priority": 1, "template": "confirm", "triggeredAt": "2026-10-08T00:00:00.000Z"}
	queue.sync([notice])
	queue.close_current(true)
	queue.sync([notice])
	assert_true(queue.current.is_empty())
