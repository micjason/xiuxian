extends SceneTree
## v14 截图（开发用，不进游戏）：历练 / 背包 滚到中间（模拟手指拖动，无滚动条）、物品详情 4 种版式、穿戴后。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_MOCK_SCENARIO=full XIUXIAN_SAFE_AREA=0,90,0,0 godot --path game --rendering-driver opengl3 \
##   --resolution 1080x2340 --script res://scripts/dev/capture_v14.gd -- <输出目录>
## 演示数据（ProtoMock，与服务器同结构）；功法书截图时往背包里放一本青元诀技能书（黑风熊王首通奖励，真实配置里的物品）。

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_v14"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 10:
		await process_frame
	var offline := _scene.get("_offline_popup") as Control
	if offline.visible:
		offline.call("close_popup")
	await _wait(0.6)
	# 历练：拖到列表中间
	_scene.call("_show_page", "adventure")
	await _wait(0.8)
	var view := (_scene.get("_stage_page") as Node).get("_stage_view") as ScrollContainer
	await _drag(view, 0.5)
	await _wait(1.2)
	print("adventure scroll ", view.scroll_vertical, " / ", view.get_v_scroll_bar().max_value - view.get_v_scroll_bar().page)
	_shot("v14_adventure_scrolled")
	await _battle_shots(view)
	# 背包：拖到中间
	_scene.call("_show_page", "bag")
	await _wait(0.8)
	var bag := _scene.get("_bag_page") as BagPage
	var grid := bag.find_child("BagGrid", true, false) as ScrollContainer
	await _drag(grid, 0.5)
	await _wait(1.2)
	print("bag scroll ", grid.scroll_vertical, " / ", grid.get_v_scroll_bar().max_value - grid.get_v_scroll_bar().page)
	_shot("v14_bag_scrolled")
	ScrollKit.of(grid).jump_to(0)
	await _wait(0.3)
	var popup := _scene.get("_item_popup") as ItemDetailPopup
	# 装备·可穿戴（身上同部位有装备 → 对比）
	var target := _pick(bag, func(it: Dictionary) -> bool: return it.category == "equip" and not it.equipped and not EquipModel.worn_in(bag.model, str(it.slot_id)).is_empty() and int(it.rarity) >= 2)
	bag.call("_on_slot", target)
	await _wait(0.6)
	_shot("v14_popup_equip")
	popup.close_popup()
	# 装备·已穿戴（纸娃娃部位）
	bag.call("_on_equip_slot", str(target.slot_id))
	await _wait(0.6)
	_shot("v14_popup_equip_worn")
	popup.close_popup()
	# 材料
	var stone := _pick(bag, func(it: Dictionary) -> bool: return it.category == "material")
	bag.call("_on_slot", stone)
	await _wait(0.6)
	_shot("v14_popup_material")
	popup.close_popup()
	# 功法书：放一本青元诀技能书
	var state: Dictionary = _scene.get("_state")
	var content: Dictionary = _scene.get("_content")
	var book_slug := ""
	for def in content.get("items", []):
		if str(def.get("kind", "")) == "skill_book" and str(def.get("displayName", "")).begins_with("青元诀"):
			book_slug = str(def.slug)
	(state.items as Array).append({"id": "cap-book", "itemSlug": book_slug, "equippedSlot": null, "isStack": false, "quantity": 1, "enhanceLevel": 0, "breakLevel": 0})
	_scene.call("_render", false)
	await _wait(0.3)
	var book := _pick(bag, func(it: Dictionary) -> bool: return it.kind == "skill_book")
	bag.call("_on_slot", book)
	await _wait(0.6)
	_shot("v14_popup_book")
	popup.close_popup()
	# 穿戴：从装备弹窗点「穿 戴」→ 背包 / 纸娃娃更新
	bag.call("_on_slot", bag.model.find(str(target.id)))
	await _wait(0.5)
	popup.button_named("穿 戴").pressed.emit()
	await _wait(1.0)
	print("after equip worn=", EquipModel.worn_in(bag.model, str(target.slot_id)).get("id"), " target=", target.id)
	_shot("v14_after_equip")
	quit()


## 挂机打小怪特效：命中 / 击杀溶解 / 掉落飞向背包 三帧。血条由脚本喂（和页面每帧传给特效的值一样），
## 掉落 = 一条演示结算（真实配置里的物品，走 PlayScreen._stage_drops 同一条路）。
func _battle_shots(view: ScrollContainer) -> void:
	ScrollKit.of(view).jump_to(0)
	var page := _scene.get("_stage_page") as StagePage
	var fx := page.battle_fx()
	page.set_process(false)
	var state: Dictionary = _scene.get("_state")
	state["lastSettle"] = {"online": true, "seconds": 12, "kills": 1, "killCultivation": 12, "drops": [{"itemSlug": "enh_stone_low", "quantity": 2}, {"itemSlug": "gear_major1_gloves_white", "quantity": 1}]}
	_scene.call("_stage_drops")
	_driving = true
	_drive(page)
	while true:  # 等一刀普通命中（之前页面自己跑着时可能还有一只待补的击杀）
		await fx.hit_landed
		if not bool(fx.get("_sw_final")):
			break
	await _wait(0.07)
	_shot("v14_battle_hit")
	await _wait_until(func() -> bool: return float(fx.get("_orb_t")) >= 0.0)  # 最后一刀落下、开始溶解
	await _wait(0.3)
	_shot("v14_battle_death")
	await _wait(0.75)
	_shot("v14_battle_drop")
	await _wait(1.5)
	_driving = false
	page.set_process(true)


var _driving := false


func _drive(page: StagePage) -> void:
	var base := {"available": true, "wave_size": 3, "kill_cultivation": 12.0}
	var k0 := int(WaveView.display(_scene.get("_state"), 0.0).get("kills", 0)) % 3
	var r0 := minf(1.0 - (page.find_child("MonsterHp", true, false) as QBar).ratio, 0.5)
	var start := Time.get_ticks_msec()
	while _driving:
		var t := float(Time.get_ticks_msec() - start) / 1000.0
		var shown := base.duplicate()
		var r := minf(r0 + t / 2.6, 0.97)
		var k := k0 if t < 2.8 else (k0 + 1) % 3
		shown["kills"] = k
		shown["ratio"] = (float(k) + (r if t < 2.8 else 0.0)) / 3.0
		page.call("_refresh_wave", shown)
		await process_frame


func _wait_until(test: Callable) -> void:
	for i in 600:
		if test.call():
			return
		await process_frame


func _pick(bag: BagPage, test: Callable) -> Dictionary:
	for it in bag.model.items:
		if test.call(it):
			return it
	return {}


func _drag(scroll: ScrollContainer, fraction: float) -> void:
	var kit := ScrollKit.of(scroll)
	var distance := kit.max_scroll() * fraction + ScrollKit.DEADZONE
	var rect := scroll.get_global_rect()
	var from := Vector2(rect.get_center().x, minf(rect.end.y - 40.0, rect.get_center().y + distance / 2.0))
	var to := from - Vector2(0, distance)
	var xf := root.get_final_transform()
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = xf * from
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await process_frame
	var last := from
	for i in range(1, 21):
		var p := from.lerp(to, i / 20.0)
		var m := InputEventScreenDrag.new()
		m.position = xf * p
		m.relative = xf * p - xf * last
		last = p
		Input.parse_input_event(m)
		Input.flush_buffered_events()
		await create_timer(0.03).timeout
	await create_timer(0.15).timeout  # 停一下再松手（不甩，停在中间）
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = xf * to
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
