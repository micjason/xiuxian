class_name SkillView
extends RefCounted
## 功法页（原型阶段只展示）：列出带修炼加成的功法、当前生效的是哪本、三本功法的离线收益对比。
## 数据：state.skills（skillSlug/level/runningSlot）、content.skills（cultivateBonusBp）、
## state.cultivationRate（gainPerTick）、content.realms（tickSeconds）、content.globals.offlineCapSeconds。
## 对比按一层功法的加成算（服务器的实际加成还要乘层数系数，以 state.cultivationRate.bonusBp 为准）。

const MAX_CARDS := 6


static func build(state: Dictionary, content: Dictionary) -> Dictionary:
	var learned := {}
	for row in state.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY:
			learned[str((row as Dictionary).get("skillSlug", ""))] = row
	var defs: Array[Dictionary] = []
	for row in content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and float((row as Dictionary).get("cultivateBonusBp", 0)) > 0.0 and bool((row as Dictionary).get("enabled", true)):
			defs.append(row)
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("cultivateBonusBp", 0)) < float(b.get("cultivateBonusBp", 0)))
	var cards: Array[Dictionary] = []
	var running_slug := ""
	for def in defs.slice(0, MAX_CARDS):
		var slug := str(def.get("slug", ""))
		var mine: Dictionary = learned.get(slug, {})
		var running := not BagModel.plain(mine.get("runningSlot", null)).is_empty()
		if running:
			running_slug = slug
		var status := "running" if running else ("learned" if not mine.is_empty() else "locked")
		cards.append({
			"slug": slug,
			"name": str(def.get("displayName", slug)),
			"bonus_bp": float(def.get("cultivateBonusBp", 0)),
			"bonus_text": "修炼加成 +%s%%" % _pct(float(def.get("cultivateBonusBp", 0))),
			"status": status,
			"status_text": {"running": "修炼中", "learned": "已习得", "locked": "未获得"}[status],
			"level": int(mine.get("level", 0)),
		})
	var selected_slug := running_slug
	if selected_slug.is_empty():
		for card in cards:
			if str(card.status) == "learned":
				selected_slug = str(card.slug)
	if selected_slug.is_empty() and not cards.is_empty():
		selected_slug = str(cards[0].slug)
	var base_per_second := _base_per_second(state, content)
	var cap := float((content.get("globals", {}) as Dictionary).get("offlineCapSeconds", 28800)) if typeof(content.get("globals", null)) == TYPE_DICTIONARY else 28800.0
	var comparison: Array[Dictionary] = []
	for card in cards:
		card["selected"] = str(card.slug) == selected_slug
		comparison.append({
			"slug": card.slug,
			"name": card.name,
			"bonus_text": "+%s%%" % _pct(float(card.bonus_bp)),
			"total": floorf(base_per_second * cap) + floorf(floorf(base_per_second * cap) * float(card.bonus_bp) / 10000.0),
			"selected": card.selected,
			"status": card.status,
		})
	var learned_count := 0
	for card in cards:
		if str(card.status) != "locked":
			learned_count += 1
	var selected: Dictionary = {}
	for card in cards:
		if bool(card.selected):
			selected = card
	return {
		"cards": cards,
		"selected": selected,
		"comparison": comparison,
		"learned_count": learned_count,
		"total_count": cards.size(),
		"base_per_second": base_per_second,
		"cap_seconds": cap,
		"actual_bonus_percent": float((state.get("cultivationRate", {}) as Dictionary).get("bonusBp", 0)) / 100.0 if typeof(state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0,
	}


static func _pct(bp: float) -> String:
	return ("%.1f" % (bp / 100.0)).trim_suffix(".0")


static func _base_per_second(state: Dictionary, content: Dictionary) -> float:
	var rate: Dictionary = state.get("cultivationRate", {}) if typeof(state.get("cultivationRate", null)) == TYPE_DICTIONARY else {}
	var gain := float(rate.get("gainPerTick", 0))
	var tick := 1.0
	for realm in content.get("realms", []):
		if typeof(realm) == TYPE_DICTIONARY and str((realm as Dictionary).get("slug", "")) == str(state.get("realmSlug", "")):
			tick = maxf(float((realm as Dictionary).get("tickSeconds", 1.0)), 0.1)
	return gain / tick


## 正在生效的功法名（离线弹窗里用）；没有返回空串。
static func running_name(state: Dictionary, content: Dictionary) -> String:
	var view := build(state, content)
	for card in view.cards:
		if str(card.status) == "running":
			return str(card.name)
	return ""
