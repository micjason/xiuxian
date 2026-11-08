extends SceneTree
## Real viewport capture: 360 deterministic frames at 30 fps (12 seconds).
func _initialize() -> void:
	var out_dir := ProjectSettings.globalize_path("res://anim_q/battle_runtime/preview")
	var frames_dir := OS.get_environment("BATTLE_CAPTURE_DIR")
	if frames_dir == "": frames_dir = "/tmp/battle_runtime_capture_frames"
	DirAccess.make_dir_recursive_absolute(frames_dir)
	var scene: Node = load("res://anim_q/battle_runtime/scenes/battle_demo.tscn").instantiate()
	root.add_child(scene)
	scene.capture_mode = true
	for _i in 8:
		await process_frame
	for i in 360:
		scene.seek_demo(float(i) / 30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		var err := image.save_jpg(frames_dir + "/%04d.jpg" % i, 0.97)
		if err != OK:
			push_error("CAPTURE_WRITE_FAILED " + str(err))
			quit(1)
			return
		var still := ""
		if i == 30: still = "idle"
		if i == 66: still = "attack"
		if i == 138: still = "skill"
		if i == 261: still = "hit"
		if still != "": image.save_png(out_dir + "/demo_" + still + ".png")
		if i % 30 == 0: print("CAPTURE_FRAME ", i, " ", image.get_width(), "x", image.get_height())
	print("CAPTURE_DONE 360 frames 12 seconds")
	quit()
