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
