extends SceneTree

const OUTPUT := "res://../builds/development/0.6.0/cave-production-1080x1920.png"


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
	var session: CultivationSession = screen.get("_session")
	if session == null or session.state == null:
		quit(2)
		return
	var progress := session.state.long_term
	for resource_id in session.long_term_config.resource_names:
		progress.economy.resources[resource_id] = 128.0
	for resource_id in session.long_term_config.cave_rates:
		session.assign_cave_labor(resource_id, 1)
	progress.cave.building_levels["echo_court"] = 2
	progress.cave.building_levels["rain_workshop"] = 1
	progress.cave.building_levels["waymark_tower"] = 1
	screen.get_node("%OfflineDialog").hide()
	screen.get_node("%UpdateDialog").hide()
	screen.call("_show_page", "cave")
	var cave: CavePageController = screen.get_node("%CavePage")
	cave.call("_select_tab", "production")
	await process_frame
	await process_frame
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var image := root.get_viewport().get_texture().get_image()
	var error := image.save_png(output_path)
	print("capture_longterm_060=%s size=%s" % [error_string(error), image.get_size()])
	quit(0 if error == OK else 3)
