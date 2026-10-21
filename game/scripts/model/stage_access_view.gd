class_name StageAccessView
extends RefCounted
## 第三批：历练页关卡列表的数据（纯函数，好测）。
## 关卡顺序 = 章节 sortOrder → 关卡 sortOrder（和服务端 orderedStages 一样）；
## 能不能打全看服务器 /me/state.stageAccess（击败上一关首领 + 境界），客户端不自己猜。
## 每关一张卡：怪物（挂机）+ 首领（精英 / 章末首领）、推荐战力、解锁条件、今日奖励次数、按钮状态。


## content.chapters 按 sortOrder 排好；关卡没挂章节的放到最后一个「其他」组。
static func chapters(content: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var access := access_map(state)
	var rows: Array[Dictionary] = []
	for row in content.get("chapters", []):
		if typeof(row) == TYPE_DICTIONARY and bool((row as Dictionary).get("enabled", true)):
			rows.append(row as Dictionary)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("sortOrder", 0)) < int(b.get("sortOrder", 0)))
	var out: Array[Dictionary] = []
	var seen := {}
	for chapter in rows:
		var slug := str(chapter.get("slug", ""))
		seen[slug] = true
		out.append(_chapter(chapter, _stages_of(content, slug), access, content))
	var loose := _stages_of(content, "", seen)
	if not loose.is_empty():
		out.append(_chapter({"slug": "", "displayName": "其他", "bgKey": "", "bossFx": "default"}, loose, access, content))
	return out.filter(func(c: Dictionary) -> bool: return not (c.cards as Array).is_empty())


static func access_map(state: Dictionary) -> Dictionary:
	var map := {}
	for row in state.get("stageAccess", []) if typeof(state.get("stageAccess", null)) == TYPE_ARRAY else []:
		if typeof(row) == TYPE_DICTIONARY:
			map[str((row as Dictionary).get("slug", ""))] = row
	return map


static func _stages_of(content: Dictionary, chapter_slug: String, exclude: Dictionary = {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for row in content.get("stages", []):
		if typeof(row) != TYPE_DICTIONARY or not bool((row as Dictionary).get("enabled", true)):
			continue
		var own := BagModel.plain((row as Dictionary).get("chapterSlug", null))
		if exclude.is_empty():
			if own != chapter_slug:
				continue
		elif exclude.has(own):
			continue
		found.append(row as Dictionary)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("sortOrder", 0)) < int(b.get("sortOrder", 0)))
	return found


static func _chapter(chapter: Dictionary, stages: Array[Dictionary], access: Dictionary, content: Dictionary) -> Dictionary:
	var cards: Array[Dictionary] = []
	for stage in stages:
		cards.append(card(stage, access.get(str(stage.get("slug", "")), {}), content))
	var open := false
	var lock_text := ""
	for c in cards:
		if bool(c.unlocked):
			open = true
	if not open and not cards.is_empty():
		lock_text = (cards[0].needs_lines as Array)[0].text if not (cards[0].needs_lines as Array).is_empty() else "未解锁"
	return {
		"slug": str(chapter.get("slug", "")), "name": str(chapter.get("displayName", chapter.get("slug", ""))),
		"bg_key": BagModel.plain(chapter.get("bgKey", null)), "boss_fx": BagModel.plain(chapter.get("bossFx", null)) if chapter.get("bossFx", null) != null else "default",
		"cards": cards, "unlocked": open, "lock_text": lock_text,
	}


static func _realm_name(content: Dictionary, order: int) -> String:
	for row in content.get("realms", []):
		if typeof(row) == TYPE_DICTIONARY and int((row as Dictionary).get("sortOrder", -1)) == order:
			return str((row as Dictionary).get("displayName", ""))
	return "境界 %d" % order


