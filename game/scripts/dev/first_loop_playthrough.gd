extends RefCounted

const SAVE := "user://saves/cultivation.json"
const SAVE_BAK := "user://saves/cultivation.bak.json"
const SAVE_TMP := "user://saves/cultivation.json.tmp"
const FIRST_THREE := ["炼气初期", "炼气中期", "炼气后期"]
const OFFLINE_SECONDS := 32400


static func snapshot_saves() -> Dictionary:
	var snap := {}
	for path in [SAVE, SAVE_BAK, SAVE_TMP]:
		if FileAccess.file_exists(path):
			snap[path] = FileAccess.get_file_as_string(path)
		else:
			snap[path] = null
	return snap


static func restore_saves(snap: Dictionary) -> void:
	for path in snap.keys():
		var text: Variant = snap[path]
		var abs_path := ProjectSettings.globalize_path(path)
		if text == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(abs_path)
		else:
			DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_string(str(text))


static func seed_capped_offline() -> void:
	var now := TimeService.new().now_unix()
	var state := CultivationState.new()
	state.cultivation = 0.0
	state.realm_id = "mortal"
	state.last_settled_unix = now - OFFLINE_SECONDS
	var save := SaveService.new()
	save.save_state(state, "0.1.4", "0.1.4", now - OFFLINE_SECONDS)


static func silence_update(screen: Node) -> void:
	screen.set("_update_check_pending", false)
	var update_dialog := screen.get_node_or_null("%UpdateDialog") as Window
	if update_dialog != null:
		update_dialog.hide()


static func drive_first_three_realms(screen: Node) -> Dictionary:
	var session: CultivationSession = screen.get("_session")
	var button := screen.get_node("%BreakthroughButton") as Button
	var banner := screen.get_node("%BreakthroughBanner") as Label
	var journal := screen.get_node("%JournalLabel") as Label
	var realm_label := screen.get_node("%RealmLabel") as Label
	if session == null or button == null:
		return {"ok": false, "error": "main screen is missing session or button"}
	var steps: Array = []
	for expected in FIRST_THREE:
		var realm := session.current_realm()
		if realm == null:
			return {"ok": false, "error": "missing current realm"}
		var wait := int(ceili(realm.breakthrough_cost / realm.gain_per_second))
		session.time_service.set_unix(session.time_service.now_unix() + wait)
		session.tick_online()
		if not session.can_breakthrough():
			return {"ok": false, "error": "not ready for %s after %s seconds" % [expected, wait]}
		button.pressed.emit()
		if realm_label.text != expected:
			return {
				"ok": false,
				"error": "realm is %s, want %s" % [realm_label.text, expected],
			}
		if not banner.visible or not banner.text.contains("突破成功"):
			return {"ok": false, "error": "breakthrough banner missing for %s" % expected}
		steps.append({
			"realm": expected,
			"banner": banner.text,
			"wait_seconds": wait,
		})
	return {
		"ok": true,
		"steps": steps,
		"journal": journal.text,
		"realm": realm_label.text,
		"button_rect": [
			button.global_position.x,
			button.global_position.y,
			button.size.x,
			button.size.y,
		],
	}
