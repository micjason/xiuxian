class_name SkillFxFallback
extends RefCounted
## 技能表现：库存写资源真名。只有客户端缺这套资源时才降级。
## gold 是 gold_light 的旧别名。不提供手动释放。

const TYPES: Array[String] = ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]
const ALIAS := {"gold": "gold_light", "holy": "gold_light"}
const FALLBACK := {
	"ice": "thunder",
	"wind": "slash",
	"poison": "fire",
	"gold_light": "slash",
	"shield": "heal_circle",
}
const ICONS := {
	"slash": "slash",
	"thunder": "thunder",
	"fire": "fire",
	"heal_circle": "heal_circle",
	"ice": "ice",
	"wind": "wind",
	"poison": "poison",
	"gold_light": "gold_light",
	"gold": "gold_light",
	"shield": "shield",
	"skill_slash": "slash",
	"skill_thunder": "thunder",
	"skill_fire": "fire",
	"skill_heal": "heal_circle",
	"skill_ice": "ice",
	"skill_wind": "wind",
	"skill_poison": "poison",
	"skill_gold": "gold_light",
	"skill_shield": "shield",
}


static func canonical(raw: String) -> String:
	var text := raw.strip_edges()
	if ALIAS.has(text):
		return str(ALIAS[text])
	if text in TYPES:
		return text
	return "slash"


static func resolve_type(raw: String, available: Array) -> String:
	var type := canonical(raw)
	if available.has(type):
		return type
	var mapped := str(FALLBACK.get(type, "slash"))
	if available.has(mapped):
		return mapped
	return "slash"


static func icon_key(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	if ICONS.has(text):
		return str(ICONS[text])
	return ""
