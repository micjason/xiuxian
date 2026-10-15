class_name PowerBreakdown
extends RefCounted
## 战力构成：把服务器给出的四项属性按战力权重拆成 输出 / 生存 / 先手 三块。
## 权重优先用内容里的 globals.powerWeights，没有就用数值方案默认值。
## 服务器的 power 仍是权威数字；这里的合计与它不同时，差额记为"其他加成"，不隐藏。

const PARTS: Array[Dictionary] = [
	{"id": "output", "name": "输出", "hint": "攻击 × 权重", "stats": ["attack"]},
	{"id": "survival", "name": "生存", "hint": "防御、气血 × 权重", "stats": ["defense", "hp"]},
	{"id": "initiative", "name": "先手", "hint": "速度 × 权重，决定出手快慢", "stats": ["speed"]},
]


static func compute(state: Dictionary, content: Dictionary) -> Dictionary:
	var weights: Dictionary = BagModel.DEFAULT_WEIGHTS.duplicate()
	var globals: Variant = content.get("globals", {})
	if typeof(globals) == TYPE_DICTIONARY:
		var raw: Variant = (globals as Dictionary).get("powerWeights", null)
		if typeof(raw) == TYPE_DICTIONARY:
			for key in BagModel.STAT_KEYS:
				if (raw as Dictionary).has(key):
					weights[key] = float((raw as Dictionary)[key])
	var stats := {}
	for key in BagModel.STAT_KEYS:
		stats[key] = float(state.get(key, 0))
	var parts: Array[Dictionary] = []
	var sum := 0.0
	for part in PARTS:
		var value := 0.0
		for key in part.stats:
			value += float(stats[key]) * float(weights[key])
		sum += value
		parts.append({"id": part.id, "name": part.name, "hint": part.hint, "value": int(round(value)), "ratio": 0.0})
	var server_power := int(state.get("power", int(round(sum))))
	var base := maxf(sum, 1.0)
	for part in parts:
		part["ratio"] = float(part.value) / base
	return {
		"parts": parts,
		"stats": stats,
		"weights": weights,
		"total": server_power,
		"computed": int(round(sum)),
		"other": server_power - int(round(sum)),
	}
