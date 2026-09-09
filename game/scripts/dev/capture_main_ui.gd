extends SceneTree


func _initialize() -> void:
	var output_dir := "/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"
	DirAccess.make_dir_recursive_absolute(output_dir)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.45).timeout
	var offline_dialog := scene.get_node_or_null("%OfflineDialog") as Window
	var update_dialog := scene.get_node_or_null("%UpdateDialog") as Window
	if offline_dialog != null:
		offline_dialog.hide()
	if update_dialog != null:
		update_dialog.hide()
	await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png("%s/ui_preview.png" % output_dir)
	quit()
