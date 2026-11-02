class_name CultivationFormat
extends RefCounted


static func amount(value: float) -> String:
	var absolute := absf(value)
	if absolute >= 100_000_000.0:
		return "%.2f 亿" % (value / 100_000_000.0)
	if absolute >= 10_000.0:
		return "%.2f 万" % (value / 10_000.0)
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value


static func rate(value: float) -> String:
	if value >= 10_000.0:
		return "%s/秒" % amount(value)
	if is_equal_approx(value, roundf(value)):
		return "%d/秒" % int(roundf(value))
	return "%.2f/秒" % value


static func duration_hours(seconds: int) -> String:
	var hours := float(seconds) / 3600.0
	if hours >= 1.0 and is_equal_approx(hours, roundf(hours)):
		return "%d 小时" % int(roundf(hours))
	if hours >= 1.0:
		return "%.1f 小时" % hours
	var minutes := float(seconds) / 60.0
	if minutes >= 1.0:
		return "%d 分钟" % int(roundf(minutes))
	return "%d 秒" % seconds


## 修为条 / 突破条件共用：分子不直接甩溢出大数，分母永远是本层 cost。
## 未满：current / cost；已满：已满(+溢出) / cost；无下一境界：只显示 current。
static func progress_pair(cultivation: float, cost: float, has_next: bool) -> Dictionary:
	## 用 OfflineView.grouped：和顶栏、突破页现有千分位一致；溢出改写「已满(+N)」避免分子炸条。
	if not has_next:
		return {"text": OfflineView.grouped(cultivation), "ratio": 1.0, "full": true, "overflow": 0.0}
	var need := maxf(cost, 1.0)
	var full := cultivation + 0.0001 >= cost
	var overflow := maxf(cultivation - cost, 0.0) if full else 0.0
	var shown := ""
	if full and overflow >= 0.5:
		shown = "已满(+%s) / %s" % [OfflineView.grouped(overflow), OfflineView.grouped(cost)]
	elif full:
		shown = "%s / %s" % [OfflineView.grouped(cost), OfflineView.grouped(cost)]
	else:
		shown = "%s / %s" % [OfflineView.grouped(cultivation), OfflineView.grouped(cost)]
	return {
		"text": shown,
		"ratio": clampf(cultivation / need, 0.0, 1.0),
		"full": full,
		"overflow": overflow,
	}
