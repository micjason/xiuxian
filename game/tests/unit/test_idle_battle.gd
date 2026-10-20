extends GutTest
## 历练页挂机打小怪特效（anim_q/battle_idle）：伤害数字合计 = 配置气血；「+N 修为」只飘一次（页面自己的飘字已删）；
## 怪物名牌 / 血条画在特效上面；死亡溶解期间藏血条；只传真实掉落；掉落飞向底栏「背包」。

const IdleBattle := preload("res://anim_q/battle_idle/idle_battle.tscn")


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func _fx() -> Node2D:
	var fx := IdleBattle.instantiate() as Node2D
	add_child_autofree(fx)
	await get_tree().process_frame
	# 手动推进时间（不等真实帧），特效和怪物模板都停掉自动 _process
	fx.set_process(false)
	(fx.get("monster") as Node).set_process(false)
	return fx


func _step(fx: Node2D, dt: float) -> void:
	(fx.get("monster") as Node).call("_process", dt)
	fx.call("_process", dt)


## 按血条模拟：每只 per_kill 秒、匀速掉血，到点击杀数 +1、血条回满；返回每只怪的伤害数字列表。
func _simulate(fx: Node2D, hp: int, per_kill: float, kills_total: int) -> Array:
	var tex := ArtLib.q("sprites/" + ArtLib.monster_sprite_id("毒牙蟒"))
	fx.call("set_monster", tex if tex != null else PlaceholderTexture2D.new(), true, hp, 12.0)
	var per_monster: Array = []
	var current: Array[int] = []
	fx.connect("hit_landed", func(d: int) -> void: current.append(d))
	fx.connect("monster_died", func() -> void:
		per_monster.append(current.duplicate())
		current.clear())
	var dt := 1.0 / 30.0
	var t := 0.0
	var total_time := per_kill * kills_total
	while t < total_time + 6.0:
		var kills := mini(int(floor(t / per_kill)), kills_total)
		var ratio := 1.0 - fmod(t, per_kill) / per_kill if kills < kills_total else 1.0
		fx.call("sync", ratio, kills % 3)
		_step(fx, dt)
		t += dt
	return per_monster


func _assert_sums(per_monster: Array, hp: int, label: String) -> void:
	assert_gt(per_monster.size(), 0, "%s 至少死了一只" % label)
	for i in per_monster.size():
		var sum := 0
		for d in per_monster[i]:
			assert_gt(int(d), 0, "%s 每刀都是正数" % label)
			sum += int(d)
		assert_eq(sum, hp, "%s 第 %d 只：伤害数字加起来 = 配置气血 %d（%s）" % [label, i + 1, hp, str(per_monster[i])])


func test_damage_numbers_sum_to_configured_hp() -> void:
	var fx := await _fx()
	var per := _simulate(fx, 520, 4.0, 4)
	_assert_sums(per, 520, "毒牙蟒 520 / 4 秒一只")
	assert_eq(per.size(), 4, "4 只都播完")
	assert_gt((per[0] as Array).size(), 1, "慢的时候一只分好几刀")


func test_damage_numbers_sum_with_fast_kills_and_odd_hp() -> void:
	for case in [[7, 2.0, 3], [99999, 3.0, 3], [1337, 0.6, 6]]:
		var fx := await _fx()
		var per := _simulate(fx, int(case[0]), float(case[1]), int(case[2]))
		_assert_sums(per, int(case[0]), "气血 %d / %s 秒一只" % [int(case[0]), str(case[1])])


func _boot() -> Node:
	OS.set_environment("XIUXIAN_UI_MOCK", "1")
	OS.set_environment("XIUXIAN_MOCK_SCENARIO", "full")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	add_child_autofree(scene)
	for i in 4:
		await get_tree().process_frame
	OS.unset_environment("XIUXIAN_UI_MOCK")
	OS.unset_environment("XIUXIAN_MOCK_SCENARIO")
	(scene.get("_offline_popup") as Control).hide()
	scene.call("_show_page", "adventure")
	await get_tree().process_frame
	return scene


func test_stage_page_wires_effect_below_name_and_hp() -> void:
	var scene := await _boot()
	var page := scene.get("_stage_page") as StagePage
	var idle := page.find_child("IdleScene", true, false) as Control
	var fx := idle.get_node("IdleBattleFx") as Node2D
	var name_chip := idle.get_node("MonsterName") as Control
	var hp := idle.get_node("MonsterHp") as Control
	assert_lt(fx.get_index(), name_chip.get_index(), "特效在名牌之前加 → 名牌画在上面")
	assert_lt(fx.get_index(), hp.get_index(), "特效在血条之前加 → 血条画在上面")
	assert_eq(name_chip.z_index, 0)
	assert_eq(hp.z_index, 0)
	assert_eq(fx.z_index, 0, "特效层没有抬高层级")
	assert_false((idle.get_node("TargetMonster") as CanvasItem).visible, "旧的目标怪图隐藏，只用来取贴图")
	assert_not_null((idle.get_node("TargetMonster") as TextureRect).texture, "仍然用它取贴图")
	var monster := fx.get("monster") as Node2D
	assert_eq(monster.call("texture"), (idle.get_node("TargetMonster") as TextureRect).texture, "特效里的怪 = 当前关卡的怪")
	assert_eq(int(fx.get("max_hp")), int(((scene.get("_state") as Dictionary).wave.monster as Dictionary).hp), "气血用配置值 wave.monster.hp")
	assert_eq(fx.get("hero"), idle.get_node("StageHero"), "主角已绑定")
	for node in idle.get_children():
		if node is TextureRect and (node as TextureRect).texture == ArtLib.icon("tab_adventure"):
			assert_true(false, "装饰飞剑 (470,600) 已去掉")
	assert_false(page.has_method("_float_gain"), "页面自己的「+N 修为」飘字已删")


