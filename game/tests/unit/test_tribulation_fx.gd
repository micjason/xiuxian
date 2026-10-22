extends GutTest
## 天雷渡劫：场景能加载、时长 10 秒、突破页成功路径等到 finished 才返回。
## 不把 10 秒跑完，测试里直接把 _process 推进到结束。


func test_tribulation_scene_loads_and_lasts_ten_seconds() -> void:
	assert_true(QFx.has(QFx.TRIBULATION), QFx.TRIBULATION)
	assert_almost_eq(QFx.TRIBULATION_SECONDS, TribulationFx.DURATION, 0.001)
	assert_almost_eq(TribulationFx.DURATION, 10.0, 0.001)
	var fx := QFx.make(QFx.TRIBULATION) as TribulationFx
	assert_not_null(fx)
	add_child_autofree(fx)
	await get_tree().process_frame
	assert_false(fx.autoplay)
	assert_true(fx.use_dim)
	assert_almost_eq(fx.shake_mul, 1.0, 0.001)
	assert_eq(fx.banner_text, "突破成功")
	assert_false(str(fx.banner_text).contains("暴击"))
	assert_almost_eq(fx.duration(), 10.0, 0.001)
	assert_eq(fx.get_node("World/Bolts").get_child_count(), 7, "落雷池 7 个，运行时不 new")
	assert_not_null(fx.get_node_or_null("World/HeroSlot"))
	var label := fx.get_node("World/Front/Title/Box/Text") as Label
	assert_eq(label.text, "突破成功")
	assert_false(label.text.contains("暴击"))
	assert_not_null(label.label_settings)
	assert_not_null(label.label_settings.font, "横幅字体能加载（共用庆科黄油体子集）")
	var missing := _missing_textures(fx)
	assert_eq(missing, [] as Array[String], "缺贴图：%s" % [missing])
	var scene := FileAccess.get_file_as_string("res://anim_q/breakthrough_tribulation/tribulation_fx.tscn")
	assert_false(scene.contains("暴击"))
	assert_true(scene.contains("res://assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2"))
	var rels: Array[String] = ["fx/fx_bolt_0.png", "fx/fx_bolt_final.png", "fx/fx_storm_cloud.png", "fx/fx_sunburst.png", "fx/fx_pillar_gold.png", "fx/fx_thunder_impact.png", "fx/fx_gold_bloom.png", "art/ribbon_title_104.png"]
	for rel in rels:
		var path: String = "res://anim_q/breakthrough_tribulation/" + rel
		assert_true(FileAccess.file_exists(path), rel)
		assert_true(scene.contains(rel), "场景引用 " + rel)


## 替身在 play() 的下一帧才发 finished。play_success 必须 await，收起才会发生在信号之后。
class _InstantTribulation extends TribulationFx:
	var play_count := 0
	var visible_when_finished := false

	func _ready() -> void:
		pass

	func play() -> void:
		play_count += 1
		call_deferred("_emit_finished")

	func _emit_finished() -> void:
		visible_when_finished = visible
		finished.emit()


func test_breakthrough_success_waits_for_tribulation_finished() -> void:
	var page := BreakthroughPage.new()
	add_child_autofree(page)
	page.bind(_ready_state(), {}, "炼气二层")
	var mock := _InstantTribulation.new()
	mock.name = "TribulationFx"
	page.add_child(mock)
	page.set("_tribulation", mock)
	await page.play_success("突破成功")
	assert_eq(mock.play_count, 1, "成功路径会 play()")
	assert_eq(mock.banner_text, "突破成功")
	assert_false(str(mock.banner_text).contains("暴击"))
	assert_false(mock.autoplay)
	assert_true(mock.use_dim)
	assert_almost_eq(mock.shake_mul, 1.0, 0.001)
	assert_true(mock.visible_when_finished, "finished 到来时特效还在，说明先等信号再收")
	assert_false(mock.visible, "finished 之后才隐藏")
	var layer := mock.get_node_or_null("FxLayer") as CanvasLayer
	assert_null(layer)
	var old := QFx.player(page.break_fx())
	assert_not_null(old)
	assert_ne(old.current_animation, "success", "正式成功路径不播短特效的 success")
	assert_true(page.fx_running(), "刷属性仍等调用方 finish_fx")
	page.finish_fx()
	assert_false(page.fx_running())


func test_success_path_mounts_the_hero_on_the_real_scene() -> void:
	var page := BreakthroughPage.new()
	add_child_autofree(page)
	page.bind(_ready_state(), {}, "炼气二层")
	var fx := page.call("_ensure_tribulation") as TribulationFx
	assert_not_null(fx)
	assert_eq(fx.scene_file_path, QFx.TRIBULATION)
	assert_false(fx.autoplay)
	var hero := fx.get_node_or_null("World/HeroSlot/Hero") as Node2D
	assert_not_null(hero, "主角挂在 World/HeroSlot")
	if hero != null:
		var cushion := hero.get_node_or_null("Rig/Cushion") as CanvasItem
		assert_not_null(cushion)
		assert_false(cushion.visible)
	assert_not_null(fx.get_node_or_null("World/HeroSlot/Lotus"))
	var old := QFx.player(page.break_fx())
	assert_not_null(old)
	assert_ne(old.current_animation, "success")


func _ready_state() -> Dictionary:
	return {
		"realmName": "炼气一层",
		"cultivation": 1800,
		"power": 915,
		"hp": 547,
		"attack": 63,
		"defense": 23,
		"speed": 24,
		"breakthrough": {
			"nextSlug": "qi_2",
			"cost": 1800,
			"rateBp": 10000,
			"preview": {"power": 1240, "hp": 829, "attack": 183, "defense": 41, "speed": 30, "realmName": "炼气二层"},
		},
	}


func _missing_textures(node: Node) -> Array[String]:
	var missing: Array[String] = []
	_walk_textures(node, missing)
	return missing


func _walk_textures(node: Node, missing: Array[String]) -> void:
	if node is Sprite2D and (node as Sprite2D).texture == null:
		missing.append(str(node.get_path()))
	elif node is CPUParticles2D and (node as CPUParticles2D).texture == null:
		missing.append(str(node.get_path()))
	elif node is NinePatchRect and (node as NinePatchRect).texture == null:
		missing.append(str(node.get_path()))
	for child in node.get_children():
		_walk_textures(child, missing)
