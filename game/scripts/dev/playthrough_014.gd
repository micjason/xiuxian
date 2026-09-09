extends SceneTree

const Helper := preload("res://scripts/dev/first_loop_playthrough.gd")
const OUTDIR := "/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUTDIR)
	var snap: Dictionary = Helper.snapshot_saves()
	Helper.seed_capped_offline()
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	Helper.silence_update(scene)
	_shot("offline_dialog.png")
	var offline := scene.get_node_or_null("%OfflineDialog") as Window
	if offline != null:
		offline.hide()
	await process_frame
	var result: Dictionary = Helper.drive_first_three_realms(scene)
	await process_frame
	await create_timer(0.25).timeout
	_shot("breakthrough_journal.png")
	var report := {
		"ok": result.get("ok", false),
		"error": result.get("error", ""),
		"realm": result.get("realm", ""),
		"journal": result.get("journal", ""),
		"steps": result.get("steps", []),
		"button_rect": result.get("button_rect", []),
		"viewport": [1080, 1920],
	}
	var file := FileAccess.open("%s/playthrough_014.json" % OUTDIR, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	Helper.restore_saves(snap)
	quit(0 if report["ok"] else 1)


func _shot(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	if image == null:
		return
	image.save_png("%s/%s" % [OUTDIR, name])
