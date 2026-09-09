class_name BreakthroughCopy
extends RefCounted


static func banner(from_name: String, to_name: String, new_rate: float) -> String:
	return "突破成功  %s → %s\n修炼效率提升至 %s" % [
		from_name,
		to_name,
		CultivationFormat.rate(new_rate),
	]
