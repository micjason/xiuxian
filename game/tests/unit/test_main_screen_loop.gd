extends GutTest

const Helper := preload("res://scripts/dev/first_loop_playthrough.gd")

var _snap: Dictionary = {}


func before_each() -> void:
	_snap = Helper.snapshot_saves()
	Helper.seed_capped_offline()


func after_each() -> void:
	Helper.restore_saves(_snap)


func test_main_screen_shows_offline_breakthrough_journal_and_first_three_realms() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	Helper.silence_update(scene)

	var offline := scene.get_node("%OfflineDialog") as AcceptDialog
	assert_false(offline.visible, "闭关详情改由通知队列显示，不再打开这扇窗口")
	assert_true((scene.get_node("%OfflineLabel") as Label).text.contains("闭关归来"))
	assert_true((scene.get_node("%JournalLabel") as Label).text.contains("闭关归来"))
	assert_eq((scene.get_node("%RealmLabel") as Label).text, "凡人")

	offline.hide()
	var result: Dictionary = Helper.drive_first_three_realms(scene)
	assert_true(result.get("ok", false), str(result.get("error", result)))
	assert_eq((scene.get_node("%RealmLabel") as Label).text, "炼气后期")
	assert_true((scene.get_node("%BreakthroughBanner") as Label).visible)
	assert_true((scene.get_node("%BreakthroughBanner") as Label).text.contains("炼气中期"))
	assert_true((scene.get_node("%BreakthroughBanner") as Label).text.contains("炼气后期"))
	var journal := (scene.get_node("%JournalLabel") as Label).text
	assert_true(journal.contains("突破成功"))
	assert_true(journal.contains("炼气初期"))
	assert_true(journal.contains("炼气中期"))
	assert_true(journal.contains("闭关归来"))
