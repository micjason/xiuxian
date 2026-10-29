class_name SkillFxCast
extends RefCounted
## 把技能配置 / 战斗事件收成一次施法表现。不改伤害，只决定播哪套、挂在哪。
## 挂点：斩 / 火 / 风 / 毒 / 金光 → 目标身中偏前；雷 / 冰 → 目标脚底；治疗 / 盾 → 己方脚底。

const SkillFxRoot := preload("res://anim_q/skill_fx/skill_fx_root.gd")

const ANCHOR_TARGET_BODY := "target_body"
const ANCHOR_TARGET_FEET := "target_feet"
const ANCHOR_SELF_FEET := "self_feet"


static func anchor_for(stored: String) -> String:
	match stored:
		"thunder", "ice":
			return ANCHOR_TARGET_FEET
		"heal_circle", "shield":
			return ANCHOR_SELF_FEET
		_:
			return ANCHOR_TARGET_BODY


## 首领战事件。普攻默认斩；大招用运转中的攻击技能（没有则斩）；治疗 / 丹药走治疗圈。
## 事件上的 fx / fxType / skillSlug 优先于默认。
static func resolve(event: Dictionary, skills: Array = [], running: Array = []) -> Dictionary:
	var explicit := _explicit(event, skills)
	if not explicit.is_empty():
		return _pack(explicit, str(event.get("fxType", event.get("kind", ""))))
	var kind := str(event.get("kind", ""))
	if kind in ["heal", "pill", "item"]:
		return _pack({"fxType": "heal_circle"}, kind)
	if kind == "ult":
		var ult_skill := pick_combat_skill(skills, running, true)
		if not ult_skill.is_empty():
			return _pack(ult_skill, kind)
		return _pack({"fxType": "slash"}, kind)
	return _pack({"fxType": "slash"}, kind)


## 历练自动出手：有运转中的攻击技能就播它的特效，否则普攻斩。
static func resolve_auto(skills: Array = [], running: Array = []) -> Dictionary:
	var skill := pick_combat_skill(skills, running, false)
	if skill.is_empty():
		return _pack({"fxType": "slash"}, "hit")
	return _pack(skill, "hit")


## for_ult 时，没有攻击技能就退回任意一门正在运转的技能。普攻挑选只认 role=attack。
static func pick_combat_skill(skills: Array, running: Array, for_ult: bool) -> Dictionary:
	var by_slug := {}
	for row in skills:
		if typeof(row) == TYPE_DICTIONARY:
			var def: Dictionary = row
			by_slug[str(def.get("slug", ""))] = def
	var fallback: Dictionary = {}
	for row in running:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var mine: Dictionary = row
		var slot := str(mine.get("runningSlot", ""))
		if slot.is_empty() or slot == "<null>":
			continue
		var def: Dictionary = by_slug.get(str(mine.get("skillSlug", "")), {})
		if def.is_empty() or not bool(def.get("enabled", true)):
			continue
		if str(def.get("role", "")) == "attack":
			return def
		if for_ult and fallback.is_empty():
			fallback = def
	return fallback if for_ult else {}


static func _explicit(event: Dictionary, skills: Array) -> Dictionary:
	if typeof(event.get("fx", null)) == TYPE_DICTIONARY:
		var fx: Dictionary = event.get("fx")
		return {"fxType": str(fx.get("type", event.get("fxType", ""))), "fx": fx, "_raw": str(fx.get("type", event.get("fxType", "")))}
	var named := str(event.get("fxType", ""))
	if not named.is_empty():
		return {"fxType": named, "_raw": named}
	var slug := str(event.get("skillSlug", ""))
	if slug.is_empty():
		return {}
	for row in skills:
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			var found: Dictionary = (row as Dictionary).duplicate(true)
			found["_raw"] = str(found.get("fxType", found.get("fx_type", "")))
			return found
	return {"fxType": "slash", "_raw": slug}


static func _pack(source: Dictionary, raw_hint: String) -> Dictionary:
	var fx: Dictionary = source.get("fx", {}) if typeof(source.get("fx", null)) == TYPE_DICTIONARY else {}
	var raw := str(source.get("_raw", ""))
	if raw.is_empty():
		raw = str(fx.get("type", ""))
	if raw.is_empty():
		raw = str(source.get("fxType", source.get("fx_type", "")))
	if raw.is_empty():
		raw = raw_hint
	var stored := SkillFxRoot.normalize_kind(raw)
	var playable := SkillFxRoot.resolve_kind(raw)
	var token := raw.strip_edges().to_lower()
	var colors: Array = SkillFxRoot.colors_for(raw if token in ["攻击法阵", "attack_circle"] else stored)
	var primary: Color = colors[0]
	var secondary: Color = colors[1]
	if fx.has("primary"):
		primary = SkillFxRoot.color_from(fx.get("primary"), primary)
	if fx.has("secondary"):
		secondary = SkillFxRoot.color_from(fx.get("secondary"), secondary)
	var scale := float(fx.get("scale", 1.0))
	if scale <= 0.0:
		scale = 1.0
	return {
		"stored": stored,
		"playable": playable,
		"alias": raw if token in ["攻击法阵", "attack_circle"] else stored,
		"anchor": anchor_for(stored),
		"primary": primary,
		"secondary": secondary,
		"scale": scale,
		"show_pillar": token in ["攻击法阵", "attack_circle"],
	}
