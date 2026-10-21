class_name ProtoMock
extends RefCounted
## 演示模式的原型数据集：内容（/content/current）和每个境界的 /me/state 都是真实服务器（原型 v1.2）导出的
## （resources/mock/prototype_dataset.json，由 backend/src/scripts/gen-mock-dataset.ts 生成），
## 装备、背包、离线报告、波次等随场景拼出来。动作：挑战（用 BossFight 预演，和服务器公式一致）、突破、
## 离线已读、挂机关卡；其余（穿戴、强化、分解…）交给 UiMock.handle。
## 只用于看界面和没有后端时联调；数值之外的规则（掉落概率、冷却…）是简化版，以真实服务器为准。

const DATASET_PATH := "res://resources/mock/prototype_dataset.json"
## 场景：ready = 突破条件全满足 + 有离线收益弹窗 + 背包 12/20；fresh = 刚开始；full = 背包 20/20；
## gate = 修为够但没打过首领；top = 最高境界；realm:<境界 slug> = 指定境界（按 gate 的装备/修为拼，如 realm:lianqi_2，用来查各境界的页面）。
static var scenario := "ready"
static var _data: Dictionary = {}
static var _seq := 500


static func available() -> bool:
	return FileAccess.file_exists(DATASET_PATH)


static func _dataset() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATASET_PATH))
		_data = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _data


static func content() -> Dictionary:
	var out := (_dataset().get("content", {}) as Dictionary).duplicate(true)
	UiMock.add_essence(out)  # 第五批：数据集是老服务器导出的，补上炼器精粹规则和物品
	return out


static func realm_snapshot(slug: String) -> Dictionary:
	return ((_dataset().get("realms", {}) as Dictionary).get(slug, {}) as Dictionary).duplicate(true)


static func _def(content_data: Dictionary, slug: String) -> Dictionary:
	for def in content_data.get("items", []):
		if str((def as Dictionary).get("slug", "")) == slug:
			return def
	return {}


static func _row(slug: String, equipped: Variant = null, level: int = 0, qty: int = 1, stack: bool = false) -> Dictionary:
	_seq += 1
	return {"id": "p%d" % _seq, "itemSlug": slug, "equippedSlot": equipped, "isStack": stack, "quantity": qty, "enhanceLevel": level, "breakLevel": 0}


