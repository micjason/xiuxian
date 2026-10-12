extends GutTest


func test_main_screen_waits_for_login_and_does_not_settle_locally() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var offline := scene.get_node("%OfflineLabel") as Label
	assert_false(offline.text.contains("闭关归来"))
	var banner := scene.get_node("%BreakthroughBanner") as Label
	assert_false(banner.visible)
	assert_ne(scene.get_script().resource_path, "res://scripts/ui/main_screen.gd")
