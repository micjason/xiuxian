class_name ItemDetailView
extends RefCounted
## 物品详情弹窗（SPEC_Q 第 13 节）的展示数据：纯数据，不建节点，便于单元测试。
## 全部来自玩家状态 / 内容配置：BagModel 的展示字典（属性、强化、分解）、内容里的境界 / 功法 / 首领奖励 / 强化规则。
## 版式：equip（背包里的装备，身上同部位有装备时带对比）、equip_worn（身上穿着的）、book（功法书，可使用）、material（材料 / 丹药）。

## 功法最多 7 层（和服务器 useItem 一致：7 层后再用转修为）。
## 功法满层：服务器 /content/current 的 globals.tuning.skillMaxLayers（后台「配置概览」可改），没有时按 7。
const SKILL_MAX_LEVEL := 7


static func skill_max_level(content: Dictionary) -> int:
	var globals: Dictionary = content.get("globals", {}) if typeof(content.get("globals", null)) == TYPE_DICTIONARY else {}
	var tuning: Dictionary = globals.get("tuning", {}) if typeof(globals.get("tuning", null)) == TYPE_DICTIONARY else {}
	var value := int(tuning.get("skillMaxLayers", SKILL_MAX_LEVEL))
	return value if value >= 1 else SKILL_MAX_LEVEL
const ROLE_NAMES := {"heart": "心法", "art": "技能", "body": "体修"}
## 品质深色（文字用，SPEC_Q 第 2 节；白品名字用 #646A76）。
const QUALITY_DARK: Array[Color] = [Color("8e96a3"), Color("3c9a4e"), Color("2e7fc4"), Color("8a4fe0"), Color("e07b24")]
const NAME_WHITE := Color("646a76")
const QUALITY_KEYS: Array[String] = Catalog.QUALITY_KEYS


static func quality_dark(rarity: int, for_name: bool = false) -> Color:
	if rarity <= 0 and for_name:
		return NAME_WHITE
	return QUALITY_DARK[clampi(rarity, 0, QUALITY_DARK.size() - 1)]


static func type_of(item: Dictionary) -> String:
	if str(item.get("category", "")) == "equip":
		return "equip_worn" if bool(item.get("equipped", false)) else "equip"
	if str(item.get("kind", "")) == "skill_book":
		return "book"
	return "material"


## worn = 身上同部位的装备（item 是背包里的装备时才有意义；没有传空字典）。
static func build(item: Dictionary, worn: Dictionary, model: BagModel, content: Dictionary, state: Dictionary) -> Dictionary:
	var type := type_of(item)
	var rarity := int(item.get("rarity", 0))
	var view := {
		"type": type,
		"id": str(item.get("id", "")),
		"title": "装备详情" if type.begins_with("equip") else "物品详情",
		"name": str(item.get("name", "")),
		"name_color": quality_dark(rarity, true),
		"rarity": rarity,
		"rarity_name": str(item.get("rarity_name", "")),
		"kind_text": kind_text(item),
		"worn_chip": type == "equip_worn",
		"enhance": int(item.get("enhance", 0)),
		"qty": int(item.get("qty", 1)),
		"stackable": bool(item.get("stackable", false)),
		"power": int(item.get("power", 0)),
		"desc": str(item.get("desc", "")),
		"item": item,
	}
	match type:
		"equip", "equip_worn":
			var realm := realm_name_for_order(content, int(item.get("required_realm_order", 0)))
			view["info"] = ("需求 %s" % realm) if not realm.is_empty() else ""
			view["realm_ok"] = current_realm_order(content, state) >= int(item.get("required_realm_order", 0))
			view["realm_need"] = realm
			view["equip_ok"] = SlotConfig.is_equippable(str(item.get("slot_id", ""))) and bool(view["realm_ok"])
			if type == "equip" and not worn.is_empty():
				view["compare"] = compare_view(item, worn)
			else:
				view["attrs"] = attrs_view(item)
			view["set"] = set_view(item, content, model)
			view["enhance_block"] = enhance_view(item, model.enhance_exp if model != null else 0, model != null and model.uses_essence)
			view["decompose"] = {"exp": int(item.get("decompose_exp", 0)), "essence": model != null and model.uses_essence, "blocked": BagModel.decompose_block_reason(item)}
		"book":
			view["info"] = "持有 %d · %s" % [int(item.get("qty", 1)), "可叠加" if bool(item.get("stackable", false)) else "不可叠加"]
			view["skill"] = skill_view(item, model, content, state)
			view["sources"] = sources_of(content, _book_slugs(item, model))
		_:
			view["info"] = "持有 %d" % int(item.get("qty", 1))
			view["usage"] = usage_view(str(item.get("slug", "")), content, model)
			view["sources"] = sources_of(content, [str(item.get("slug", ""))])
	return view


