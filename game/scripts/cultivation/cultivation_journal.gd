class_name CultivationJournal
extends RefCounted

const MAX_ENTRIES := 5

var entries: PackedStringArray = []


func add(line: String) -> void:
	var cleaned := line.strip_edges()
	if cleaned.is_empty():
		return
	entries.insert(0, cleaned)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)


func as_text() -> String:
	if entries.is_empty():
		return "静心吐纳，尚未留下记录。"
	var lines: PackedStringArray = []
	for entry in entries:
		lines.append("·  %s" % entry)
	return "\n".join(lines)