## 按场景生成一个完整的 /me/state。
static func state(scene: String = "") -> Dictionary:
	var which := scene if not scene.is_empty() else scenario
	var content_data := content()
	var realm_slug := {"fresh": "lianqi_1", "top": "jindan_3", "gate": "lianqi_3"}.get(which, "lianqi_3") as String
	var by_realm := which.begins_with("realm:")
	if by_realm:
		realm_slug = which.trim_prefix("realm:")
		which = "gate"
	var out := realm_snapshot(realm_slug)
	out["code"] = 200
	out["playerId"] = "mock-player"
	var realm_name := str(out.get("realmName", ""))
	var items: Array = []
	var gear := [
		["gear_major1_weapon_green", "weapon", 3], ["gear_major1_helmet_white", "helmet", 1], ["gear_major1_clothes_white", "clothes", 1],
		["gear_major1_gloves_white", "gloves", 1], ["gear_major1_shoes_white", "shoes", 1],
	]
	if which != "fresh":
		for entry in gear:
			items.append(_row(str(entry[0]), entry[1], int(entry[2])))
		for slug in ["gear_major1_weapon_blue", "gear_major1_weapon_white", "gear_major1_helmet_green", "gear_major1_helmet_white", "gear_major1_clothes_green", "gear_major1_gloves_green", "gear_major1_shoes_green", "gear_major1_accessory_blue", "gear_major1_shoes_white"]:
			items.append(_row(slug))
		items.append(_row("enh_stone_low", null, 0, 3, true))
		items.append(_row("refine_essence", null, 0, 1286 if which != "full" else 260, true))
		if which == "full":
			# 满包 20/20（含 2 格材料堆叠）：几件紫 / 橙、带强化的，方便看分解界面和二次确认
			for entry in [["gear_major1_weapon_white", 0], ["gear_major1_clothes_white", 0], ["gear_major1_clothes_blue", 2], ["gear_major1_helmet_purple", 3], ["gear_major1_gloves_white", 0], ["gear_major1_gloves_blue", 0], ["gear_major1_shoes_orange", 5], ["gear_major1_accessory_white", 0], ["gear_major1_accessory_purple", 0]]:
				items.append(_row(str(entry[0]), null, int(entry[1])))
	out["items"] = items
	out.erase("autoDecompose")
	out["enhanceExp"] = 0
	out["bagBonus"] = 0
	out["bagCapacity"] = 20
	out["spiritStones"] = 0
	var skill_slug := _skill_slug(content_data, "青元诀")
	out["skills"] = [] if which == "fresh" or skill_slug.is_empty() else [{"skillSlug": skill_slug, "level": 1, "runningSlot": "heart"}]
	if not skill_slug.is_empty() and which != "fresh":
		out["cultivationRate"] = {"gainPerTick": float((out.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 1)), "bonusBp": 1500}
	var breakthrough: Dictionary = out.get("breakthrough", {}) if typeof(out.get("breakthrough", null)) == TYPE_DICTIONARY else {}
	var cost := float(breakthrough.get("cost", 0))
	out["cultivation"] = 0.0
	## 修为永远不超过本境界突破所需（cost）：满足条件的场景正好等于 cost（条满，可突破），
	## 其余按比例取自真实境界配置。最高境界没有 cost（0），不受限。
	match which:
		"ready":
			out["cultivation"] = cost
			if typeof(breakthrough.get("requiredStage", null)) == TYPE_DICTIONARY:
				(breakthrough.requiredStage as Dictionary)["cleared"] = true
				mark_cleared(out, str((breakthrough.requiredStage as Dictionary).get("slug", "")))
		"gate":
			out["cultivation"] = floorf(cost * 0.75) if by_realm else cost
		"fresh":
			out["cultivation"] = floorf(cost * 0.2)
		"full":
			out["cultivation"] = floorf(cost * 0.5)
		"top":
			out["cultivation"] = 99999.0
	out["breakthrough"] = breakthrough
	out["_base"] = {"attack": float(out.get("attack", 0)), "defense": float(out.get("defense", 0)), "hp": float(out.get("hp", 0)), "speed": float(out.get("speed", 0))}
	out["wave"] = _wave(content_data, out, realm_slug)
	out["lastSettle"] = {"online": true, "seconds": 0, "passiveGained": 0, "kills": 0, "deaths": 0, "killCultivation": 0, "drops": [], "bagFull": false}
	out["offlineReport"] = _offline_report(realm_name) if which == "ready" else null
	out["bossDaily"] = []
	# 第四批：每日首领挑战总次数（全局，所有首领共用；挂机刷出的首领默认不算）
	out["bossDailyTotal"] = {"used": 0, "limit": 5, "idleWaves": []}
	out["challengeCooldownSeconds"] = 0
	UiMock.recompute(out, content_data)
	_sync_preview(out, content_data)
	return out


## 「突破后」预览 = 下一境界的裸属性 + 现在穿的装备（真实服务器就是这么算的）。装备变了要重算。
static func _sync_preview(state_data: Dictionary, content_data: Dictionary) -> void:
	var breakthrough: Dictionary = state_data.get("breakthrough", {}) if typeof(state_data.get("breakthrough", null)) == TYPE_DICTIONARY else {}
	var preview: Variant = breakthrough.get("preview", null)
	if typeof(preview) != TYPE_DICTIONARY or (preview as Dictionary).is_empty():
		return
	if not state_data.has("_preview_base"):
		var base := {}
		for key in BagModel.STAT_KEYS:
			base[key] = float((preview as Dictionary).get(key, 0))
		state_data["_preview_base"] = base
	var raw_base: Dictionary = state_data.get("_base", {})
	var weights: Dictionary = (content_data.get("globals", {}) as Dictionary).get("powerWeights", UiMock.WEIGHTS)
	var total := {}
	for key in BagModel.STAT_KEYS:
		var gear := float(state_data.get(key, 0)) - float(raw_base.get(key, 0))
		total[key] = float((state_data._preview_base as Dictionary).get(key, 0)) + gear
		(preview as Dictionary)[key] = total[key]
	(preview as Dictionary)["power"] = BagModel.power_of(total, weights)


static func _skill_slug(content_data: Dictionary, skill_name: String) -> String:
	for skill in content_data.get("skills", []):
		if str((skill as Dictionary).get("displayName", "")) == skill_name:
			return str((skill as Dictionary).get("slug", ""))
	return ""


