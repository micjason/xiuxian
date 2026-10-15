class_name WaveView
extends RefCounted
## 修炼主界面的波次显示：把 /me/state 的 wave / lastSettle 变成画面要的文字和比例。
## 服务器在每次心跳时结算击杀；两次心跳之间画面按本地经过的秒数推进进度条（只是显示，不改数据）。
## 数值直接用服务器的小数，只在拼文字时取整。


## 当前一波的显示数据。elapsed 是上次拿到状态以来经过的秒数（只在“在线”时推进）。
static func display(state: Dictionary, elapsed: float = 0.0) -> Dictionary:
	var wave: Dictionary = state.get("wave", {}) if typeof(state.get("wave", null)) == TYPE_DICTIONARY else {}
	if not bool(wave.get("available", false)):
		return {"available": false, "ratio": 0.0, "kills": 0, "wave_size": 0, "text": "这里还没有可以刷的怪", "monster": "", "stage": ""}
	var cycle := float(wave.get("cycleSeconds", 0.0)) if wave.get("cycleSeconds", null) != null else 0.0
	var size := int(wave.get("waveSize", 3))
	var kills_per_wave := int(wave.get("killsPerWave", size))
	var progress := float(wave.get("progress", 0.0)) + maxf(elapsed, 0.0)
	var ratio := 0.0
	if cycle > 0.0:
		ratio = fposmod(progress, cycle) / cycle
	var kills := mini(kills_per_wave, int(floor(ratio * float(maxi(kills_per_wave, 1)))))
	var monster: Dictionary = wave.get("monster", {}) if typeof(wave.get("monster", null)) == TYPE_DICTIONARY else {}
	var monster_name := str(monster.get("name", ""))
	var text := "%s · 本波 %d / %d" % [monster_name, kills, size]
	if kills_per_wave <= 0:
		text = "%s · 打不过，反复阵亡" % monster_name
	return {
		"available": true,
		"ratio": ratio,
		"kills": kills,
		"wave_size": size,
		"monster": monster_name,
		"stage": str(wave.get("stageName", "")),
		"text": text,
		"deaths_in_row": int(wave.get("deathsInRow", 0)),
		"kill_cultivation": float(monster.get("killCultivation", 0)),
	}


## 这次结算要给玩家看的反馈（击杀、修为、掉落）。name_of(slug) -> 物品名；没有任何事件时返回空数组。
static func feedback(last: Dictionary, name_of: Callable) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if last.is_empty() or not bool(last.get("online", false)):
		return lines
	var kills := int(last.get("kills", 0))
	if kills > 0:
		var gained := float(last.get("killCultivation", 0))
		lines.append({"kind": "kill", "text": "击败怪物 ×%d · 修为 +%s" % [kills, CultivationFormat.amount(gained)]})
	if int(last.get("deaths", 0)) > 0:
		lines.append({"kind": "death", "text": "阵亡 %d 次，已复活" % int(last.get("deaths", 0))})
	for drop in last.get("drops", []):
		if typeof(drop) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = drop
		var item_name := str(name_of.call(str(row.get("itemSlug", ""))))
		if bool(row.get("dropped", false)):
			lines.append({"kind": "warn", "text": "背包已满，「%s」没能拿到" % item_name})
			continue
		var text := "掉落：%s" % item_name
		if bool(row.get("decomposed", false)):
			text += "（背包已满，自动分解 +%d 强化经验）" % int(row.get("enhanceExp", 0))
		var freed: Array = row.get("freed", [])
		if not freed.is_empty():
			text += "（分解了 %d 件白/绿装备腾出格子）" % freed.size()
		lines.append({"kind": "drop", "quality": str(row.get("quality", "")), "text": text})
	return lines


## 修炼页「历练」入口下的小字：正在刷的关卡名。
static func stage_caption(state: Dictionary) -> String:
	var wave: Dictionary = state.get("wave", {}) if typeof(state.get("wave", null)) == TYPE_DICTIONARY else {}
	return str(wave.get("stageName", "")) if bool(wave.get("available", false)) else ""
