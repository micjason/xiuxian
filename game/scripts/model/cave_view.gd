class_name CaveView
extends RefCounted
## 洞府大改：总览四入口傀儡/药园/炼丹/炼器；无阵法、无洞府强化入口。
## state.dongfu 权威；本视图只做展示整形。

const FACILITIES := [
	{"id": "puppet", "name": "傀儡产线", "sprite": "bd_hut", "blurb": "肉底座 · 木草石派工"},
	{"id": "garden", "name": "药园", "sprite": "bd_field", "blurb": "本页点种 · 成熟领取"},
	{"id": "alchemy", "name": "炼丹", "sprite": "bd_alchemy", "blurb": "摸索藏方 · 一键复炼"},
	{"id": "forge", "name": "炼器", "sprite": "bd_alchemy", "blurb": "图纸造装 · 顶橙同表"},
]

## 内容缺 displayName 时的中文名。界面禁止回落成 slug。
const ITEM_DISPLAY_FALLBACK := {
	"seed_lingcao": "灵草种子",
	"seed_qingxin": "清心草种子",
	"herb_lingcao": "灵草",
	"herb_qingxin": "清心草",
	"pill_cultivate": "修为丹",
	"pill_atk_temp": "攻击临时丹",
	"pill_def_temp": "防御临时丹",
	"wood_lingmu": "灵木",
	"array_shard": "阵纹残片",
	"puppet_meat": "灵肉",
	"puppet_stone": "灵石材",
}
const UNKNOWN_ITEM_NAME := "未知物品"


static func config_of(content: Dictionary) -> Dictionary:
	var globals: Variant = content.get("globals", {})
	if typeof(globals) != TYPE_DICTIONARY:
		return {}
	var raw: Variant = (globals as Dictionary).get("dongfu", null)
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func item_name(content: Dictionary, slug: String) -> String:
	if slug.is_empty():
		return ""
	var named := _content_display_name(content, slug)
	if not named.is_empty():
		return named
	return str(ITEM_DISPLAY_FALLBACK.get(slug, UNKNOWN_ITEM_NAME))


static func _content_display_name(content: Dictionary, slug: String) -> String:
	var items: Variant = content.get("items", [])
	if typeof(items) != TYPE_ARRAY:
		return ""
	for row in items:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		if str(item.get("slug", "")) != slug:
			continue
		# 空字符串或把 slug 写进 displayName 都算缺名，改走中文回落。
		var name := str(item.get("displayName", "")).strip_edges()
		if name.is_empty() or name == slug:
			return ""
		return name
	return ""


static func remaining_text(iso: String, now_unix: float = -1.0) -> String:
	if iso.is_empty():
		return ""
	var stamp := iso
	# Godot 解析 ISO：把尾部 Z 换成 +00:00，去掉毫秒更稳。
	if stamp.ends_with("Z"):
		stamp = stamp.substr(0, stamp.length() - 1) + "+00:00"
	var dot := stamp.find(".")
	var plus := stamp.find("+", 10)
	var minus := stamp.rfind("-")
	if dot >= 0:
		var end := plus if plus > dot else (minus if minus > 19 else stamp.length())
		if end > dot:
			stamp = stamp.substr(0, dot) + stamp.substr(end)
	var target := Time.get_unix_time_from_datetime_string(stamp)
	var now := Time.get_unix_time_from_system() if now_unix < 0.0 else now_unix
	var left := int(floor(target - now))
	if left <= 0:
		return "可领取"
	if left < 60:
		return "%d 秒" % left
	if left < 3600:
		return "%d 分 %d 秒" % [left / 60, left % 60]
	return "%d 时 %d 分" % [left / 3600, (left % 3600) / 60]