static func _wave(content_data: Dictionary, state_data: Dictionary, realm_slug: String) -> Dictionary:
	var order := 1
	for realm in content_data.get("realms", []):
		if str((realm as Dictionary).get("slug", "")) == realm_slug:
			order = int((realm as Dictionary).get("sortOrder", 1))
	var farmable: Array[Dictionary] = []
	for stage in content_data.get("stages", []):
		if int((stage as Dictionary).get("requiredRealmOrder", 99)) <= order and not ((stage as Dictionary).get("monsters", []) as Array).is_empty():
			farmable.append(stage)
	farmable.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.requiredRealmOrder) > int(b.requiredRealmOrder))
	var chosen: Dictionary = farmable[0] if not farmable.is_empty() else {}
	var selectable: Array = []
	for stage in farmable:
		selectable.append({"slug": stage.slug, "name": stage.displayName, "monsterName": (stage.monsters as Array)[0].name})
	selectable.reverse()
	if chosen.is_empty():
		return {"available": false, "selectable": [], "onlineGapSeconds": 15, "chosenStageSlug": null}
	var monster: Dictionary = (chosen.monsters as Array)[0]
	return {
		"available": true, "stageSlug": chosen.slug, "stageName": chosen.displayName,
		"monster": {"name": monster.name, "artKey": monster.get("artKey", null), "hp": monster.hp, "attack": monster.attack, "defense": monster.defense, "interval": monster.interval, "killCultivation": monster.killCultivation},
		"waveSize": 3, "cycleSeconds": 24.5, "killsPerWave": 3, "deathsPerWave": 0, "progress": 9.8, "deathsInRow": 0,
		"onlineGapSeconds": 15, "chosenStageSlug": null, "selectable": selectable,
	}


static func _offline_report(realm_name: String) -> Dictionary:
	return {"id": "11111111-2222-3333-4444-555555555555", "seconds": 33120, "countedSeconds": 28800, "hitCap": true, "offlineCapSeconds": 28800, "gained": 33120.0, "baseGained": 28800.0, "bonusGained": 4320.0, "realmName": realm_name}


## 模拟一次前台心跳：结算 seconds 秒（修为、击杀、偶尔一次掉落）。返回新状态（原地修改后返回）。
static func tick(state_data: Dictionary, content_data: Dictionary, seconds: float) -> Dictionary:
	var rate: Dictionary = state_data.get("cultivationRate", {}) if typeof(state_data.get("cultivationRate", null)) == TYPE_DICTIONARY else {}
	var passive := float(rate.get("gainPerTick", 0)) * (1.0 + float(rate.get("bonusBp", 0)) / 10000.0) * seconds
	var wave: Dictionary = state_data.get("wave", {}) if typeof(state_data.get("wave", null)) == TYPE_DICTIONARY else {}
	var kills := 0
	var kill_gain := 0.0
	var drops: Array = []
	if bool(wave.get("available", false)):
		var cycle := maxf(float(wave.get("cycleSeconds", 24.5)), 1.0)
		var progress := float(wave.get("progress", 0)) + seconds
		kills = int(floor(progress / cycle)) * int(wave.get("killsPerWave", 3))
		wave["progress"] = fposmod(progress, cycle)
		kill_gain = float((wave.get("monster", {}) as Dictionary).get("killCultivation", 0)) * float(kills)
		if kills > 0:
			drops.append({"itemSlug": "gear_major1_gloves_white", "quality": "white", "quantity": 1})
	state_data["cultivation"] = float(state_data.get("cultivation", 0)) + passive + kill_gain
	state_data["wave"] = wave
	state_data["lastSettle"] = {"online": true, "seconds": int(seconds), "passiveGained": passive, "kills": kills, "deaths": 0, "killCultivation": kill_gain, "drops": drops, "bagFull": false}
	return state_data


static func _find_row(items: Array, id: String) -> Dictionary:
	for row in items:
		if str((row as Dictionary).get("id", "")) == id:
			return row
	return {}