## 一张关卡卡的数据。acc = stageAccess 里这一关（没有 = 服务器没给，按未解锁处理）。
static func card(stage: Dictionary, acc: Dictionary, content: Dictionary) -> Dictionary:
	var bosses: Array = stage.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	var monsters: Array = stage.get("monsters", [])
	var monster: Dictionary = monsters[0] if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else {}
	var tier := str(acc.get("tier", boss.get("tier", stage.get("tier", "elite"))))
	var needs: Dictionary = acc.get("needs", {}) if typeof(acc.get("needs", null)) == TYPE_DICTIONARY else {}
	var lines: Array[Dictionary] = []
	var win: Variant = needs.get("bossWin", null)
	if typeof(win) == TYPE_DICTIONARY:
		var who := str((win as Dictionary).get("bossName", ""))
		var kind := "首领"  # 第四批：不再区分精英 / 章末首领
		lines.append({"ok": bool((win as Dictionary).get("met", false)), "text": "击败%s「%s」" % [kind, who]})
	var realm: Variant = needs.get("realm", null)
	if typeof(realm) == TYPE_DICTIONARY:
		lines.append({"ok": bool((realm as Dictionary).get("met", false)), "text": "达到%s" % _realm_name(content, int((realm as Dictionary).get("order", 0)))})
	var rules: Dictionary = boss.get("rules", {}) if typeof(boss.get("rules", null)) == TYPE_DICTIONARY else {}
	return {
		"slug": str(stage.get("slug", "")), "name": str(stage.get("displayName", stage.get("slug", ""))), "tier": tier,
		"boss_name": str(boss.get("name", "")), "boss_art": BagModel.plain(boss.get("artKey", null)), "has_boss": not boss.is_empty(),
		"monster_name": str(monster.get("name", "")), "monster_art": BagModel.plain(monster.get("artKey", null)),
		"recommended": int(stage.get("recommendedPower", 0)),
		"unlocked": bool(acc.get("unlocked", false)), "realm_ok": bool(acc.get("realmOk", false)),
		"playable": bool(acc.get("playable", false)), "cleared": bool(acc.get("cleared", false)),
		"needs_lines": lines, "rules": rules, "first_clear": boss.get("firstClear", []), "repeat": boss.get("repeat", null),
	}


## 今日首领挑战次数 {used, limit, left}；这一关不发重复奖励返回空字典。
## 第四批：次数是全局的（state.bossDailyTotal {used, limit}，所有首领共用一个每日总数，挂机刷出的首领默认不算）；
## 老服务器没有 bossDailyTotal 时退回按关的 bossDaily + rules.dailyRewardLimit。
static func daily(card_data: Dictionary, state: Dictionary) -> Dictionary:
	var rules: Dictionary = card_data.get("rules", {})
	if not bool(rules.get("allowRepeat", true)) or not bool(rules.get("repeatRewards", true)):
		return {}
	var total: Variant = state.get("bossDailyTotal", null)
	if typeof(total) == TYPE_DICTIONARY:
		var cap := int((total as Dictionary).get("limit", 0))
		if cap <= 0:
			return {}
		var spent := int((total as Dictionary).get("used", 0))
		return {"used": spent, "limit": cap, "left": maxi(0, cap - spent)}
	var limit := int(rules.get("dailyRewardLimit", 0))
	var used := 0
	for row in state.get("bossDaily", []) if typeof(state.get("bossDaily", null)) == TYPE_ARRAY else []:
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("stageSlug", "")) == str(card_data.slug):
			used = int((row as Dictionary).get("used", 0))
			limit = int((row as Dictionary).get("limit", limit))
	if limit <= 0:
		return {}
	return {"used": used, "limit": limit, "left": maxi(0, limit - used)}


## 卡片按钮：{text, sub, kind(o/m/g), enabled, state(locked/new/repeat/done)}。
## 未解锁 → 灰「未解锁」；没打过 → 橙「挑 战」+ 首通奖励；打过且能重复：有奖励次数 → 橙「再 战」，
## 次数用完 → 灰「明日再来」，不发重复奖励 → 薄荷「再 战」+ 无奖励；不能重复 → 灰「已击败」。
static func button(card_data: Dictionary, state: Dictionary) -> Dictionary:
	if not bool(card_data.get("has_boss", false)):
		return {"text": "无首领", "sub": "", "kind": "g", "enabled": false, "state": "none"}
	if not bool(card_data.playable):
		return {"text": "未解锁", "sub": "", "kind": "g", "enabled": false, "state": "locked"}
	if not bool(card_data.cleared):
		return {"text": "挑 战", "sub": "首通奖励", "kind": "o", "enabled": true, "state": "new"}
	var rules: Dictionary = card_data.get("rules", {})
	if not bool(rules.get("allowRepeat", true)):
		return {"text": "已击败", "sub": "", "kind": "g", "enabled": false, "state": "done"}
	if not bool(rules.get("repeatRewards", true)):
		return {"text": "再 战", "sub": "首通已领 · 无奖励", "kind": "m", "enabled": true, "state": "repeat"}
	# 次数本身写在卡片首领名后的「今日 n/总」胶囊里（SPEC_Q §17.10），按钮下只写「用 1 次」/「今日次数已用完」
	var day := daily(card_data, state)
	if not day.is_empty() and int(day.left) <= 0:
		return {"text": "明日再来", "sub": "今日次数已用完", "kind": "g", "enabled": false, "state": "spent"}
	return {"text": "再 战", "sub": "用 1 次" if not day.is_empty() else "", "kind": "o", "enabled": true, "state": "repeat"}


