class_name SkillRank
extends RefCounted

const HUANG := "huang"
const XUAN := "xuan"
const DI := "di"
const TIAN := "tian"

const ORDER := [HUANG, XUAN, DI, TIAN]
const DISPLAY := {
	HUANG: "黄阶",
	XUAN: "玄阶",
	DI: "地阶",
	TIAN: "天阶",
}


static func is_valid(id: String) -> bool:
	return ORDER.has(id)


static func rank(id: String) -> int:
	return ORDER.find(id)


static func display_name(id: String) -> String:
	return str(DISPLAY.get(id, id))
