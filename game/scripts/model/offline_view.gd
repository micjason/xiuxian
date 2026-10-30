class_name OfflineView
extends RefCounted
## 离线收益弹窗的数据：把 state.offlineReport 变成界面文字。没有“领取”这一步（修为早已入账），
## 点按钮只是告诉服务器“已读”。数值用服务器给的小数，显示时取整。


static func duration_text(seconds: int) -> String:
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	if hours > 0 and minutes > 0:
		return "%d 小时 %d 分" % [hours, minutes]
	if hours > 0:
		return "%d 小时" % hours
	if minutes > 0:
		return "%d 分钟" % minutes
	return "%d 秒" % seconds


static func clock_text(seconds: int) -> String:
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]


static func grouped(value: float) -> String:
	var whole := int(roundf(absf(value)))
	var raw := str(whole)
	var out := ""
	for index in raw.length():
		if index > 0 and (raw.length() - index) % 3 == 0:
			out += ","
		out += raw[index]
	return ("-" if value < 0.0 else "") + out


## state 里的 offlineReport → 展示字典；没有报告返回空字典。
## skill_name / bonus_percent 由外壳从运转中的功法取（服务器只给了合计加成）。
## name_of(slug) -> 物品显示名（可选）；没有则界面先显示 slug。
## loot / bagFullSkipped 来自离线挂机掉装（修为早已入账，点领取只是已读）。
static func build(report: Variant, skill_name: String = "", bonus_percent: float = 0.0, name_of: Callable = Callable()) -> Dictionary:
	if typeof(report) != TYPE_DICTIONARY or (report as Dictionary).is_empty():
		return {}
	var data: Dictionary = report
	var seconds := int(data.get("seconds", 0))
	var counted := int(data.get("countedSeconds", seconds))
	var cap := int(data.get("offlineCapSeconds", counted))
	var hit_cap := bool(data.get("hitCap", false))
	var wasted := maxi(0, seconds - counted)
	var base := float(data.get("baseGained", 0))
	var bonus := float(data.get("bonusGained", 0))
	var total := float(data.get("gained", base + bonus))
	var bag_full := bool(data.get("bagFullSkipped", false))
	return {
		"id": str(data.get("id", "")),
		"away_text": duration_text(seconds),
		"counted_text": "计入 %s" % duration_text(counted),
		"bar_ratio": clampf(float(counted) / float(maxi(cap, 1)), 0.0, 1.0),
		"bar_text": "计入 %s / %s" % [clock_text(counted), clock_text(cap)],
		"hit_cap": hit_cap,
		"cap_note": "已满 %s，多出的 %s已作废" % [duration_text(cap), duration_text(wasted)] if hit_cap and wasted > 0 else "未达上限，按实际时长计入",
		"total": total,
		"total_text": "+" + grouped(total),
		"base_text": grouped(base),
		"bonus": bonus,
		"bonus_text": "+" + grouped(bonus),
		"skill_label": "技能《%s》" % skill_name if not skill_name.is_empty() else "技能加成",
		"bonus_percent_text": "+%s%%" % ("%.1f" % bonus_percent).trim_suffix(".0") if bonus_percent > 0.0 else "",
		"formula_text": "%s + %s = %s" % [grouped(base), grouped(bonus), grouped(total)],
		"realm": str(data.get("realmName", "")),
		"items": loot_items(data, name_of),
		"bag_full_skipped": bag_full,
		"bag_full_note": "行囊已满，部分装备未入包" if bag_full else "",
	}


## offlineReport.loot → 弹窗战利品行。每项：slug / quantity / quality / name / text。
static func loot_items(report: Dictionary, name_of: Callable = Callable()) -> Array:
	var raw: Variant = report.get("loot", report.get("items", []))
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var slug := str(row.get("itemSlug", row.get("slug", ""))).strip_edges()
		if slug.is_empty():
			continue
		var qty := maxi(1, int(row.get("quantity", 1)))
		var quality := str(row.get("quality", "") if row.get("quality", null) != null else "")
		var item_name := str(name_of.call(slug)) if name_of.is_valid() else ""
		if item_name.is_empty() or item_name == "名称缺失":
			item_name = slug
		var text := item_name if qty <= 1 else "%s ×%d" % [item_name, qty]
		out.append({
			"slug": slug,
			"itemSlug": slug,
			"quantity": qty,
			"quality": quality,
			"name": item_name,
			"text": text,
			"idle": bool(row.get("idle", false)),
			"seed": bool(row.get("seed", false)),
		})
	return out