## 假动作：外形和真实接口一致 {code, state, ...}。
static func handle(path: String, body: Dictionary, state_data: Dictionary, content_data: Dictionary) -> Dictionary:
	var parts := path.trim_prefix("/api/v1/me/").split("/")
	if parts.size() >= 3 and parts[0] == "stages" and parts[2] == "challenge":
		return _challenge(String(parts[1]), body, state_data, content_data)
	if parts[0] == "breakthrough" and parts.size() == 1:
		return _breakthrough(state_data, content_data)
	if parts.size() >= 3 and parts[0] == "offline-reports" and parts[2] == "ack":
		state_data["offlineReport"] = null
		return {"code": 200, "ok": true, "id": String(parts[1]), "acknowledged": true, "state": state_data}
	if parts[0] == "idle-stage":
		var wave: Dictionary = state_data.get("wave", {})
		var slug: Variant = body.get("stageSlug", null)
		wave["chosenStageSlug"] = slug
		if slug != null:
			for option in wave.get("selectable", []):
				if str((option as Dictionary).get("slug", "")) == str(slug):
					wave["stageSlug"] = slug
					wave["stageName"] = (option as Dictionary).get("name", "")
					for stage in content_data.get("stages", []):
						if str((stage as Dictionary).get("slug", "")) == str(slug):
							var monster: Dictionary = ((stage as Dictionary).get("monsters", []) as Array)[0]
							wave["monster"] = {"name": monster.name, "artKey": monster.get("artKey", null), "hp": monster.hp, "attack": monster.attack, "defense": monster.defense, "interval": monster.interval, "killCultivation": monster.killCultivation}
		wave["progress"] = 0.0
		state_data["wave"] = wave
		return {"code": 200, "state": state_data}
	var result := UiMock.handle(path, body, state_data, content_data)
	_sync_preview(state_data, content_data)
	return result


static func _challenge(slug: String, body: Dictionary, state_data: Dictionary, content_data: Dictionary) -> Dictionary:
	var stage: Dictionary = {}
	for row in content_data.get("stages", []):
		if str((row as Dictionary).get("slug", "")) == slug:
			stage = row
	if stage.is_empty() or ((stage.get("bosses", []) as Array).is_empty()):
		return {"code": 400, "error": {"code": "INVALID_INPUT", "message": "这个关卡还没有首领"}}
	var bag := BagModel.from_state(state_data, content_data, {})
	var items: Array = state_data.get("items", [])
	var fight := BossFight.from_state(state_data, content_data, stage)
	# 第四批：大招全自动，服务器不再接收 ultTaps（传了也忽略）
	_play(fight, [])
	var drops: Array = []
	var bag_full := false
	if fight.win:
		var bag_after := BagModel.from_state(state_data, content_data, {})
		var drop_slug := "gear_major1_weapon_blue"
		var row := {"itemSlug": drop_slug, "quantity": 1, "quality": "blue"}
		if bag_after.is_full():
			row["dropped"] = true
			bag_full = true
		else:
			items.append(_row(drop_slug))
		drops.append(row)
		_count_daily(state_data, stage, slug)
		mark_cleared(state_data, slug)
		var gate_info: Variant = (state_data.get("breakthrough", {}) as Dictionary).get("requiredStage", null)
		if typeof(gate_info) == TYPE_DICTIONARY and str((gate_info as Dictionary).get("slug", "")) == slug:
			(gate_info as Dictionary)["cleared"] = true
	var casts: Array = []
	for cast in fight.casts:
		casts.append({"t": cast.t, "manual": cast.manual, "damage": cast.damage})
	var battle := {"win": fight.win, "reason": fight.reason, "durationSeconds": fight.duration if fight.finished else fight.time_limit, "log": fight.log, "ultCasts": casts}
	UiMock.recompute(state_data, content_data)
	return {"code": 200, "battle": battle, "drops": drops, "bagFull": bag_full, "reward": {"firstClear": false}, "state": state_data}


