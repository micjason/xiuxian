class_name QualityId
extends RefCounted

const WHITE := "white"
const BLUE := "blue"
const PURPLE := "purple"
const GOLD := "gold"
const RED := "red"
const NONE := ""

const ORDER := [WHITE, BLUE, PURPLE, GOLD, RED]
const DISPLAY := {
	WHITE: "白色",
	BLUE: "蓝色",
	PURPLE: "紫色",
	GOLD: "金色",
	RED: "红色",
}
const COLORS := {
	WHITE: Color(0.86, 0.86, 0.84, 1),
	BLUE: Color(0.42, 0.62, 0.92, 1),
	PURPLE: Color(0.72, 0.48, 0.92, 1),
	GOLD: Color(0.92, 0.78, 0.34, 1),
	RED: Color(0.9, 0.32, 0.28, 1),
}


static func is_valid(id: String) -> bool:
	return ORDER.has(id)


static func rank(id: String) -> int:
	return ORDER.find(id)


static func display_name(id: String) -> String:
	return str(DISPLAY.get(id, "无"))


static func color(id: String) -> Color:
	return COLORS.get(id, Color(0.7, 0.7, 0.7, 1))
