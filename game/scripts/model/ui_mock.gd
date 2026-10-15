class_name UiMock
extends RefCounted
## 界面演示模式：不连服务器，用内存里的假数据和假动作跑通整个界面。
## 开启方式：命令行参数 `-- --ui-mock`，或环境变量 XIUXIAN_UI_MOCK=1。
## 只用于看界面、截图、没有后端时联调交互；所有数据都是假的，界面左上角会显示"演示数据"。
## 动作（穿戴、脱下、强化、分解、使用、挑战）只改内存里的状态；强化和分解的公式与服务器一致（EnhanceModel），
## 其余数值规则与真实服务器不一定一致。

## 与后台「填入建议起始值」一致的强化规则（backend STARTING_ENHANCE_RULES，含红色和突破节点）。
const ENHANCE_RULES := {
	"expBase": 60, "expGrowth": 1.25, "statGrowthBp": 600, "refundBp": 8000,
	"qualities": {
		"white": {"cap": 5, "costMult": 1, "decomposeExp": 30, "breakthroughs": []},
		"green": {"cap": 8, "costMult": 1.1, "decomposeExp": 60, "breakthroughs": [{"level": 5, "materials": [{"itemSlug": "enh_stone_low", "count": 3}]}]},
		"blue": {"cap": 10, "costMult": 1.25, "decomposeExp": 120, "breakthroughs": [{"level": 5, "materials": [{"itemSlug": "enh_stone_low", "count": 5}]}]},
		"purple": {"cap": 12, "costMult": 1.4, "decomposeExp": 240, "breakthroughs": [
			{"level": 5, "materials": [{"itemSlug": "enh_stone_low", "count": 8}]},
			{"level": 10, "materials": [{"itemSlug": "enh_stone_mid", "count": 3}]}]},
		"orange": {"cap": 15, "costMult": 1.6, "decomposeExp": 480, "breakthroughs": [
			{"level": 5, "materials": [{"itemSlug": "enh_stone_low", "count": 10}]},
			{"level": 10, "materials": [{"itemSlug": "enh_stone_mid", "count": 6}]}]},
		"red": {"cap": 18, "costMult": 2, "decomposeExp": 960, "breakthroughs": [
			{"level": 5, "materials": [{"itemSlug": "enh_stone_low", "count": 15}]},
			{"level": 10, "materials": [{"itemSlug": "enh_stone_mid", "count": 10}]},
			{"level": 15, "materials": [{"itemSlug": "enh_stone_high", "count": 5}]}]},
	},
}

const WEIGHTS := {"attack": 4.7, "defense": 1.6, "hp": 0.95, "speed": 2.6}

static var _seq := 100


static func enabled() -> bool:
	return OS.get_cmdline_user_args().has("--ui-mock") or OS.get_environment("XIUXIAN_UI_MOCK") == "1"


