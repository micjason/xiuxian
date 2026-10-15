class_name BattleResultView
extends RefCounted
## 首领战结算页的数据：胜负标题、战后摘要（用时/总伤害/大招次数）、掉落清单、背包相关提示。
## 输入是 POST /me/stages/:slug/challenge 的返回（battle、drops、bagFull、reward；背包满不再拦挑战，也没有开战前腾格）。
## name_of(slug) -> 物品显示名。数值显示时才取整。


static func build(result: Dictionary, boss_name: String, name_of: Callable) -> Dictionary:
	var battle: Dictionary = result.get("battle", {}) if typeof(result.get("battle", null)) == TYPE_DICTIONARY else {}
	var summary := BattleReportBuilder.summary(battle)
	var win := bool(summary.win)
	var title := "挑战成功" if win else "挑战失败"
	var reason := ""
	if win:
		reason = "击败 %s，用时 %.1f 秒" % [boss_name, float(summary.seconds)]
	elif str(summary.reason) == "timeout":
		reason = "时间到：%.0f 秒内没能击败 %s" % [float(summary.seconds), boss_name]
	else:
		reason = "你被 %s 击败，用时 %.1f 秒" % [boss_name, float(summary.seconds)]
	var lines: Array[String] = [
		"我方造成伤害 %s" % OfflineView.grouped(float(summary.dealt)),
		"受到伤害 %s" % OfflineView.grouped(float(summary.taken)),
	]
	var ult_line := "大招释放 %d 次" % int(summary.ults)
	if int(summary.ults) > 0:
		ult_line += "（手动 %d · 自动 %d）" % [int(summary.manual_ults), int(summary.ults) - int(summary.manual_ults)]
	lines.append(ult_line)
	var loot: Array[Dictionary] = []
	var notes: Array[String] = []
	for drop in result.get("drops", []):
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = drop
		var item_name := str(name_of.call(str(row.get("itemSlug", ""))))
		var quantity := int(row.get("quantity", 1))
		var text := item_name if quantity <= 1 else "%s ×%d" % [item_name, quantity]
		if bool(row.get("dropped", false)):
			text += "（背包已满，没有掉落）"
		elif bool(row.get("decomposed", false)):
			text += "（背包已满，自动分解 +%d 强化经验）" % int(row.get("enhanceExp", 0))
		elif not (row.get("freed", []) as Array).is_empty():
			text += "（自动分解了 %d 件白/绿装备腾格）" % (row.get("freed", []) as Array).size()
		loot.append({"text": text, "quality": str(row.get("quality", ""))})
	var reward: Dictionary = result.get("reward", {}) if typeof(result.get("reward", null)) == TYPE_DICTIONARY else {}
	var first_clear := bool(reward.get("firstClear", false))
	if first_clear and float(reward.get("cultivation", 0)) > 0.0:
		notes.append("首通奖励：修为 +%s" % CultivationFormat.amount(float(reward.get("cultivation", 0))))
	if bool(result.get("bagFull", false)):
		notes.append("背包已满，部分装备没有掉落，请先分解装备")
	return {
		"win": win,
		"title": title,
		"reason": reason,
		"lines": lines,
		"loot": loot,
		"notes": notes,
		"first_clear": first_clear,
		"summary": summary,
	}