## 默认打开哪个章节：挂机所在关的章节 → 第一个有「能打没打过」关卡的章节 → 最后一个解锁的章节。
static func default_chapter(chapters_data: Array[Dictionary], idle_slug: String) -> String:
	for chapter in chapters_data:
		for c in chapter.cards:
			if str(c.slug) == idle_slug and not idle_slug.is_empty():
				return str(chapter.slug)
	for chapter in chapters_data:
		for c in chapter.cards:
			if bool(c.playable) and not bool(c.cleared):
				return str(chapter.slug)
	var last := ""
	for chapter in chapters_data:
		if bool(chapter.unlocked):
			last = str(chapter.slug)
	return last if not last.is_empty() or chapters_data.is_empty() else str(chapters_data[0].slug)


## 默认选中哪一关：第一个「能打没打过」的；都打过了选最后一个能打的；都不能打选第一张。
static func default_stage(chapters_data: Array[Dictionary]) -> String:
	var last := ""
	for chapter in chapters_data:
		for c in chapter.cards:
			if bool(c.playable) and not bool(c.cleared) and bool(c.has_boss):
				return str(c.slug)
			if bool(c.playable):
				last = str(c.slug)
	if not last.is_empty():
		return last
	return str((chapters_data[0].cards as Array)[0].slug) if not chapters_data.is_empty() else ""


## 关卡所在章节（找不到返回空字典）。
static func chapter_of(chapters_data: Array[Dictionary], stage_slug: String) -> Dictionary:
	for chapter in chapters_data:
		for c in chapter.cards:
			if str(c.slug) == stage_slug:
				return chapter
	return {}


## 章节 slug → 章节配置（content.chapters 原样）。
static func chapter_row(content: Dictionary, chapter_slug: String) -> Dictionary:
	for row in content.get("chapters", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == chapter_slug:
			return row
	return {}


## 挂机刷首领结果提示（lastSettle.idleBoss：{bossName, spawns, wins, losses, rewarded, bagFull, ...}）。没有返回 ""。
static func idle_boss_text(last_settle: Variant) -> String:
	if typeof(last_settle) != TYPE_DICTIONARY:
		return ""
	var idle: Variant = (last_settle as Dictionary).get("idleBoss", null)
	if typeof(idle) != TYPE_DICTIONARY:
		return ""
	var row := idle as Dictionary
	var spawns := int(row.get("spawns", 0))
	if spawns <= 0:
		return ""
	var wins := int(row.get("wins", 0))
	var text := "挂机遇到首领「%s」%d 次，胜 %d 次" % [str(row.get("bossName", "")), spawns, wins]
	var got := 0
	for drop in row.get("drops", []):
		if typeof(drop) == TYPE_DICTIONARY and not bool((drop as Dictionary).get("dropped", false)):
			got += 1
	if got > 0:
		text += "，获得 %d 件物品" % got
	if bool(row.get("bagFull", false)):
		text += "（行囊已满，装备未拾取）"
	return text


## 自动挑战结果提示（lastSettle.autoChallenge）。没有返回 ""。
static func auto_challenge_text(last_settle: Variant) -> String:
	if typeof(last_settle) != TYPE_DICTIONARY:
		return ""
	var auto: Variant = (last_settle as Dictionary).get("autoChallenge", null)
	if typeof(auto) != TYPE_DICTIONARY:
		return ""
	var row := auto as Dictionary
	var kind := "首领"  # 第四批：不再区分精英 / 章末首领
	if bool(row.get("win", false)):
		var count := 0
		for drop in row.get("drops", []):
			if typeof(drop) == TYPE_DICTIONARY and not bool((drop as Dictionary).get("dropped", false)):
				count += 1
		var full := "（行囊已满，装备未拾取）" if bool(row.get("bagFull", false)) else ""
		return "自动挑战%s「%s」胜利%s%s" % [kind, str(row.get("bossName", "")), ("，获得 %d 件物品" % count) if count > 0 else "", full]
	return "自动挑战%s「%s」失败，稍后再试" % [kind, str(row.get("bossName", ""))]