static func content() -> Dictionary:
	var items: Array[Dictionary] = []
	var gear := [
		["sword_w", "青锋剑", "weapon", "white", 20, 0, 60, 0], ["sword_g", "青锋剑·良", "weapon", "green", 23, 0, 69, 0],
		["sword_b", "青锋剑·精", "weapon", "blue", 26, 0, 78, 0], ["sword_p", "寒光剑·珍", "weapon", "purple", 30, 0, 90, 0],
		["helm_w", "素木冠", "helmet", "white", 0, 4, 60, 0], ["helm_g", "素木冠·良", "helmet", "green", 0, 5, 69, 0],
		["helm_b", "云纹冠·精", "helmet", "blue", 0, 6, 78, 0],
		["glove_w", "粗布护腕", "gloves", "white", 3, 2, 30, 0], ["glove_b", "银丝护手·精", "gloves", "blue", 5, 4, 45, 1],
		["robe_w", "云纹道袍", "clothes", "white", 0, 16, 60, 0], ["robe_g", "云纹道袍·良", "clothes", "green", 0, 18, 69, 0],
		["robe_p", "玄光法袍·珍", "clothes", "purple", 0, 24, 90, 0],
		["shoe_w", "踏云靴", "shoes", "white", 0, 4, 60, 4], ["shoe_b", "踏云靴·精", "shoes", "blue", 0, 5, 78, 5],
		["acc_w", "凝玉佩", "accessory", "white", 0, 4, 60, 0], ["acc_o", "天罡玉佩·绝", "accessory", "orange", 6, 7, 108, 2],
		["sword_r", "诛仙剑·仙", "weapon", "red", 40, 0, 120, 3],
	]
	for row in gear:
		items.append({"slug": row[0], "displayName": row[1], "kind": "equipment", "slot": row[2], "quality": row[3], "attack": row[4], "defense": row[5], "hp": row[6], "speed": row[7], "requiredRealmOrder": 2, "enabled": true})
	for row in [["herb", "凝露草", "material", "white"], ["ore", "玄铁矿", "material", "green"], ["stone", "灵石", "material", "white"], ["wood", "养魂木", "material", "blue"],
			["enh_stone_low", "突破石·下品", "material", "green"], ["enh_stone_mid", "突破石·中品", "material", "blue"], ["enh_stone_high", "突破石·上品", "material", "purple"]]:
		items.append({"slug": row[0], "displayName": row[1], "kind": row[2], "quality": row[3], "stackable": true, "description": "炼制与锻造用的材料。", "enabled": true})
	for row in [["pill_qi", "聚气丹", "consumable", "white"], ["pill_back", "回灵丹", "consumable", "green"], ["pill_break", "突破丹", "consumable", "purple"]]:
		items.append({"slug": row[0], "displayName": row[1], "kind": row[2], "quality": row[3], "stackable": true, "description": "服用后见效。", "enabled": true})
	items.append({"slug": "book1", "displayName": "吐纳心法残页", "kind": "skill_book", "quality": "blue", "skillSlug": "heart1", "enabled": true})
	return {
		"globals": {"bagCapacity": 20, "powerWeights": WEIGHTS, "enhance": ENHANCE_RULES.duplicate(true)},
		"realms": [{"slug": "mortal", "displayName": "凡人", "sortOrder": 1}, {"slug": "qi1", "displayName": "炼气初期", "sortOrder": 2}, {"slug": "qi2", "displayName": "炼气中期", "sortOrder": 3}, {"slug": "qi3", "displayName": "炼气后期", "sortOrder": 4}],
		"stages": [
			{"slug": "s1", "displayName": "青岚山·枯木林", "requiredRealmOrder": 1, "recommendedPower": 800, "bosses": [{"name": "枯木妖", "attack": 30, "defense": 20, "hp": 1200, "drops": [{"itemSlug": "sword_g", "chanceBp": 2500}, {"itemSlug": "herb", "chanceBp": 6000}]}]},
			{"slug": "s2", "displayName": "青岚山·寒潭", "requiredRealmOrder": 2, "recommendedPower": 1500, "bosses": [{"name": "寒潭蛟", "attack": 45, "defense": 30, "hp": 3600, "drops": [{"itemSlug": "robe_g", "chanceBp": 1800}, {"itemSlug": "book1", "chanceBp": 500}]}]},
			{"slug": "s3", "displayName": "落霞谷", "requiredRealmOrder": 3, "recommendedPower": 2600, "bosses": [{"name": "赤练蛇王", "attack": 70, "defense": 48, "hp": 6400, "drops": [{"itemSlug": "shoe_b", "chanceBp": 1200}]}]},
		],
		"items": items,
		"skills": [{"slug": "heart1", "displayName": "养气诀", "role": "heart"}, {"slug": "art1", "displayName": "青云剑诀", "role": "art"}],
	}


static func state() -> Dictionary:
	var rows: Array[Dictionary] = []
	for row in [
		["sword_g", "weapon", 1, 3], ["helm_w", "helmet", 1, 0], ["robe_w", "clothes", 1, 2], ["shoe_b", "shoes", 1, 5], ["acc_w", "accessory", 1, 0],
		["sword_p", "", 1, 5], ["sword_b", "", 1, 0], ["sword_w", "", 1, 0], ["helm_b", "", 1, 0], ["helm_g", "", 1, 0], ["robe_p", "", 1, 0], ["robe_g", "", 1, 0],
		["glove_b", "", 1, 0], ["acc_o", "", 1, 4], ["sword_r", "", 1, 2],
		["herb", "", 36, 0], ["ore", "", 12, 0], ["wood", "", 3, 0], ["enh_stone_low", "", 6, 0], ["enh_stone_mid", "", 2, 0],
		["pill_qi", "", 8, 0], ["pill_break", "", 1, 0], ["book1", "", 1, 0],
	]:
		_seq += 1
		rows.append({"id": "m%d" % _seq, "itemSlug": row[0], "equippedSlot": null if str(row[1]).is_empty() else row[1], "isStack": int(row[2]) > 1, "quantity": row[2], "enhanceLevel": row[3], "breakLevel": int(row[4]) if row.size() > 4 else 0})
	var out := {
		"code": 200, "realmSlug": "qi2", "realmName": "炼气中期", "cultivation": 2380.0, "power": 0, "attack": 0, "defense": 0, "hp": 0, "speed": 0,
		"breakthrough": {"cost": 2880, "nextSlug": "qi3", "rateBp": 7500}, "cultivationRate": {"gainPerTick": 6.0},
		"challengeCooldownSeconds": null, "autoDecompose": false, "bagCapacity": 20, "bagBonus": 0, "enhanceExp": 380,
		"items": rows,
		"skills": [{"skillSlug": "heart1", "level": 2, "runningSlot": "heart"}, {"skillSlug": "art1", "level": 1, "runningSlot": null}],
	}
	recompute(out, content())
	return out