## 套装（批次②）：这件装备属于哪个套装、成员里已拥有 / 穿着几件、每档加成（穿够的档标亮）。不属于套装时返回空字典。
## 数据：content.items[].setSlug + content.gearSets（名字、档位、成员），拥有 / 穿着按背包里的装备算（和服务器 setBonusOf 同一规则：穿着件数够就生效）。
static func set_view(item: Dictionary, content: Dictionary, model: BagModel) -> Dictionary:
	var slug := str(item.get("slug", ""))
	var set_slug := ""
	for row in content.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			set_slug = BagModel.plain((row as Dictionary).get("setSlug", null))
			break
	if set_slug.is_empty():
		return {}
	var set_def := {}
	for row in content.get("gearSets", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == set_slug:
			set_def = row
			break
	if set_def.is_empty():
		return {}
	var owned_slugs := {}
	var worn_slugs := {}
	if model != null:
		for mine in model.items:
			owned_slugs[str(mine.get("slug", ""))] = true
			if bool(mine.get("equipped", false)):
				worn_slugs[str(mine.get("slug", ""))] = true
	var members: Array[Dictionary] = []
	var owned := 0
	var worn := 0
	for member in set_def.get("members", []):
		var member_slug := str(member)
		var def := {}
		for row in content.get("items", []):
			if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == member_slug:
				def = row
				break
		var is_owned := owned_slugs.has(member_slug)
		var is_worn := worn_slugs.has(member_slug)
		owned += 1 if is_owned else 0
		worn += 1 if is_worn else 0
		members.append({
			"slug": member_slug,
			"name": str(def.get("displayName", member_slug)),
			"slot_name": Catalog.slot_name(str(def.get("slot", ""))),
			"owned": is_owned,
			"worn": is_worn,
			"this": member_slug == slug,
		})
	var tiers: Array[Dictionary] = []
	for tier in set_def.get("tiers", []):
		if typeof(tier) != TYPE_DICTIONARY:
			continue
		var pieces := int((tier as Dictionary).get("pieces", 0))
		tiers.append({"pieces": pieces, "text": "%d 件：%s" % [pieces, tier_text((tier as Dictionary).get("stats", []))], "active": worn >= pieces})
	tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.pieces) < int(b.pieces))
	return {
		"slug": set_slug,
		"name": str(set_def.get("displayName", set_slug)),
		"desc": str(set_def.get("description", "")),
		"total": members.size(),
		"owned": owned,
		"worn": worn,
		"members": members,
		"tiers": tiers,
		"summary": "已有 %d/%d · 穿戴 %d/%d" % [owned, members.size(), worn, members.size()],
	}


## 一档加成的文字：「攻击 +5%、速度 +3」。
static func tier_text(stats: Variant) -> String:
	var parts: Array[String] = []
	if typeof(stats) == TYPE_ARRAY:
		for row in stats:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var label := str(BagModel.STAT_NAMES.get(str((row as Dictionary).get("stat", "")), str((row as Dictionary).get("stat", ""))))
			var value := float((row as Dictionary).get("value", 0))
			var number := str(int(value)) if is_equal_approx(value, roundf(value)) else String.num(value, 2)
			parts.append("%s +%s%s" % [label, number, "%" if str((row as Dictionary).get("mode", "")) == "pct" else ""])
	return "、".join(parts)


static func kind_text(item: Dictionary) -> String:
	var slot := SlotConfig.find(str(item.get("slot_id", "")))
	if not slot.is_empty() and str(item.get("category", "")) == "equip":
		return str(slot.get("name", ""))
	match str(item.get("kind", "")):
		"equipment":
			return "装备"
		"material":
			return "材料"
		"consumable", "pill", "elixir":
			return "丹药"
		"skill_book":
			return "技能书"
		_:
			return "物品"


