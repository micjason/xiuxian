class_name CaveView
extends RefCounted
## 洞府 v1：把 /me/state.dongfu 与 content.globals.dongfu 转成总览 / 药园 / 炼丹界面数据。
## 强化不在此建模——第三卡只由 CavePage 发 enhance_entry_requested。

const FACILITIES := [
	{"id": "garden", "name": "药园", "sprite": "bd_field", "blurb": "种植种子，成熟领取草药"},
	{"id": "alchemy", "name": "炼丹", "sprite": "bd_alchemy", "blurb": "消耗草药炼制丹药"},
	{"id": "enhance", "name": "强化", "sprite": "", "blurb": "前往行囊强化装备"},
]


static func config_of(content: Dictionary) -> Dictionary:
	var globals: Variant = content.get("globals", {})
	if typeof(globals) != TYPE_DICTIONARY:
		return {}
	var raw: Variant = (globals as Dictionary).get("dongfu", null)
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func item_name(content: Dictionary, slug: String) -> String:
	if slug.is_empty():
		return ""
	for row in content.get("items", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return str((row as Dictionary).get("displayName", slug))
	return slug


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


## 总视图：{ available, plotCount, alchemyQueueLength, claimable, cards, plots, alchemy, recipes, seeds }
static func build(state: Dictionary, content: Dictionary, now_unix: float = -1.0) -> Dictionary:
	var dongfu: Variant = state.get("dongfu", null)
	var cfg := config_of(content)
	if typeof(dongfu) != TYPE_DICTIONARY:
		return {
			"available": false,
			"plotCount": 0,
			"alchemyQueueLength": 0,
			"claimable": {"plots": 0, "alchemy": 0},
			"cards": _cards(false, {"plots": 0, "alchemy": 0}, [], []),
			"plots": [],
			"alchemy": [],
			"recipes": [],
			"seeds": [],
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
	return {
		"available": true,
		"plotCount": int(data.get("plotCount", plots.size())),
		"alchemyQueueLength": int(data.get("alchemyQueueLength", 2)),
		"claimable": {
			"plots": int(claimable.get("plots", 0)),
			"alchemy": int(claimable.get("alchemy", 0)),
		},
		"cards": _cards(true, claimable, plots, alchemy),
		"plots": plots,
		"alchemy": alchemy,
		"recipes": _recipes(recipes_cfg, state, content),
		"seeds": _seeds(seeds_cfg, state, content),
		"hint": "",
	}


static func _cards(available: bool, claimable: Dictionary, plots: Array, alchemy: Array) -> Array[Dictionary]:
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
		if id == "garden":
			ready = plot_ready
			progress = growing
			if available:
				subtitle = ("可领取 %d" % ready) if ready > 0 else (("种植中 %d" % progress) if progress > 0 else "空闲可种植")
		elif id == "alchemy":
			ready = alchemy_ready
			progress = crafting
			if available:
				subtitle = ("可领取 %d" % ready) if ready > 0 else (("炼制中 %d" % progress) if progress > 0 else "空闲可炼丹")
		out.append({
			"id": id,
			"name": str(spec.name),
			"sprite": str(spec.sprite),
			"blurb": str(spec.blurb),
			"subtitle": subtitle,
			"claimable": ready,
			"in_progress": progress,
			"available": available or id == "enhance",
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


static func _seeds(rows: Array, state: Dictionary, content: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var seed := row as Dictionary
		var slug := str(seed.get("seedSlug", ""))
		var have := bag_count(state, slug)
		out.append({
			"seedSlug": slug,
			"herbSlug": str(seed.get("herbSlug", "")),
			"growSeconds": int(seed.get("growSeconds", 0)),
			"name": item_name(content, slug),
			"herbName": item_name(content, str(seed.get("herbSlug", ""))),
			"have": have,
			"canPlant": have > 0,
		})
	return out


static func _recipes(rows: Array, state: Dictionary, content: Dictionary) -> Array[Dictionary]:
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
		out.append({
			"recipeSlug": str(recipe.get("recipeSlug", "")),
			"outputItemSlug": output,
			"outputName": item_name(content, output),
			"outputQty": int(recipe.get("outputQty", 1)),
			"craftSeconds": int(recipe.get("craftSeconds", 0)),
			"spiritStones": stones,
			"costs": costs,
			"canCraft": can_craft,
			"costLine": _cost_line(costs, stones),
		})
	return out


static func _cost_line(costs: Array[Dictionary], spirit_stones: int) -> String:
	var parts: PackedStringArray = []
	for cost in costs:
		parts.append("%s %d/%d" % [str(cost.get("name", "")), int(cost.get("have", 0)), int(cost.get("need", 0))])
	if spirit_stones > 0:
		parts.append("灵石 ×%d" % spirit_stones)
	return "、".join(parts)
