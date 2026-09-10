class_name EquipSlot
extends RefCounted

const WEAPON := "weapon"
const HELMET := "helmet"
const CLOTHES := "clothes"
const SHOES := "shoes"
const ACCESSORY := "accessory"

const ORDER := [WEAPON, HELMET, CLOTHES, SHOES, ACCESSORY]
const DISPLAY := {
	WEAPON: "武器",
	HELMET: "头盔",
	CLOTHES: "衣服",
	SHOES: "鞋子",
	ACCESSORY: "玉佩",
}


static func is_valid(id: String) -> bool:
	return ORDER.has(id)


static func display_name(id: String) -> String:
	return str(DISPLAY.get(id, id))
