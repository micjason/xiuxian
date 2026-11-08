extends SceneTree
## Confirmed UI acceptance: render the actual main scene under local MOCK only.
## xvfb-run -a Godot --path game --rendering-driver opengl3 --resolution 1080x2340 --script res://scripts/dev/capture_ui_fix_20261104.gd -- /out
var _out := "/workspace/cp_fix_shots/ui_fix_20261104"
var _scene: Node

func _initialize() -> void:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", "realm:jindan_2")
	OS.set_environment("XIUXIAN_UPDATE_CHECK", "0")
	OS.set_environment("XIUXIAN_SAFE_AREA", "0,90,0,0")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	await _settle()
	(_scene.get("_offline_popup") as Control).hide()
	(_scene.get("_mock_tag") as Control).hide()
	# Fixture keeps the confirmed volcano chapter and explicit three server access states.
	var state: Dictionary = _scene.get("_state")
	ProtoMock.mark_cleared(state, "jindan_1")
	state["offlineReport"] = null
	state["appearance"] = {"meditateKey": "meditate_blue", "previewKey": "preview_blue", "avatarRoundKey": "avatar_blue_round"}
	(_scene.get("_timer") as Timer).stop()
	_scene.call("_render")
	_scene.call("_show_page", "adventure")
	var page := _scene.get("_stage_page") as StagePage
	await _settle()
	await _shot("01_adventure_list.png")
	var preview := page.find_child("BossPreview_jindan_2", true, false) as Button
	assert(preview != null)
	preview.pressed.emit()
	await _shot("01b_loot_preview.png")
	page.call("_close_stage_popup")
	await process_frame
	page.challenge_button_for("jindan_3").pressed.emit()
	await _shot("01c_unlock_popup.png")
	page.call("_close_stage_popup")
	await process_frame
	page.challenge_button_for("jindan_2").pressed.emit()
	await _settle()
	await _shot("02_boss_battle.png")
	_scene.call("_show_page", "cultivate")
	var home := _scene.get("_home_page") as HomePage
	home.set_offline_pending(false)
	await _shot("03_home_no_chest.png")
	state["offlineReport"] = ProtoMock.state("ready").get("offlineReport")
	home.bind(state, _scene.get("_content"), "")
	await _shot("03_home_with_chest.png")
	print("UI_FIX_CAPTURE_DONE ", _out)
	_scene.queue_free()
	await process_frame
	await process_frame
	quit()

func _settle() -> void:
	for i in 15:
		await process_frame
	await create_timer(0.35).timeout

func _shot(filename: String) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(_out.path_join(filename))
	assert(result == OK)
	print("UI_FIX_SHOT ", filename, " ", image.get_size())
