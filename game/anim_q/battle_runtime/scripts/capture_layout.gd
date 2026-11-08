extends SceneTree
## 开发用：单独加载 battle_demo.tscn，导出 1080×2340 布局截图。
## 用法见 README.md

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "res://anim_q/battle_runtime/preview/layout_1080x2340.png"
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir() if out_path.begins_with("/") else "res://anim_q/battle_runtime/preview")

	var scene: Node = load("res://anim_q/battle_runtime/scenes/battle_demo.tscn").instantiate()
	root.add_child(scene)
	for _i in 20:
		await process_frame
	await create_timer(0.4).timeout

	var image: Image = root.get_viewport().get_texture().get_image()
	var abs_path := out_path
	if out_path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(out_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := image.save_png(abs_path)
	print("BATTLE_DEMO_SHOT path=", abs_path, " size=", image.get_width(), "x", image.get_height(), " err=", err)
	quit()
