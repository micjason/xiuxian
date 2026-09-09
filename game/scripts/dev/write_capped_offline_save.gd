extends SceneTree

const Helper := preload("res://scripts/dev/first_loop_playthrough.gd")
const OUT := "/Volumes/kaixia/projects/xiuxian/builds/development/0.1.4/seed_cultivation.json"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var now := TimeService.new().now_unix()
	var state := CultivationState.new()
	state.cultivation = 0.0
	state.realm_id = "mortal"
	state.last_settled_unix = now - Helper.OFFLINE_SECONDS
	var save := SaveService.new(OUT, OUT + ".bak", OUT + ".tmp")
	var ok := save.save_state(state, "0.1.4", "0.1.4", now - Helper.OFFLINE_SECONDS)
	print(
		"seed_ok=%s path=%s last_settled=%s offline_seconds=%s"
		% [ok, OUT, state.last_settled_unix, Helper.OFFLINE_SECONDS]
	)
	quit(0 if ok else 1)