## 重新计算攻防血速和战力：境界基础值 + 已穿戴装备。
static func recompute(state: Dictionary, content: Dictionary) -> void:
	var defs := {}
	for def in content.get("items", []):
		defs[str(def.slug)] = def
	var enhance := EnhanceModel.from_content(content)
	var total := {"attack": 60.0, "defense": 40.0, "hp": 900.0, "speed": 14.0}
	for row in state.get("items", []):
		if row.get("equippedSlot", null) == null:
			continue
		var def: Dictionary = defs.get(str(row.itemSlug), {})
		for key in BagModel.STAT_KEYS:
			total[key] = float(total[key]) + float(enhance.stat(float(def.get(key, 0)), int(row.get("enhanceLevel", 0)), BagModel.rarity_of(def)))
	for key in BagModel.STAT_KEYS:
		state[key] = int(total[key])
	state["power"] = BagModel.power_of(total, WEIGHTS)


## 假动作：和真实接口返回同样的外形 {code, state, ...}。
static func handle(path: String, body: Dictionary, state: Dictionary, content: Dictionary) -> Dictionary:
	var parts := path.trim_prefix("/api/v1/me/").split("/")
	var result := {"code": 200}
	var items: Array = state.get("items", [])
	if parts.size() >= 3 and parts[0] == "items":
		var id := String(parts[1])
		var row := _row(items, id)
		if row.is_empty():
			return {"code": 404, "error": {"message": "没有这件物品"}}
		var def := _def(content, str(row.itemSlug))
		match String(parts[2]):
			"equip":
				var slot := str(def.get("slot", ""))
				if slot.is_empty():
					return {"code": 400, "error": {"message": "这件物品不能穿戴"}}
				for other in items:
					if other.get("equippedSlot", null) == slot:
						other["equippedSlot"] = null
				row["equippedSlot"] = slot
			"unequip":
				row["equippedSlot"] = null
			"decompose":
				if row.get("equippedSlot", null) != null:
					# 与服务器一致：409 + EQUIPPED_CANNOT_DECOMPOSE
					return {"code": 409, "error": {"code": "EQUIPPED_CANNOT_DECOMPOSE", "message": "已穿戴的装备不能分解，请先脱下「%s」" % str(def.get("displayName", "这件装备"))}}
				var rules := EnhanceModel.from_content(content)
				var rarity := BagModel.rarity_of(def)
				var gained := rules.decompose_exp(rarity, int(row.get("enhanceLevel", 0)))
				items.erase(row)
				result["gainedEnhanceExp"] = gained
				state["enhanceExp"] = int(state.get("enhanceExp", 0)) + gained
			"enhance":
				var rules2 := EnhanceModel.from_content(content)
				var rarity2 := BagModel.rarity_of(def)
				var level := int(row.get("enhanceLevel", 0))
				var broken := int(row.get("breakLevel", 0))
				if not rules2.supports(rarity2) or level >= rules2.cap(rarity2):
					return {"code": 400, "error": {"message": "已强化到上限"}}
				var gate := rules2.pending_node(rarity2, level, broken)
				if not gate.is_empty():
					return {"code": 409, "error": {"code": "BREAKTHROUGH_REQUIRED", "message": "已到突破节点 +%d，需要先突破" % int(gate.level)}}
				var from_level := level
				var spent := 0
				var pool := int(state.get("enhanceExp", 0))
				var wanted := rules2.levels_affordable(rarity2, level, pool, broken) if bool(body.get("toMax", false)) else level + 1
				if wanted == level:
					return {"code": 400, "error": {"message": "强化经验不足，还差 %d" % (rules2.cost(rarity2, level) - pool)}}
				while level < wanted:
					var need := rules2.cost(rarity2, level)
					if pool < need:
						return {"code": 400, "error": {"message": "强化经验不足，还差 %d" % (need - pool)}}
					pool -= need
					spent += need
					level += 1
				row["enhanceLevel"] = level
				state["enhanceExp"] = pool
				var stopped := rules2.pending_node(rarity2, level, broken)
				result["enhanced"] = {"itemId": id, "fromLevel": from_level, "toLevel": level, "spentExp": spent, "blockedByBreakthrough": null if stopped.is_empty() else int(stopped.level)}
			"breakthrough":
				var rules3 := EnhanceModel.from_content(content)
				var rarity3 := BagModel.rarity_of(def)
				var node := rules3.pending_node(rarity3, int(row.get("enhanceLevel", 0)), int(row.get("breakLevel", 0)))
				if node.is_empty():
					return {"code": 400, "error": {"message": "这件装备现在不在突破节点上，不需要突破"}}
				var short: Array[String] = []
				for material in node.materials:
					var have := _stack_count(items, str(material.itemSlug))
					if have < int(material.count):
						short.append("%s 还差 %d" % [str(_def(content, str(material.itemSlug)).get("displayName", material.itemSlug)), int(material.count) - have])
				if not short.is_empty():
					return {"code": 409, "error": {"code": "BREAKTHROUGH_MATERIAL_SHORT", "message": "突破材料不足：" + "；".join(short)}}
				for material in node.materials:
					_take_stack(items, str(material.itemSlug), int(material.count))
				row["breakLevel"] = int(node.level)
				result["broken"] = {"itemId": id, "level": int(node.level), "materials": node.materials}
			"use":
				items.erase(row)
				result["learned"] = {"level": 1}
	elif parts.size() >= 3 and parts[0] == "stages" and parts[2] == "challenge":
		result["battle"] = _fake_battle(state)
		result["drops"] = [{"itemSlug": "herb"}] if bool(result.battle.win) else []
	elif parts[0] == "breakthrough":
		var breakthrough: Dictionary = state.get("breakthrough", {})
		var cost := float(breakthrough.get("cost", 0))
		if float(state.get("cultivation", 0)) < cost:
			return {"code": 400, "error": {"message": "修为不足"}}
		state["cultivation"] = float(state.cultivation) - cost
		var next_slug := str(breakthrough.get("nextSlug", ""))
		for realm in content.get("realms", []):
			if str(realm.slug) == next_slug:
				state["realmSlug"] = next_slug
				state["realmName"] = str(realm.displayName)
		state["breakthrough"] = {"cost": cost * 1.6, "nextSlug": "", "rateBp": 6000}
		result["result"] = {"success": true}
	elif parts[0] == "auto-decompose":
		state["autoDecompose"] = bool(body.get("enabled", false))
	recompute(state, content)
	result["state"] = state
	return result