## 本件 vs 身上：每项属性 {key, label, value, other, delta}（显示前四舍五入，delta 用四舍五入后的值算，和看到的数一致）+ 战力行。
static func compare_view(item: Dictionary, worn: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for row in BagModel.compare(item, worn):
		var value := BagModel.shown(float(row.value))
		var other := BagModel.shown(float(row.other))
		rows.append({"key": str(row.key), "label": str(row.label), "value": value, "other": other, "delta": value - other})
	var power := int(item.get("power", 0))
	var worn_power := int(worn.get("power", 0))
	return {
		"worn_name": str(worn.get("name", "")),
		"worn_enhance": int(worn.get("enhance", 0)),
		"worn_rarity": int(worn.get("rarity", 0)),
		"worn_item": worn,
		"rows": rows,
		"power": {"value": power, "other": worn_power, "delta": power - worn_power},
	}


## 基础 → 当前（强化后）。只列非 0 的属性。
static func attrs_view(item: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var stats: Dictionary = item.get("stats", {})
	var base: Dictionary = item.get("base_stats", {})
	for key in BagModel.STAT_KEYS:
		var value := float(stats.get(key, 0))
		var raw := float(base.get(key, 0))
		if is_zero_approx(value) and is_zero_approx(raw):
			continue
		rows.append({"key": key, "label": str(BagModel.STAT_NAMES[key]), "base": BagModel.shown(raw), "value": BagModel.shown(value)})
	return {"enhance": int(item.get("enhance", 0)), "rows": rows, "power": int(item.get("power", 0))}


## 强化分区：mode = none（品质没有强化规则）/ max / break（卡在节点）/ normal。
## essence = 真：pool / cost 是炼器精粹（第五批，SPEC_Q §17.3）；否则是旧的强化经验。
static func enhance_view(item: Dictionary, pool: int, essence: bool = false) -> Dictionary:
	var cap := int(item.get("enhance_cap", 0))
	var level := int(item.get("enhance", 0))
	if cap <= 0:
		return {"mode": "none"}
	if level >= cap:
		return {"mode": "max", "cap": cap, "level": level}
	var view: Dictionary = item.get("break_view", {})
	var pending: Dictionary = view.get("pending", {})
	var upcoming: Dictionary = view.get("next", {})
	var cost := int(item.get("enhance_cost", 0))
	var out := {"mode": "break" if not pending.is_empty() else "normal", "cap": cap, "level": level, "cost": cost, "pool": pool,
		"enough": pool >= cost, "ratio": clampf(float(pool) / float(maxi(cost, 1)), 0.0, 1.0), "pending": pending, "next": upcoming, "essence": essence}
	out["next_text"] = ("下个突破节点 +%d：%s" % [int(upcoming.level), materials_text(upcoming)]) if not upcoming.is_empty() else ""
	return out


static func materials_text(node: Dictionary) -> String:
	var parts: Array[String] = []
	for material in node.get("materials", []):
		parts.append("%s ×%d（有 %d）" % [str(material.name), int(material.need), int(material.have)])
	return "、".join(parts)


static func _sorted_realms(content: Dictionary) -> Array:
	var rows: Array = []
	for row in content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY:
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("sortOrder", 0)) < int(b.get("sortOrder", 0)))
	return rows


## requiredRealmOrder → 境界名：第一个 sortOrder ≥ order 的境界（0 = 最低境界）。
static func realm_name_for_order(content: Dictionary, order: int) -> String:
	for row in _sorted_realms(content):
		if int(row.get("sortOrder", 0)) >= order:
			return str(row.get("displayName", ""))
	return ""


static func current_realm_order(content: Dictionary, state: Dictionary) -> int:
	var slug := str(state.get("realmSlug", ""))
	for row in _sorted_realms(content):
		if str(row.get("slug", "")) == slug:
			return int(row.get("sortOrder", 0))
	return 0


static func _def(model: BagModel, slug: String) -> Dictionary:
	return (model.defs.get(slug, {}) as Dictionary) if model != null else {}


static func _book_slugs(item: Dictionary, model: BagModel) -> Array:
	var out: Array = [str(item.get("slug", ""))]
	var skill := str(_def(model, str(item.get("slug", ""))).get("skillSlug", ""))
	if not skill.is_empty():
		out.append(skill)  # 首领首通奖励里写的是功法 slug（服务器发奖时换成对应的功法书）
	return out


## 功法书：功法名 · 类型、修炼加成、当前层数 → 使用后层数、最多 7 层、提示。
static func skill_view(item: Dictionary, model: BagModel, content: Dictionary, state: Dictionary) -> Dictionary:
	var skill_slug := str(_def(model, str(item.get("slug", ""))).get("skillSlug", ""))
	var skill: Dictionary = {}
	for row in content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == skill_slug:
			skill = row
	var level := 0
	for row in state.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("skillSlug", "")) == skill_slug:
			level = int((row as Dictionary).get("level", 0))
	var bonus: Array[String] = []
	var bp := int(skill.get("cultivateBonusBp", 0))
	if bp > 0:
		bonus.append("修炼速度 +%s%%" % _pct(bp))
	for key in BagModel.STAT_KEYS:
		var value := int(skill.get(key, 0))
		if value > 0:
			bonus.append("%s +%d" % [str(BagModel.STAT_NAMES[key]), value])
	var need_order := int(skill.get("requiredRealmOrder", 0))
	var realm_ok := current_realm_order(content, state) >= need_order
	var max_level := skill_max_level(content)
	var hint := "已满 %d 层后再使用，会转换为修为。" % max_level
	if level >= max_level:
		hint = "已满 %d 层，使用后转换为修为。" % max_level
	elif level == 0 and not realm_ok:
		hint = "需要 %s 才能学习。" % realm_name_for_order(content, need_order)
	return {
		"name": str(skill.get("displayName", "")),
		"role": str(ROLE_NAMES.get(str(skill.get("role", "")), "技能")),
		"bonus": "  ".join(bonus),
		"level": level,
		"max": max_level,
		"now_text": "未学习" if level == 0 else "第 %d 层" % level,
		"next_text": "转为修为" if level >= max_level else "第 %d 层" % (level + 1),
		"hint": hint,
	}


