class_name SkillRole
extends RefCounted

const HEART := "heart"
const ATTACK := "attack"
const BODY := "body"
const STEP := "step"

const ORDER := [HEART, ATTACK, BODY, STEP]
const DISPLAY := {
	HEART: "心法",
	ATTACK: "攻法",
	BODY: "体法",
	STEP: "步法",
}


static func is_valid(id: String) -> bool:
	return ORDER.has(id)


static func is_heart(id: String) -> bool:
	return id == HEART


static func is_art(id: String) -> bool:
	return id == ATTACK or id == BODY or id == STEP


static func display_name(id: String) -> String:
	return str(DISPLAY.get(id, id))


static func art_slot_count(realm_order: int) -> int:
	return 2 if realm_order >= 4 else 1
