extends SceneTree
## 开发用：登录页截图（不连服务器、不用演示数据）。用法：--script res://scripts/dev/capture_login.gd -- <输出目录>
func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/login_shot"
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	await create_timer(1.0).timeout
	root.get_viewport().get_texture().get_image().save_png("%s/login.png" % out)
	print("shot login")
	quit()