static func _stack_count(items: Array, slug: String) -> int:
	var total := 0
	for row in items:
		if str(row.get("itemSlug", "")) == slug and bool(row.get("isStack", false)):
			total += int(row.get("quantity", 0))
	return total


static func _take_stack(items: Array, slug: String, count: int) -> void:
	var left := count
	for row in items.duplicate():
		if left <= 0:
			break
		if str(row.get("itemSlug", "")) == slug and bool(row.get("isStack", false)):
			var take := mini(left, int(row.get("quantity", 0)))
			left -= take
			row["quantity"] = int(row.quantity) - take
			if int(row.quantity) <= 0:
				items.erase(row)


static func _row(items: Array, id: String) -> Dictionary:
	for row in items:
		if str(row.get("id", "")) == id:
			return row
	return {}


static func _def(content: Dictionary, slug: String) -> Dictionary:
	for def in content.get("items", []):
		if str(def.slug) == slug:
			return def
	return {}


static func _fake_battle(state: Dictionary) -> Dictionary:
	var log: Array[Dictionary] = []
	var boss_hp := 1200.0
	var my_hp := float(state.get("hp", 900))
	var t := 0.0
	for i in 6:
		t += 1.3
		boss_hp = maxf(0.0, boss_hp - (230.0 + i * 12.0))
		log.append({"t": t, "side": "player", "damage": 230 + i * 12, "targetHpAfter": boss_hp})
		if boss_hp <= 0.0:
			break
		my_hp -= 31.0
		log.append({"t": t + 0.4, "side": "boss", "damage": 31, "targetHpAfter": my_hp})
	return {"win": boss_hp <= 0.0, "reason": "win" if boss_hp <= 0.0 else "timeout", "durationSeconds": t, "log": log}
