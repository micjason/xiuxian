extends GutTest


func test_empty_journal_has_placeholder() -> void:
	var journal := CultivationJournal.new()
	assert_eq(journal.as_text(), "静心吐纳，尚未留下记录。")


func test_newest_entry_stays_on_top_and_caps_at_five() -> void:
	var journal := CultivationJournal.new()
	for index in range(6):
		journal.add("记录 %d" % index)
	assert_eq(journal.entries.size(), 5)
	assert_eq(journal.entries[0], "记录 5")
	assert_eq(journal.entries[4], "记录 1")
	assert_false(journal.as_text().contains("记录 0"))


func test_blank_lines_are_ignored() -> void:
	var journal := CultivationJournal.new()
	journal.add("  ")
	journal.add("突破成功")
	assert_eq(journal.entries.size(), 1)
	assert_eq(journal.entries[0], "突破成功")
