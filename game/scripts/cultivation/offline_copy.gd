class_name OfflineCopy
extends RefCounted


static func banner(result: SettlementResult) -> String:
	if result == null:
		return ""
	if result.clock_rewound:
		return "检测到时间回拨，未扣除修为。"
	if result.gained <= 0.0:
		return ""
	return "闭关归来 +%s · %s" % [
		CultivationFormat.amount(result.gained),
		CultivationFormat.duration_hours(result.applied_seconds),
	]


static func dialog(result: SettlementResult, cap_seconds: int) -> String:
	if result == null:
		return ""
	if result.clock_rewound:
		return "检测到时间回拨，未扣除修为。"
	if result.gained <= 0.0:
		return ""
	var lines: PackedStringArray = [
		"闭关归来，修为有所精进。",
		"获得修为：%s" % CultivationFormat.amount(result.gained),
		"结算时长：%s" % CultivationFormat.duration_hours(result.applied_seconds),
	]
	if result.hit_cap:
		lines.append(
			"已顶到离线上限 %s，超出部分未计算。" % CultivationFormat.duration_hours(cap_seconds)
		)
	else:
		lines.append("未顶到 %s 上限。" % CultivationFormat.duration_hours(cap_seconds))
	if result.combat_kills > 0:
		lines.append("历练击杀：%d" % result.combat_kills)
	if not result.combat_loot.is_empty():
		lines.append("入袋：%s" % "、".join(result.combat_loot))
	if result.combat_retreated:
		lines.append("此间有敌手，已退回调息。")
	if result.combat_bag_skipped > 0:
		lines.append("行囊已满，%d 件未入袋。" % result.combat_bag_skipped)
	return "\n".join(lines)
