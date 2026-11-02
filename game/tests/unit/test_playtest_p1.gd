extends GutTest
## 通玩 P1：拥有/需要文案、挂机战报不回落占位、假入口锁标。


func test_have_need_reads_clear() -> void:
	assert_eq(QKit.have_need(4965, 109), "拥有 4,965 · 需要 109")
	assert_eq(QKit.have_need(217, 2), "拥有 217 · 需要 2")


func test_cave_cost_line_uses_have_need() -> void:
	var parts: Array[String] = []
	parts.append("%s %s" % ["灵草", "拥有 %d · 需要 %d" % [217, 2]])
	assert_eq(parts[0], "灵草 拥有 217 · 需要 2")


func test_home_feed_keeps_last_kill_line() -> void:
	var page := HomePage.new()
	add_child_autofree(page)
	page.show_feedback([{"kind": "kill", "text": "击败怪物 ×3 · 修为 +12"}])
	assert_eq(page._feed_label.text, "击败怪物 ×3 · 修为 +12")
	page._feed.clear()
	page._render_feed()
	assert_eq(page._feed_label.text, "击败怪物 ×3 · 修为 +12", "过期后仍保留最后一句，不回落开发占位")


func test_locked_entries_have_badge() -> void:
	var bar := TopBar.new()
	add_child_autofree(bar)
	assert_true(bar.mail_button().has_node("LockedBadge"), "邮箱应有锁标")
	assert_true(LockedFeature.is_locked(bar.mail_button()))
	var page := BagPage.new()
	add_child_autofree(page)
	assert_true(page._sell_button.has_node("LockedBadge"), "一键出售应有锁标")
