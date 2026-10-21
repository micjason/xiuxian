extends Node
## 真实本地服务器联调（开发用，不进游戏）：不走演示数据，用真账号驱动整个界面壳。
## 用法：XIUXIAN_API_BASE=http://127.0.0.1:8787 godot --headless --path game res://scripts/dev/e2e_real.tscn -- <phase> <用户名>
## phase：register（注册并存 token）| offline | battle | breakthrough | bagfull | state
## 输出以 "E2E " 开头，便于脚本筛选。

var _scene: Node


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	var dir := OS.get_environment("XIUXIAN_E2E_SHOTS")
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.6).timeout
	var image := get_tree().root.get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [dir, name])
	print("E2E shot=", name)


func _out(key: String, value: Variant) -> void:
	print("E2E %s=%s" % [key, str(value)])


func _ready() -> void:
	_main()


func _main() -> void:
	var args := OS.get_cmdline_user_args()
	var phase := args[0] if args.size() > 0 else "state"
	var user := args[1] if args.size() > 1 else "e2e_user"
	if phase == "register":
		var result := await PlayerApi.register(user, "correct-horse-1")
		if int(result.get("code", 0)) != 200 and int(result.get("code", 0)) != 201:
			result = await PlayerApi.login(user, "correct-horse-1")
		_out("register_code", result.get("code", 0))
		PlayerApi.save_token(str(result.get("token", "")))
		get_tree().quit()
		return
	var login := await PlayerApi.login(user, "correct-horse-1")
	PlayerApi.save_token(str(login.get("token", "")))
	_scene = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(_scene)
	for i in 30:
		await get_tree().process_frame
	await _wait_state()
	match phase:
		"offline":
			await _offline()
		"battle":
			await _battle()
		"breakthrough":
			await _breakthrough()
		"bagfull":
			await _bagfull()
		_:
			_dump_state()
	get_tree().quit()


func _wait_state() -> void:
	var guard := 0
	while (_scene.get("_state") as Dictionary).is_empty() and guard < 100:
		await get_tree().create_timer(0.1).timeout
		guard += 1
	await get_tree().create_timer(0.3).timeout


func _dump_state() -> void:
	var state: Dictionary = _scene.get("_state")
	_out("realm", state.get("realmName"))
	_out("power", state.get("power"))
	_out("cultivation", state.get("cultivation"))
	_out("heartbeats", _scene.call("heartbeat_count"))
	_out("bag_used", BagModel.from_state(state, _scene.get("_content"), {}).used_slots())
	var gate: Variant = (state.get("breakthrough", {}) as Dictionary).get("requiredStage")
	_out("gate", gate)


func _offline() -> void:
	var popup: OfflinePopup = _scene.get("_offline_popup")
	_out("popup_visible", popup.visible)
	var view := popup.current_view()
	_out("popup_total", view.get("total_text"))
	_out("popup_duration", view.get("duration_text"))
	_out("popup_base", view.get("base_text"))
	_out("popup_bonus", view.get("bonus_text"))
	var state: Dictionary = _scene.get("_state")
	_out("report", state.get("offlineReport"))
	await _shot("real_01_offline_popup")
	if popup.visible:
		popup.claim_button().pressed.emit()
		await get_tree().create_timer(1.0).timeout
		_out("after_ack_visible", popup.visible)
		var again := await PlayerApi.fetch_state()
		_out("after_ack_report", again.get("offlineReport"))


func _gate_slug() -> String:
	var gate: Variant = ((_scene.get("_state") as Dictionary).get("breakthrough", {}) as Dictionary).get("requiredStage")
	return str((gate as Dictionary).get("slug", "")) if typeof(gate) == TYPE_DICTIONARY else ""


