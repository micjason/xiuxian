extends SceneTree

const OUTPUT := "res://../builds/development/bag-page-preview-1080x1920.png"


func _init() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var screen := packed.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.get_node("%OfflineDialog").hide()
	screen.get_node("%UpdateDialog").hide()
	var session: CultivationSession = screen.get("_session")
	if session != null and session.state != null:
		session.state.inventory.clear()
		session.state.equipped = EquipmentLoadout.new()
		screen.set("_bag_fingerprint", "")
	screen.call("_show_page", "bag")
	await process_frame
	await process_frame
	await process_frame
	screen.call("_apply_safe_chrome")
	screen.call("_sync_bag_cell_size")
	await process_frame
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	print("capture_bag_page=%s size=%s" % [error_string(error), image.get_size()])
	screen.call("_show_page", "cultivate")
	await process_frame
	await process_frame
	var home_path := ProjectSettings.globalize_path("res://../builds/development/cultivate-page-preview-1080x1920.png")
	var home := root.get_viewport().get_texture().get_image()
	var home_error := home.save_png(home_path)
	print("capture_cultivate_page=%s size=%s" % [error_string(home_error), home.get_size()])
	quit(0 if error == OK and home_error == OK else 3)