## 第三批：打赢 slug 这关 → stageAccess 里这关首通，下一关「击败上一关首领」条件满足（境界也够就能打）。和服务器同一套规则。
static func mark_cleared(state_data: Dictionary, slug: String) -> void:
	for row in state_data.get("stageAccess", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var acc := row as Dictionary
		if str(acc.get("slug", "")) == slug:
			acc["cleared"] = true
		var needs: Variant = acc.get("needs", null)
		var win: Variant = (needs as Dictionary).get("bossWin", null) if typeof(needs) == TYPE_DICTIONARY else null
		if typeof(win) == TYPE_DICTIONARY and str((win as Dictionary).get("stageSlug", "")) == slug:
			(win as Dictionary)["met"] = true
			acc["unlocked"] = true
			acc["playable"] = bool(acc.get("realmOk", false))


## 首通之后再打赢：今日首领挑战次数 +1（全局 bossDailyTotal；只算发奖励的首领；按关的 bossDaily 给老客户端看，同一个数）。
static func _count_daily(state_data: Dictionary, stage: Dictionary, slug: String) -> void:
	var cleared := false
	for row in state_data.get("stageAccess", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			cleared = bool((row as Dictionary).get("cleared", false))
	var boss: Dictionary = (stage.get("bosses", []) as Array)[0]
	var rules: Dictionary = boss.get("rules", {}) if typeof(boss.get("rules", null)) == TYPE_DICTIONARY else {}
	if not cleared or not bool(rules.get("allowRepeat", true)) or not bool(rules.get("repeatRewards", true)):
		return
	var total: Dictionary = state_data.get("bossDailyTotal", {"used": 0, "limit": 5, "idleWaves": []})
	if int(total.get("used", 0)) >= int(total.get("limit", 0)):
		return
	total["used"] = int(total.get("used", 0)) + 1
	state_data["bossDailyTotal"] = total
	var daily: Array = state_data.get("bossDaily", [])
	for row in daily:
		if str((row as Dictionary).get("stageSlug", "")) == slug:
			(row as Dictionary)["used"] = int(total.used)
			return
	daily.append({"stageSlug": slug, "used": int(total.used), "limit": int(total.get("limit", 0))})
	state_data["bossDaily"] = daily


## 把预演跑完：按上报的点击时间依次点大招，没点的由自动释放兜底。
static func _play(fight: BossFight, taps: Array) -> void:
	for tap_time in taps:
		if fight.finished:
			break
		fight.advance_to(float(tap_time))
		fight.tap()
	fight.advance_to(fight.time_limit + 1.0)


static func _breakthrough(state_data: Dictionary, content_data: Dictionary) -> Dictionary:
	var breakthrough: Dictionary = state_data.get("breakthrough", {})
	var next_slug := BagModel.plain(breakthrough.get("nextSlug", null))
	if next_slug.is_empty():
		return {"code": 400, "error": {"code": "INVALID_INPUT", "message": "已经是最高境界"}}
	var gate: Variant = breakthrough.get("requiredStage", null)
	if typeof(gate) == TYPE_DICTIONARY and not bool((gate as Dictionary).get("cleared", false)):
		return {"code": 409, "error": {"code": "STAGE_REQUIRED", "message": "先击败首领「%s」" % str((gate as Dictionary).get("bossName", ""))}}
	var cost := float(breakthrough.get("cost", 0))
	if float(state_data.get("cultivation", 0)) < cost:
		return {"code": 409, "error": {"code": "NOT_ENOUGH_CULTIVATION", "message": "修为不足"}}
	var keep_cultivation := float(state_data.cultivation) - cost
	var keep := {"items": state_data.get("items", []), "skills": state_data.get("skills", []), "enhanceExp": state_data.get("enhanceExp", 0), "wave": state_data.get("wave", {}), "bagCapacity": 20}
	var bonus_bp := float((state_data.get("cultivationRate", {}) as Dictionary).get("bonusBp", 0))
	var snapshot := realm_snapshot(next_slug)
	for key in snapshot:
		state_data[key] = snapshot[key]
	for key in keep:
		state_data[key] = keep[key]
	var rate: Dictionary = state_data.get("cultivationRate", {})
	rate["bonusBp"] = bonus_bp
	state_data["cultivationRate"] = rate
	state_data["cultivation"] = keep_cultivation
	state_data["_base"] = {"attack": float(snapshot.get("attack", 0)), "defense": float(snapshot.get("defense", 0)), "hp": float(snapshot.get("hp", 0)), "speed": float(snapshot.get("speed", 0))}
	state_data["wave"] = _wave(content_data, state_data, next_slug)
	state_data["offlineReport"] = null
	state_data.erase("_preview_base")
	UiMock.recompute(state_data, content_data)
	_sync_preview(state_data, content_data)
	return {"code": 200, "result": {"success": true, "realmSlug": next_slug}, "state": state_data}
