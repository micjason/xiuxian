class_name BreakthroughView
extends RefCounted
## 境界突破流程界面的数据：条件（修为、必须击败的首领）、突破前后的属性与战力。
## 服务器在 state.breakthrough 里给：cost、nextSlug、rateBp、requiredStage{slug,name,bossName,cleared}、preview{...}。
## 修为条件超出的部分会保留（突破只扣 cost）。数值用服务器小数，显示时取整。

const STAT_ROWS: Array[Dictionary] = [
	{"key": "hp", "name": "生命", "icon": "res_bag"},
	{"key": "attack", "name": "攻击", "icon": "tab_adventure"},
	{"key": "defense", "name": "防御", "icon": "res_power"},
	{"key": "speed", "name": "速度", "icon": "res_cultivation"},
]


static func build(state: Dictionary, next_realm_name: String = "") -> Dictionary:
	var breakthrough: Dictionary = state.get("breakthrough", {}) if typeof(state.get("breakthrough", null)) == TYPE_DICTIONARY else {}
	var next_slug := BagModel.plain(breakthrough.get("nextSlug", null))
	var cultivation := float(state.get("cultivation", 0))
	var cost := float(breakthrough.get("cost", 0))
	var gate: Dictionary = breakthrough.get("requiredStage", {}) if typeof(breakthrough.get("requiredStage", null)) == TYPE_DICTIONARY else {}
	var preview: Dictionary = breakthrough.get("preview", {}) if typeof(breakthrough.get("preview", null)) == TYPE_DICTIONARY else {}
	var has_gate := not gate.is_empty()
	var cultivation_ok := cultivation >= cost
	var boss_ok := not has_gate or bool(gate.get("cleared", false))
	var power_now := int(state.get("power", 0))
	var power_after := int(round(float(preview.get("power", power_now)))) if not preview.is_empty() else power_now
	var gain_percent := 0.0 if power_now <= 0 else (float(power_after - power_now) / float(power_now)) * 100.0
	var rows: Array[Dictionary] = []
	for row in STAT_ROWS:
		var key := str(row.key)
		var before := float(state.get(key, 0))
		var after := float(preview.get(key, before)) if not preview.is_empty() else before
		rows.append({"key": key, "name": row.name, "before": before, "after": after, "delta": after - before})
	var out_name := next_realm_name if not next_realm_name.is_empty() else str(preview.get("realmName", ""))
	var button_text := "开始突破"
	var hint := "突破必定成功，超出的修为会保留"
	var can_start := next_slug != "" and cultivation_ok and boss_ok
	if next_slug.is_empty():
		button_text = "已至最高境界"
		hint = "当前已是最高境界"
	elif not cultivation_ok:
		hint = "修为还差 %s" % CultivationFormat.amount(cost - cultivation)
	elif not boss_ok:
		hint = "先击败首领「%s」" % str(gate.get("bossName", gate.get("name", "")))
	return {
		"has_next": next_slug != "",
		"next_name": out_name,
		"cultivation": cultivation,
		"cost": cost,
		"cultivation_ok": cultivation_ok,
		"cultivation_ratio": clampf(cultivation / maxf(cost, 1.0), 0.0, 1.0),
		"has_gate": has_gate,
		"gate_stage": str(gate.get("slug", "")),
		"gate_stage_name": str(gate.get("name", "")),
		"gate_boss": str(gate.get("bossName", "")),
		"boss_ok": boss_ok,
		"power_now": power_now,
		"power_after": power_after,
		"power_delta": power_after - power_now,
		"power_gain_percent": gain_percent,
		"rows": rows,
		"rate_percent": int(round(float(breakthrough.get("rateBp", 0)) / 100.0)),
		"can_start": can_start,
		"button_text": button_text,
		"hint": hint,
		"cost_text": "消耗修为 %s · 成功率 %d%%" % [CultivationFormat.amount(cost), int(round(float(breakthrough.get("rateBp", 0)) / 100.0))],
		"gain_per_tick_before": float((state.get("cultivationRate", {}) as Dictionary).get("gainPerTick", 0)) if typeof(state.get("cultivationRate", null)) == TYPE_DICTIONARY else 0.0,
		"gain_per_tick_after": float(preview.get("gainPerTick", 0)),
		"ult_after": preview.get("ult", null),
		"new_stages": preview.get("newStages", []),
		"preview_ok": not preview.is_empty(),
	}


## 突破成功后的对比（用突破前的 state 和突破后的 state）。
static func success_summary(before: Dictionary, after: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	for row in STAT_ROWS:
		var key := str(row.key)
		var b := float(before.get(key, 0))
		var a := float(after.get(key, 0))
		rows.append({"key": key, "name": row.name, "before": b, "after": a, "delta": a - b})
	var power_before := int(before.get("power", 0))
	var power_after := int(after.get("power", 0))
	return {
		"from_name": str(before.get("realmName", "")),
		"to_name": str(after.get("realmName", "")),
		"rows": rows,
		"power_before": power_before,
		"power_after": power_after,
		"power_delta": power_after - power_before,
		"power_gain_percent": 0.0 if power_before <= 0 else (float(power_after - power_before) / float(power_before)) * 100.0,
	}
