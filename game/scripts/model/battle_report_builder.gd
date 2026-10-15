class_name BattleReportBuilder
extends RefCounted
## 把服务器返回的战斗结果（battle.log 事件：{t, side, damage, targetHpAfter}）变成文字战报行。
## 战报协议还没有正式定稿：目前只有"谁、第几秒、造成多少伤害、对方剩多少气血"，
## 没有暴击、技能名、状态，因此战报里也只有这些；协议扩展后在这里加映射即可，界面不用改。
## 返回的每一行是 {round, kind(BattleReport.Kind), text, amount}，kind=-1 表示回合标题。

const ROUND_HEAD := -1


static func build(battle: Dictionary, boss_name: String, player_hp: int = 0, boss_hp: int = 0, ult_name: String = "") -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var events: Array = battle.get("log", [])
	var name := boss_name if not boss_name.is_empty() else "首领"
	var round_no := 0
	if player_hp > 0 or boss_hp > 0:
		lines.append({"round": 0, "kind": BattleReport.Kind.PLAIN, "text": "你（气血 %d）对阵 %s（气血 %d）" % [player_hp, name, boss_hp], "amount": 0})
	for event in events:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var side := str((event as Dictionary).get("side", ""))
		# 我方出手开启新回合；首领先手时也算第一回合。
		if side == "player" or round_no == 0:
			round_no += 1
			lines.append({"round": round_no, "kind": ROUND_HEAD, "text": "", "amount": 0})
		var damage := int(round(float((event as Dictionary).get("damage", 0))))
		var left := int(round(float((event as Dictionary).get("targetHpAfter", 0))))
		var time := float((event as Dictionary).get("t", 0))
		if side == "player" and str((event as Dictionary).get("kind", "")) == "ult":
			lines.append({"round": round_no, "kind": BattleReport.Kind.CRIT, "text": "（%.1f秒）释放「%s」，%s 剩余气血 %d" % [time, ult_name if not ult_name.is_empty() else "大招", name, maxi(left, 0)], "amount": damage})
		elif side == "player":
			lines.append({"round": round_no, "kind": BattleReport.Kind.DAMAGE_DEALT, "text": "（%.1f秒）你击中 %s，对方剩余气血 %d" % [time, name, maxi(left, 0)], "amount": damage})
		else:
			lines.append({"round": round_no, "kind": BattleReport.Kind.DAMAGE_TAKEN, "text": "（%.1f秒）%s 反击，你剩余气血 %d" % [time, name, maxi(left, 0)], "amount": damage})
	if events.is_empty():
		lines.append({"round": 0, "kind": BattleReport.Kind.PLAIN, "text": "这场战斗服务器没有返回战报明细。", "amount": 0})
	var won := bool(battle.get("win", false))
	var reason := str(battle.get("reason", ""))
	var seconds := float(battle.get("durationSeconds", 0))
	var result_text := ""
	if won:
		result_text = "胜利！击败 %s，用时 %.1f 秒" % [name, seconds]
	elif reason == "timeout":
		result_text = "失败：%.0f 秒内没能击败 %s" % [seconds, name]
	else:
		result_text = "失败：你被 %s 击败" % name
	lines.append({"round": round_no, "kind": BattleReport.Kind.WIN if won else BattleReport.Kind.LOSE, "text": result_text, "amount": 0})
	return lines


## 战斗中一条事件的短句（实时战报区用）：「你出手，对黑风熊王造成 48 点伤害」之类。
static func live_line(event: Dictionary, boss_name: String, ult_name: String = "") -> Dictionary:
	var damage := int(round(float(event.get("damage", 0))))
	var name := boss_name if not boss_name.is_empty() else "首领"
	if str(event.get("side", "")) == "boss":
		return {"kind": BattleReport.Kind.DAMAGE_TAKEN, "text": "%s 拍击，你受到 %d 点伤害" % [name, damage], "amount": 0}
	if str(event.get("kind", "")) == "ult":
		return {"kind": BattleReport.Kind.CRIT, "text": "「%s」释放，对%s造成 %d 点伤害" % [ult_name if not ult_name.is_empty() else "大招", name, damage], "amount": 0}
	return {"kind": BattleReport.Kind.PLAIN, "text": "你出手，对%s造成 %d 点伤害" % [name, damage], "amount": 0}


## 战后摘要：我方总伤害、受到总伤害、大招次数、用时。
static func summary(battle: Dictionary) -> Dictionary:
	var dealt := 0.0
	var taken := 0.0
	var ults := 0
	var manual := 0
	for event in battle.get("log", []):
		if typeof(event) != TYPE_DICTIONARY:
			continue
		if str((event as Dictionary).get("side", "")) == "player":
			dealt += float((event as Dictionary).get("damage", 0))
			if str((event as Dictionary).get("kind", "")) == "ult":
				ults += 1
		else:
			taken += float((event as Dictionary).get("damage", 0))
	for cast in battle.get("ultCasts", []):
		if typeof(cast) == TYPE_DICTIONARY and bool((cast as Dictionary).get("manual", false)):
			manual += 1
	return {"dealt": int(round(dealt)), "taken": int(round(taken)), "ults": ults, "manual_ults": manual, "seconds": float(battle.get("durationSeconds", 0)), "win": bool(battle.get("win", false)), "reason": str(battle.get("reason", ""))}


## 渲染到 BattleReport 控件。
static func render(report: BattleReport, lines: Array[Dictionary]) -> void:
	report.clear()
	for line in lines:
		var kind: int = int(line.kind)
		if kind == ROUND_HEAD:
			report.add_round(int(line.round))
		elif kind == BattleReport.Kind.WIN or kind == BattleReport.Kind.LOSE:
			report.add_result(kind == BattleReport.Kind.WIN, str(line.text))
		else:
			report.add_line(kind as BattleReport.Kind, str(line.text), int(line.amount))
