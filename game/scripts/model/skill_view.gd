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
			"fx_type": str(def.get("fxType", def.get("fx_type", ""))),
			"icon_key": SkillFxFallback.icon_key(str(def.get("fxType", def.get("fx_type", "")))),
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
		"slots": slots_view(state, content),
		"actual_bonus_percent": float((state.get("cultivationRate", {}) as Dictionary).get("bonusBp", 0)) / 100.0 if typeof(state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0,
	}


## 功法栏位（批次②）：state.skillSlots = {open, max, next:{slots, realmOrder, realmName}|null}（后台「配置概览 → 功法栏位」按境界配）。
## 栏位 N 放 runningSlot == "run_N" 的功法；老数据里的其他运转名（如 heart）按顺序补进空的已开放栏位（和服务器 countedSkills 一致）。
## 服务器没下发时按 3 个全开（老规则）。
const DEFAULT_SLOTS := 3


static func slots_view(state: Dictionary, content: Dictionary) -> Dictionary:
	var info: Dictionary = state.get("skillSlots", {}) if typeof(state.get("skillSlots", null)) == TYPE_DICTIONARY else {}
	var open := int(info.get("open", DEFAULT_SLOTS))
	var max_slots := maxi(int(info.get("max", DEFAULT_SLOTS)), open)
	var next: Dictionary = info.get("next", {}) if typeof(info.get("next", null)) == TYPE_DICTIONARY else {}
	var names := {}
	var icons := {}
	for row in content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY:
			var skill_slug := str((row as Dictionary).get("slug", ""))
			names[skill_slug] = str((row as Dictionary).get("displayName", skill_slug))
			icons[skill_slug] = SkillFxFallback.icon_key(str((row as Dictionary).get("fxType", (row as Dictionary).get("fx_type", ""))))
	var placed := {}
	var legacy: Array[String] = []
	for row in state.get("skills", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var slot := BagModel.plain((row as Dictionary).get("runningSlot", null))
		var slug := str((row as Dictionary).get("skillSlug", ""))
		if slot.is_empty():
			continue
		if slot.begins_with("run_") and slot.trim_prefix("run_").is_valid_int():
			placed[int(slot.trim_prefix("run_"))] = slug
		else:
			legacy.append(slug)
	for slug in legacy:
		for index in range(1, open + 1):
			if not placed.has(index):
				placed[index] = slug
				break
	var cells: Array[Dictionary] = []
	for index in range(1, max_slots + 1):
		var is_open := index <= open
		var slug := str(placed.get(index, "")) if is_open else ""
		var hint := ""
		if not is_open:
			hint = ("%s开放" % str(next.get("realmName", ""))) if (index <= int(next.get("slots", 0)) and not str(next.get("realmName", "")).is_empty()) else "未开放"
		cells.append({"index": index, "open": is_open, "skill_slug": slug, "skill_name": str(names.get(slug, slug)), "icon_key": str(icons.get(slug, "")), "hint": hint if not is_open else ("空栏位" if slug.is_empty() else "运转中")})
	var used := 0
	for cell in cells:
		used += 1 if not str(cell.skill_slug).is_empty() else 0
	var note := "技能栏位 %d/%d 已开放" % [open, max_slots]
	if not next.is_empty():
		note += " · %s开放第 %d 栏" % [str(next.get("realmName", "")), int(next.get("slots", open + 1))]
	return {"open": open, "max": max_slots, "used": used, "cells": cells, "note": note}


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