func test_kill_shows_gain_once_and_hides_hp_during_death() -> void:
	# 用固定时间步手动推进（不依赖真实帧率）：--headless 下帧不限速，按“帧数”等待时真实时间只过了零点几秒，
	# 溶解还没开始循环就结束了（动画师那边报的失败就是这个）。
	var scene := await _boot()
	var page := scene.get("_stage_page") as StagePage
	var fx := page.battle_fx()
	var hp := page.find_child("MonsterHp", true, false) as Control
	page.set_process(false)  # 由测试喂血条
	fx.set_process(false)
	(fx.get("monster") as Node).set_process(false)
	var dt := 1.0 / 30.0
	var base := {"available": true, "wave_size": 3, "kill_cultivation": 12.0}
	# 启动时页面已经按真实时间跑过几帧，可能有一只“待补的击杀”在播；先用当前击杀数、满血稳住 3 秒，让它播完再开始数。
	var per := maxi(1, int((page.call("_wave") as Dictionary).get("killsPerWave", 3)))
	var k0 := maxi(0, int(fx.get("_last_kills"))) % per
	for i in 90:
		var steady := base.duplicate()
		steady["kills"] = k0
		steady["ratio"] = float(k0) / float(per)
		page.call("_refresh_wave", steady)
		(fx.get("monster") as Node).call("_process", dt)
		fx.call("_process", dt)
	var gains: Array = []
	fx.connect("spirit_arrived", func(g: float) -> void: gains.append(g))
	var hp_hidden_seen := false
	var showing_false_seen := false
	for i in 150:  # 5 秒：前 1.3 秒掉到 30%，然后击杀一只，之后等溶解、灵气、下一只刷出
		var shown := base.duplicate()
		var k := k0 if i < 40 else (k0 + 1) % per
		shown["kills"] = k
		shown["ratio"] = (float(k) + (0.3 * float(i) / 40.0 if i < 40 else 0.001)) / float(per)
		page.call("_refresh_wave", shown)
		if not bool(fx.call("monster_showing")):
			showing_false_seen = true
			if not hp.visible:
				hp_hidden_seen = true
		(fx.get("monster") as Node).call("_process", dt)
		fx.call("_process", dt)
	assert_true(showing_false_seen, "击杀后有一段怪物不显示（溶解）")
	assert_true(hp_hidden_seen, "那段时间血条藏起来")
	assert_true(bool(fx.call("monster_showing")), "下一只刷出来了")
	assert_true(hp.visible, "下一只刷出后血条回来")
	assert_eq(gains.size(), 1, "击杀一只只飘一次「+N 修为」")
	assert_eq(page.find_children("KillFloat", "", true, false).size(), 0, "页面没有自己的飘字")


func test_only_real_drops_are_queued_and_fly_to_bag_label() -> void:
	var scene := await _boot()
	var page := scene.get("_stage_page") as StagePage
	var fx := page.battle_fx()
	var state: Dictionary = scene.get("_state")
	state["lastSettle"] = {"online": true, "seconds": 12, "kills": 1, "killCultivation": 12, "drops": [
		{"itemSlug": "enh_stone_low", "quantity": 1},
		{"itemSlug": "gear_major1_weapon_blue", "quantity": 1, "dropped": true},
		{"itemSlug": "gear_major1_gloves_white", "quantity": 1, "decomposed": true, "enhanceExp": 3},
	]}
	scene.call("_stage_drops")
	assert_eq((fx.get("_queued_icons") as Array).size(), 1, "只传真正进了背包的掉落")
	var tab_bar := scene.get("_tab_bar") as Node
	assert_eq(fx.get("bag_target_global"), tab_bar.call("label_center", "bag"), "终点 = 底栏「背包」文字")
	# 没有掉落 → 不传
	state["lastSettle"] = {"online": true, "seconds": 12, "kills": 1, "drops": []}
	(fx.get("_queued_icons") as Array).clear()
	scene.call("_stage_drops")
	assert_eq((fx.get("_queued_icons") as Array).size(), 0, "没掉落不凭空弹东西")
	# 不在历练页不传
	scene.call("_show_page", "bag")
	await get_tree().process_frame
	state["lastSettle"] = {"online": true, "seconds": 12, "kills": 1, "drops": [{"itemSlug": "enh_stone_low", "quantity": 1}]}
	scene.call("_stage_drops")
	assert_eq((fx.get("_queued_icons") as Array).size(), 0, "不在历练页不攒")
