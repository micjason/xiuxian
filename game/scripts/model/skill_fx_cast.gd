class_name SkillFxCast
extends RefCounted
## 把技能配置 / 战斗事件收成一次施法表现。不改伤害，只决定播哪套、挂在哪。
## 挂点：斩/风在目标身前；火/冰/毒/金光在目标中心；雷在目标脚底；治疗在己方脚底；盾在己方身中。

const SkillFxRoot := preload("res://anim_q/skill_fx/skill_fx_root.gd")

const ANCHOR_TARGET_BODY := "target_body"
const ANCHOR_TARGET_CENTER := "target_center"
const ANCHOR_TARGET_FEET := "target_feet"
const ANCHOR_SELF_FEET := "self_feet"
const ANCHOR_SELF_BODY := "self_body"


static func anchor_for(stored: String) -> String:
	match stored:
		"thunder":
			return ANCHOR_TARGET_FEET
		"fire", "ice", "poison", "gold_light":
			return ANCHOR_TARGET_CENTER
		"heal_circle":
			return ANCHOR_SELF_FEET
		"shield":
			return ANCHOR_SELF_BODY
		_:
			return ANCHOR_TARGET_BODY


## 首领战事件。普攻默认斩；自动技能（协议字段 kind=ult，不是玩家按钮）用运转中的攻击技能，没有则斩；治疗 / 丹药走治疗圈。
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


## 玩家自动施法。协议里的 kind=ult 只是自动技能事件名。普攻和首领出手不播九套。
static func is_auto_cast(event: Dictionary) -> bool:
	if str(event.get("side", "")) == "boss":
		return false
	var kind := str(event.get("kind", ""))
	if kind in ["ult", "heal", "pill", "item"]:
		return true
	if typeof(event.get("fx", null)) == TYPE_DICTIONARY:
		return true
	if not str(event.get("fxType", event.get("fx_type", ""))).is_empty():
		return true
	if not str(event.get("skillSlug", event.get("skill_slug", ""))).is_empty():
		return true
	return false


static func anchor_position(cast: Dictionary, points: Dictionary) -> Vector2:
	var key := str(cast.get("anchor", ANCHOR_TARGET_BODY))
	if points.has(key):
		return points[key] as Vector2
	if points.has(ANCHOR_TARGET_CENTER):
		return points[ANCHOR_TARGET_CENTER] as Vector2
	return Vector2.ZERO


## 按 resolve / resolve_auto 的结果播一次。缺场景时静默返回 null，不写 slug。不移动 parent。
static func play(parent: Node, cast: Dictionary, points: Dictionary) -> Node2D:
	if parent == null or cast.is_empty():
		return null
	var kind := str(cast.get("playable", ""))
	if kind.is_empty():
		return null
	var scale := float(cast.get("scale", 1.0))
	var n := SkillFxRoot.spawn(kind, parent, anchor_position(cast, points), scale)
	if n == null:
		return null
	n.z_index = 8
	if "primary_color" in n and cast.get("primary") is Color:
		n.primary_color = cast.primary as Color
	if "secondary_color" in n and cast.get("secondary") is Color:
		n.secondary_color = cast.secondary as Color
	if bool(cast.get("show_pillar", false)) and "show_pillar" in n:
		n.show_pillar = true
	if n.has_signal("finished") and not n.finished.is_connected(n.queue_free):
		n.finished.connect(n.queue_free, CONNECT_ONE_SHOT)
	if n.has_method("play"):
		n.play()
	return n
