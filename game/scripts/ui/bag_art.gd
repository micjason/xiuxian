class_name BagArt
extends RefCounted

const BACKGROUND := preload("res://assets/images/bag_bg_night_mountain.png")
const CULTIVATOR := preload("res://assets/images/cultivator_back.png")
const SLOT_HELMET := preload("res://assets/images/slot_icon_helmet.png")
const SLOT_WEAPON := preload("res://assets/images/slot_icon_weapon.png")
const SLOT_CLOTHES := preload("res://assets/images/slot_icon_clothes.png")
const SLOT_SHOES := preload("res://assets/images/slot_icon_shoes.png")
const SLOT_JADE := preload("res://assets/images/slot_icon_jade.png")
const TAB_CULTIVATE := preload("res://assets/images/tab_cultivate.png")
const TAB_ADVENTURE := preload("res://assets/images/tab_adventure.png")
const TAB_CAVE := preload("res://assets/images/tab_cave.png")
const TAB_BAG := preload("res://assets/images/tab_bag.png")
const TAB_SKILL := preload("res://assets/images/tab_skill.png")
const ICON_SETTINGS := preload("res://assets/images/icon_settings.png")


static func slot_icon(slot: String) -> Texture2D:
	match slot:
		EquipSlot.HELMET:
			return SLOT_HELMET
		EquipSlot.WEAPON:
			return SLOT_WEAPON
		EquipSlot.CLOTHES:
			return SLOT_CLOTHES
		EquipSlot.SHOES:
			return SLOT_SHOES
		EquipSlot.ACCESSORY:
			return SLOT_JADE
		_:
			return SLOT_JADE