func _battle() -> void:
	var slug := _gate_slug()
	_out("stage", slug)
	_scene.call("_open_battle", slug)
	var page: BattlePage = _scene.get("_battle_page")
	var bag_gate: Dictionary = page.get("_gate")
	_out("gate_state", bag_gate)
	await _shot("real_02_battle_ready")
	page.submit_requested.connect(func(_slug: String, taps: Array) -> void: _out("uploaded_taps", taps))
	page._on_start()
	if page.phase != BattlePage.Phase.RUNNING:
		_out("blocked", true)
		return
	var guard := 0
	var shot_mid := false
	while page.phase == BattlePage.Phase.RUNNING and guard < 400:
		page.step(0.25)
		if page.fight.ult_ready() and page.fight.taps.is_empty():
			if not shot_mid:
				shot_mid = true
				await _shot("real_03_battle_ult_ready")
			pass  # 第四批：大招全自动，没有点击
		guard += 1
	var predicted_win := page.fight.win
	var predicted_duration := page.fight.duration
	var guard2 := 0
	while page.phase != BattlePage.Phase.RESULT and guard2 < 100:
		await get_tree().create_timer(0.1).timeout
		guard2 += 1
	_out("phase", page.phase)
	await _shot("real_04_battle_result")
	var view := page.last_view()
	_out("client_predicted_win", predicted_win)
	_out("server_win", view.get("win"))
	_out("client_duration", predicted_duration)
	_out("server_duration", (view.get("summary", {}) as Dictionary).get("seconds"))
	_out("ults", (view.get("summary", {}) as Dictionary).get("ults"))
	_out("manual_ults", (view.get("summary", {}) as Dictionary).get("manual_ults"))
	_out("client_casts", page.fight.casts)
	_out("loot", view.get("loot"))
	_out("notes", view.get("notes"))
	_out("reason", view.get("reason"))
	_out("report_lines", page.report_text().split("\n").size())


func _breakthrough() -> void:
	var state: Dictionary = _scene.get("_state")
	var page: BreakthroughPage = _scene.get("_breakthrough_page")
	_scene.call("_open_breakthrough")
	var view := page.view()
	_out("can_start", view.get("can_start"))
	_out("hint", view.get("hint"))
	_out("power_before", state.get("power"))
	_out("preview_power", ((state.get("breakthrough", {}) as Dictionary).get("preview", {}) as Dictionary).get("power"))
	if not bool(view.get("can_start", false)):
		var denied := await PlayerApi.post_action("/api/v1/me/breakthrough")
		_out("direct_breakthrough_code", denied.get("code"))
		_out("direct_breakthrough_error", (denied.get("error", {}) as Dictionary).get("code") if typeof(denied.get("error", null)) == TYPE_DICTIONARY else "")
		return
	await _shot("real_05_breakthrough_page")
	_scene.call("_on_breakthrough")
	await get_tree().create_timer(1.5).timeout
	await _shot("real_06_breakthrough_success")
	var after: Dictionary = _scene.get("_state")
	var success: BreakthroughSuccess = _scene.get("_success_popup")
	_out("success_visible", success.visible)
	_out("realm_after", after.get("realmName"))
	_out("power_after", after.get("power"))
	_out("summary", success.summary().get("power_delta"))


func _bagfull() -> void:
	var slug := _gate_slug()
	_scene.call("_open_battle", slug)
	var page: BattlePage = _scene.get("_battle_page")
	_out("client_gate", page.get("_gate"))
	page._on_start()
	_out("phase_after_start", page.phase)
	await _shot("real_07_bag_full_fight_not_blocked")
	var result := await PlayerApi.post_action("/api/v1/me/stages/%s/challenge" % slug, {})
	_out("direct_challenge_code", result.get("code"))
	_out("direct_challenge_win", (result.get("battle", {}) as Dictionary).get("win"))
	_out("direct_challenge_bagFull", result.get("bagFull"))
	_out("direct_challenge_reward", result.get("reward"))
	_out("direct_challenge_drops", result.get("drops"))
	_out("direct_challenge_error", (result.get("error", {}) as Dictionary).get("code") if typeof(result.get("error", null)) == TYPE_DICTIONARY else "")
	var popup := _scene.get("_popup") as GamePopup
	if bool(result.get("bagFull", false)):
		_scene.call("_show_bag_full", 20, 20)
		await _wait(0.4)
		await _shot("real_08_bag_full_prompt")
		_out("prompt_visible", popup.visible)