static func _pct(bp: int) -> String:
	return str(bp / 100) if bp % 100 == 0 else String.num(bp / 100.0, 2)


## 材料用途：强化规则里哪些品质的哪个突破节点要用它（来自 globals.enhance.qualities）。
static func usage_view(slug: String, content: Dictionary, model: BagModel) -> Dictionary:
	var globals: Dictionary = content.get("globals", {}) if typeof(content.get("globals", null)) == TYPE_DICTIONARY else {}
	var enhance: Dictionary = globals.get("enhance", {}) if typeof(globals.get("enhance", null)) == TYPE_DICTIONARY else {}
	var qualities: Dictionary = enhance.get("qualities", {}) if typeof(enhance.get("qualities", null)) == TYPE_DICTIONARY else {}
	var rows: Array[Dictionary] = []
	var levels: Array[int] = []
	for index in QUALITY_KEYS.size():
		var rule: Variant = qualities.get(QUALITY_KEYS[index], null)
		if typeof(rule) != TYPE_DICTIONARY:
			continue
		for node in (rule as Dictionary).get("breakthroughs", []):
			for material in (node as Dictionary).get("materials", []):
				if str((material as Dictionary).get("itemSlug", "")) == slug:
					var level := int((node as Dictionary).get("level", 0))
					rows.append({"rarity": index, "name": UiTokens.RARITY_NAMES[index] + "装备", "level": level, "count": int((material as Dictionary).get("count", 0))})
					if not levels.has(level):
						levels.append(level)
	if rows.is_empty():
		return {}
	levels.sort()
	var level_text := " / ".join(levels.map(func(l: int) -> String: return "+%d" % l))
	var shown := rows.slice(0, 4)
	var rest := rows.slice(4)
	var note := ""
	if not rest.is_empty():
		note = "；".join(rest.map(func(r: Dictionary) -> String: return "%s +%d 需要 %d 个" % [str(r.name).trim_suffix("装备"), int(r.level), int(r.count)])) + "。"
	if levels.size() > 1:
		for row in shown:
			row["name"] = "%s +%d" % [str(row.name), int(row.level)]
	return {"title": "用途 · 装备 %s 突破" % level_text, "rows": shown, "note": note}


## 来源：首领首通奖励 / 重复挑战额外掉落（内容配置 stages[].bosses[]）。
static func sources_of(content: Dictionary, slugs: Array) -> Array[String]:
	var firsts: Array[String] = []
	var repeats: Array = []
	for stage in content.get("stages", []):
		if typeof(stage) != TYPE_DICTIONARY:
			continue
		for boss in (stage as Dictionary).get("bosses", []):
			if typeof(boss) != TYPE_DICTIONARY:
				continue
			var name := str((boss as Dictionary).get("name", ""))
			for reward in (boss as Dictionary).get("firstClear", []):
				if typeof(reward) == TYPE_DICTIONARY and str((reward as Dictionary).get("itemSlug", "")) in slugs:
					var qty := int((reward as Dictionary).get("quantity", 1))
					firsts.append("%s首通%s" % [name, (" ×%d" % qty) if qty > 1 else "奖励"])
			var repeat: Variant = (boss as Dictionary).get("repeat", null)
			if typeof(repeat) == TYPE_DICTIONARY:
				for extra in (repeat as Dictionary).get("extras", []):
					if typeof(extra) == TYPE_DICTIONARY and str((extra as Dictionary).get("itemSlug", "")) in slugs:
						repeats.append({"boss": name, "chance": int((extra as Dictionary).get("chanceBp", 0)), "min": int((extra as Dictionary).get("minQty", 1)), "max": int((extra as Dictionary).get("maxQty", 1))})
	var out: Array[String] = []
	if not repeats.is_empty():
		var same := true
		for r in repeats:
			if r.chance != repeats[0].chance or r.min != repeats[0].min or r.max != repeats[0].max:
				same = false
		if same:
			out.append("重复挑战首领：%s%% 掉 %s 个" % [_pct(int(repeats[0].chance)), _range(int(repeats[0].min), int(repeats[0].max))])
		else:
			for r in repeats:
				out.append("重复挑战%s：%s%% 掉 %s 个" % [r.boss, _pct(int(r.chance)), _range(int(r.min), int(r.max))])
	out.append_array(firsts)
	return out


static func _range(low: int, high: int) -> String:
	return str(low) if low == high else "%d–%d" % [low, high]