static func bag_count(state: Dictionary, slug: String) -> int:
	var total := 0
	for row in state.get("items", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item := row as Dictionary
		if str(item.get("itemSlug", "")) != slug:
			continue
		total += maxi(1, int(item.get("quantity", 1)))
	return total


static func _factor(data: Dictionary, key: String) -> float:
	var scale: Variant = data.get("timeScale", {})
	if typeof(scale) != TYPE_DICTIONARY:
		return 1.0
	return clampf(float((scale as Dictionary).get(key, 1.0)), 0.01, 1.0)


static func _scaled_seconds(base: int, factor: float) -> int:
	if base <= 0:
		return 0
	return maxi(1, int(ceil(float(base) * factor)))


## 总视图：洞府三卡 + 灵仆分配 + 设施升级。
static func build(state: Dictionary, content: Dictionary, now_unix: float = -1.0) -> Dictionary:
	var dongfu: Variant = state.get("dongfu", null)
	var cfg := config_of(content)
	if typeof(dongfu) != TYPE_DICTIONARY:
		return {
			"available": false,
			"plotCount": 0,
			"alchemyQueueLength": 0,
			"claimable": {"plots": 0, "alchemy": 0, "forge": 0},
			"cards": _cards(false, {"plots": 0, "alchemy": 0}, [], [], {}, {}, {}, {}),
			"plots": [],
			"alchemy": [],
			"recipes": [],
			"seeds": [],
			"seedHint": "",
			"allocation": {"garden": 0, "alchemy": 0},
			"servantTotal": 0,
			"servantAssignLingshi": 0,
			"trial": {},
			"alchemyXp": 0,
			"woodCount": 0,
			"woodName": "灵木",
			"timeScale": {"garden": 1.0, "alchemy": 1.0},
			"upgrades": {},
			"spiritStones": int(state.get("spiritStones", 0)),
			"arrayDaily": {"enabled": false, "clearedToday": false, "dayKey": "", "arrayXp": 0, "puzzle": {}},
			"puppet": {},
			"forge": {"jobs": [], "blueprints": [], "claimable": 0},
			"alchemyMaterials": [],
			"forgeMaterials": [],
			"hubEntries": ["puppet", "garden", "alchemy", "forge"],
			"hint": "洞府配置尚未发布" if cfg.is_empty() else "暂无洞府数据",
		}
	var data := dongfu as Dictionary
	var claimable: Dictionary = data.get("claimable", {}) if typeof(data.get("claimable", {})) == TYPE_DICTIONARY else {}
	var plots_raw: Array = data.get("plots", []) if typeof(data.get("plots", [])) == TYPE_ARRAY else []
	var alchemy_raw: Array = data.get("alchemy", []) if typeof(data.get("alchemy", [])) == TYPE_ARRAY else []
	var plots := _plots(plots_raw, content, now_unix)
	var alchemy := _alchemy(alchemy_raw, content, now_unix)
	var seeds_cfg: Array = cfg.get("seeds", []) if typeof(cfg.get("seeds", [])) == TYPE_ARRAY else []
	var recipes_cfg: Array = cfg.get("recipes", []) if typeof(cfg.get("recipes", [])) == TYPE_ARRAY else []
	var recipes_state: Array = data.get("recipes", []) if typeof(data.get("recipes", [])) == TYPE_ARRAY else []
	var allocation: Dictionary = data.get("allocation", {}) if typeof(data.get("allocation", {})) == TYPE_DICTIONARY else {}
	var upgrades: Dictionary = data.get("upgrades", {}) if typeof(data.get("upgrades", {})) == TYPE_DICTIONARY else {}
	var garden_factor := _factor(data, "garden")
	var alchemy_factor := _factor(data, "alchemy")
	var wood_slug := str(data.get("woodItemSlug", "wood_lingmu"))
	var seed_rows := _seeds(seeds_cfg, state, content, data, garden_factor)
	var seed_total := 0
	for s in seed_rows:
		seed_total += int((s as Dictionary).get("have", 0))
	var seed_hint := ""
	if seed_total <= 0:
		var any_buy := false
		for s in seed_rows:
			if bool((s as Dictionary).get("canBuy", false)):
				any_buy = true
				break
		seed_hint = "暂无种子：可历练掉落" + ("，或点种子袋用灵石兑换" if any_buy else "（首次进洞府会赠种）")
	return {
		"available": true,
		"plotCount": int(data.get("plotCount", plots.size())),
		"alchemyQueueLength": int(data.get("alchemyQueueLength", 2)),
		"claimable": {
			"plots": int(claimable.get("plots", 0)),
			"alchemy": int(claimable.get("alchemy", 0)),
		},
		"cards": _cards(true, claimable, plots, alchemy, upgrades, data.get("arrayDaily", {}), data.get("puppet", {}), data.get("forge", {})),
		"plots": plots,
		"alchemy": alchemy,
		"recipes": _recipes_from_state(recipes_state, recipes_cfg, state, content, alchemy_factor),
		"seeds": seed_rows,
		"seedHint": seed_hint,
		"allocation": {
			"garden": int(allocation.get("garden", 0)),
			"alchemy": int(allocation.get("alchemy", 0)),
		},
		"servantTotal": int(data.get("servantTotal", 0)),
		"servantAssignLingshi": int(data.get("servantAssignLingshi", cfg.get("servantAssignLingshi", 0))),
		"trial": data.get("trial", {}) if typeof(data.get("trial", {})) == TYPE_DICTIONARY else {},
		"alchemyXp": int(data.get("alchemyXp", 0)),
		"gardenLevel": int(data.get("gardenLevel", 1)),
		"alchemyLevel": int(data.get("alchemyLevel", 1)),
		"woodCount": int(data.get("woodCount", bag_count(state, wood_slug))),
		"woodName": item_name(content, wood_slug) if not wood_slug.is_empty() else "灵木",
		"timeScale": {"garden": garden_factor, "alchemy": alchemy_factor},
		"upgrades": upgrades,
		"spiritStones": int(state.get("spiritStones", 0)),
		"arrayDaily": _array_daily(data.get("arrayDaily", {})),
		"puppet": data.get("puppet", {}) if typeof(data.get("puppet", {})) == TYPE_DICTIONARY else {},
		"forge": _forge(data.get("forge", {}), state, content),
		"alchemyMaterials": _material_bar(state, content, ["herb_lingcao", "herb_qingxin", "wood_lingmu"]),
		"forgeMaterials": _forge_material_bar(data.get("forge", {}), state, content),
		"hubEntries": data.get("hubEntries", ["puppet", "garden", "alchemy", "forge"]),
		"hint": "",
	}


static func _cards(available: bool, claimable: Dictionary, plots: Array, alchemy: Array, upgrades: Dictionary, array_daily: Variant = {}, puppet: Variant = {}, forge: Variant = {}) -> Array[Dictionary]:
	var growing := 0
	for plot in plots:
		if str((plot as Dictionary).get("status", "")) == "growing":
			growing += 1
	var crafting := 0
	for job in alchemy:
		if str((job as Dictionary).get("status", "")) == "crafting":
			crafting += 1
	var plot_ready := int(claimable.get("plots", 0))
	var alchemy_ready := int(claimable.get("alchemy", 0))
	var out: Array[Dictionary] = []
	for spec in FACILITIES:
		var id := str(spec.id)
		var subtitle := str(spec.blurb)
		var ready := 0
		var progress := 0
		var can_upgrade := false
		var facility: Variant = upgrades.get(id, {})
		if typeof(facility) == TYPE_DICTIONARY:
			can_upgrade = bool((facility as Dictionary).get("canUpgrade", false))
		if id == "garden":
			ready = plot_ready
			progress = growing
			if available:
				subtitle = ("可领取 %d" % ready) if ready > 0 else (("种植中 %d" % progress) if progress > 0 else "空闲可种植")
				if can_upgrade:
					subtitle = "%s · 可升级" % subtitle
		elif id == "alchemy":
			ready = alchemy_ready
			progress = crafting
			if available:
				subtitle = ("可领取 %d" % ready) if ready > 0 else (("炼制中 %d" % progress) if progress > 0 else "空闲可炼丹")
				if can_upgrade:
					subtitle = "%s · 可升级" % subtitle
		elif id == "puppet":
			var pd: Dictionary = puppet if typeof(puppet) == TYPE_DICTIONARY else {}
			var idle := int(pd.get("idle", 0))
			var starved := bool(pd.get("meatStarved", false))
			if available:
				if starved:
					subtitle = "肉空停产 · 闲置 %d" % idle
				else:
					subtitle = "闲置 %d · 可派工" % idle
			ready = 1 if starved else 0
		elif id == "forge":
			var fd: Dictionary = forge if typeof(forge) == TYPE_DICTIONARY else {}
			ready = int(fd.get("claimable", 0))
			var jobs: Array = fd.get("jobs", []) if typeof(fd.get("jobs", [])) == TYPE_ARRAY else []
			for job in jobs:
				if typeof(job) == TYPE_DICTIONARY and str((job as Dictionary).get("status", "")) == "crafting":
					progress += 1
			if available:
				subtitle = ("可领取 %d" % ready) if ready > 0 else (("开炼中 %d" % progress) if progress > 0 else "选图纸开炼")
		out.append({
			"id": id,
			"name": str(spec.name),
			"sprite": str(spec.sprite),
			"blurb": str(spec.blurb),
			"subtitle": subtitle,
			"claimable": ready,
			"can_upgrade": can_upgrade,
			"in_progress": progress,
			"available": available,
		})
	return out


static func _plots(rows: Array, content: Dictionary, now_unix: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var plot := row as Dictionary
		var status := str(plot.get("status", "empty"))
		var seed_slug := str(plot.get("seedSlug", "")) if plot.get("seedSlug", null) != null else ""
		var herb_slug := str(plot.get("herbSlug", "")) if plot.get("herbSlug", null) != null else ""
		var mature := str(plot.get("matureAt", "")) if plot.get("matureAt", null) != null else ""
		var line := "空地 · 点此种植"
		match status:
			"growing":
				line = "%s · %s" % [item_name(content, seed_slug), remaining_text(mature, now_unix)]
			"ready":
				line = "%s · 可领取" % item_name(content, herb_slug if not herb_slug.is_empty() else seed_slug)
		out.append({
			"slot": int(plot.get("slot", out.size())),
			"seedSlug": seed_slug,
			"herbSlug": herb_slug,
			"plantedAt": str(plot.get("plantedAt", "")) if plot.get("plantedAt", null) != null else "",
			"matureAt": mature,
			"status": status,
			"title": "地块 %d" % (int(plot.get("slot", out.size())) + 1),
			"line": line,
			"seedName": item_name(content, seed_slug),
			"herbName": item_name(content, herb_slug),
		})
	return out


static func _alchemy(rows: Array, content: Dictionary, now_unix: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var job := row as Dictionary
		var status := str(job.get("status", "crafting"))
		var output := str(job.get("outputItemSlug", ""))
		var ready := str(job.get("readyAt", "")) if job.get("readyAt", null) != null else ""
		var line := "%s ×%d" % [item_name(content, output), int(job.get("outputQty", 1))]
		if status == "crafting":
			line = "%s · %s" % [line, remaining_text(ready, now_unix)]
		else:
			line = "%s · 可领取" % line
		out.append({
			"id": str(job.get("id", "")),
			"recipeSlug": str(job.get("recipeSlug", "")),
			"startedAt": str(job.get("startedAt", "")) if job.get("startedAt", null) != null else "",
			"readyAt": ready,
			"status": status,
			"outputItemSlug": output,
			"outputQty": int(job.get("outputQty", 1)),
			"outputName": item_name(content, output),
			"line": line,
		})
	return out


## 优先用 state.dongfu.seedOffers（运行时）；否则回落 content.globals.dongfu。
static func _seed_offers(dongfu_state: Dictionary, content: Dictionary) -> Dictionary:
	var offers: Dictionary = {}
	var rows: Array = []
	if typeof(dongfu_state.get("seedOffers", null)) == TYPE_ARRAY:
		rows = dongfu_state.get("seedOffers", [])
	else:
		var cfg := config_of(content)
		rows = cfg.get("seedOffers", []) if typeof(cfg.get("seedOffers", [])) == TYPE_ARRAY else []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var slug := str((row as Dictionary).get("seedSlug", ""))
		if slug.is_empty():
			continue
		offers[slug] = {
			"seedSlug": slug,
			"spiritStones": int((row as Dictionary).get("spiritStones", 0)),
			"quantity": int((row as Dictionary).get("quantity", 1)),
		}
	return offers


static func _seeds(rows: Array, state: Dictionary, content: Dictionary, dongfu_state: Dictionary = {}, factor: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var offers := _seed_offers(dongfu_state, content)
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var seed := row as Dictionary
		var slug := str(seed.get("seedSlug", ""))
		var have := bag_count(state, slug)
		var offer: Dictionary = offers.get(slug, {}) if typeof(offers.get(slug, {})) == TYPE_DICTIONARY else {}
		out.append({
			"seedSlug": slug,
			"herbSlug": str(seed.get("herbSlug", "")),
			"growSeconds": _scaled_seconds(int(seed.get("growSeconds", 0)), factor),
			"baseGrowSeconds": int(seed.get("growSeconds", 0)),
			"name": item_name(content, slug),
			"herbName": item_name(content, str(seed.get("herbSlug", ""))),
			"have": have,
			"canPlant": have > 0,
			"canBuy": not offer.is_empty() and int(offer.get("spiritStones", 0)) > 0,
			"buyStones": int(offer.get("spiritStones", 0)),
			"buyQty": int(offer.get("quantity", 1)),
		})
	return out




static func _recipes_from_state(state_rows: Array, cfg_rows: Array, state: Dictionary, content: Dictionary, factor: float = 1.0) -> Array[Dictionary]:
	if state_rows.is_empty():
		return _recipes(cfg_rows, state, content, factor)
	var out: Array[Dictionary] = []
	for row in state_rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var recipe := row as Dictionary
		if bool(recipe.get("locked", false)):
			out.append({
				"recipeSlug": str(recipe.get("recipeSlug", "")),
				"title": "未悟丹方",
				"locked": true,
				"discoverMode": "hidden",
				"canCraft": false,
				"costLine": "试炼悟得后可一键炼",
				"costs": [],
				"spiritStones": 0,
				"craftSeconds": 0,
				"outputName": "",
				"outputQty": 0,
			})
			continue
		# Reuse cost/canCraft logic via a one-element cfg-shaped row.
		var shaped := {
			"recipeSlug": str(recipe.get("recipeSlug", "")),
			"outputItemSlug": str(recipe.get("outputItemSlug", "")),
			"outputQty": int(recipe.get("outputQty", 1)),
			"craftSeconds": int(recipe.get("craftSeconds", 0)),
			"spiritStones": int(recipe.get("spiritStones", 0)),
			"costs": recipe.get("costs", []),
		}
		var built := _recipes([shaped], state, content, factor)
		if built.is_empty():
			continue
		var item: Dictionary = built[0]
		item["locked"] = false
		item["discoverMode"] = str(recipe.get("discoverMode", "starter"))
		out.append(item)
	return out

static func _recipes(rows: Array, state: Dictionary, content: Dictionary, factor: float = 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var recipe := row as Dictionary
		var costs_raw: Array = recipe.get("costs", []) if typeof(recipe.get("costs", [])) == TYPE_ARRAY else []
		var costs: Array[Dictionary] = []
		var can_craft := true
		for cost in costs_raw:
			if typeof(cost) != TYPE_DICTIONARY:
				continue
			var c := cost as Dictionary
			var slug := str(c.get("itemSlug", ""))
			var need := int(c.get("count", 0))
			var have := bag_count(state, slug)
			if have < need:
				can_craft = false
			costs.append({"itemSlug": slug, "name": item_name(content, slug), "need": need, "have": have})
		var stones := int(recipe.get("spiritStones", 0))
		if stones > 0 and int(state.get("spiritStones", 0)) < stones:
			can_craft = false
		var output := str(recipe.get("outputItemSlug", ""))
		var output_name := item_name(content, output)
		var output_qty := int(recipe.get("outputQty", 1))
		out.append({
			"recipeSlug": str(recipe.get("recipeSlug", "")),
			"outputItemSlug": output,
			"outputName": output_name,
			"outputQty": output_qty,
			# 可见标题只用产出中文名。recipeSlug 只留给请求，不进文案。
			"title": "%s ×%d" % [output_name if not output_name.is_empty() else UNKNOWN_ITEM_NAME, output_qty],
			"craftSeconds": _scaled_seconds(int(recipe.get("craftSeconds", 0)), factor),
			"baseCraftSeconds": int(recipe.get("craftSeconds", 0)),
			"spiritStones": stones,
			"costs": costs,
			"canCraft": can_craft,
			"costLine": _cost_line(costs, stones),
		})
	return out


static func _cost_line(costs: Array[Dictionary], spirit_stones: int) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		parts.append("%s %s" % [str(cost.get("name", "")), "拥有 %d · 需要 %d" % [int(cost.get("have", 0)), int(cost.get("need", 0))]])
	if spirit_stones > 0:
		parts.append("灵石 ×%d" % spirit_stones)
	return "、".join(parts)

static func _material_bar(state: Dictionary, content: Dictionary, slugs: Array) -> Array:
	var out: Array = []
	for slug_v in slugs:
		var slug := str(slug_v)
		if slug.is_empty():
			continue
		out.append({
			"itemSlug": slug,
			"name": item_name(content, slug),
			"have": bag_count(state, slug),
		})
	return out


static func _forge_material_bar(forge_raw: Variant, state: Dictionary, content: Dictionary) -> Array:
	var forge: Dictionary = forge_raw if typeof(forge_raw) == TYPE_DICTIONARY else {}
	var bps: Array = forge.get("blueprints", []) if typeof(forge.get("blueprints", [])) == TYPE_ARRAY else []
	var seen: Dictionary = {}
	var slugs: Array = []
	for bp_v in bps:
		if typeof(bp_v) != TYPE_DICTIONARY:
			continue
		var costs: Array = (bp_v as Dictionary).get("costs", []) if typeof((bp_v as Dictionary).get("costs", [])) == TYPE_ARRAY else []
		for c in costs:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var slug := str((c as Dictionary).get("itemSlug", ""))
			if slug.is_empty() or seen.has(slug):
				continue
			seen[slug] = true
			slugs.append(slug)
	if slugs.is_empty():
		slugs = ["wood_lingmu", "herb_lingcao", "puppet_stone"]
	return _material_bar(state, content, slugs)


static func _forge(forge_raw: Variant, state: Dictionary, content: Dictionary) -> Dictionary:
	var forge: Dictionary = forge_raw if typeof(forge_raw) == TYPE_DICTIONARY else {}
	var jobs_raw: Array = forge.get("jobs", []) if typeof(forge.get("jobs", [])) == TYPE_ARRAY else []
	var jobs: Array = []
	for row in jobs_raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var job := (row as Dictionary).duplicate(true)
		var status := str(job.get("status", "crafting"))
		var bp := str(job.get("blueprintSlug", ""))
		var output := str(job.get("outputItemSlug", "")) if job.get("outputItemSlug", null) != null else ""
		var ready := str(job.get("readyAt", "")) if job.get("readyAt", null) != null else ""
		var title := item_name(content, output) if not output.is_empty() else bp
		if status == "ready":
			job["line"] = "%s · 可领取" % title
		else:
			var remain := remaining_text(ready)
			job["line"] = "%s · %s" % [title if not title.is_empty() else "炼器中", remain if not remain.is_empty() else "炼制中"]
		jobs.append(job)
	var bps_raw: Array = forge.get("blueprints", []) if typeof(forge.get("blueprints", [])) == TYPE_ARRAY else []
	var blueprints: Array = []
	for row in bps_raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var bp := (row as Dictionary).duplicate(true)
		var costs_raw: Array = bp.get("costs", []) if typeof(bp.get("costs", [])) == TYPE_ARRAY else []
		var costs: Array[Dictionary] = []
		var can_craft := true
		for c in costs_raw:
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var cost := c as Dictionary
			var slug := str(cost.get("itemSlug", ""))
			var need := int(cost.get("count", cost.get("need", 0)))
			var have := bag_count(state, slug)
			if have < need:
				can_craft = false
			costs.append({"itemSlug": slug, "name": item_name(content, slug), "need": need, "have": have})
		bp["costs"] = costs
		bp["canCraft"] = can_craft
		bp["costLine"] = _cost_line(costs, 0)
		if str(bp.get("displayName", "")).is_empty():
			bp["displayName"] = str(bp.get("blueprintSlug", "图纸"))
		blueprints.append(bp)
	return {
		"jobs": jobs,
		"blueprints": blueprints,
		"claimable": int(forge.get("claimable", 0)),
		"forgeXp": int(forge.get("forgeXp", 0)),
		"baseOrangeChance": float(forge.get("baseOrangeChance", 0.0)),
		"orangeChanceCap": float(forge.get("orangeChanceCap", 0.0)),
	}


static func _array_daily(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {"enabled": false, "clearedToday": false, "dayKey": "", "arrayXp": 0, "puzzle": {}}
	var ad := raw as Dictionary
	var puzzle: Variant = ad.get("puzzle", {})
	return {
		"enabled": bool(ad.get("enabled", false)),
		"clearedToday": bool(ad.get("clearedToday", false)),
		"dayKey": str(ad.get("dayKey", "")),
		"arrayXp": int(ad.get("arrayXp", 0)),
		"puzzle": puzzle if typeof(puzzle) == TYPE_DICTIONARY else {},
	}

