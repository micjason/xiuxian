class_name EquipmentLoadout
extends RefCounted

var weapon: int = 0
var helmet: int = 0
var clothes: int = 0
var shoes: int = 0
var accessory: int = 0


func uid_for(slot: String) -> int:
	match slot:
		EquipSlot.WEAPON:
			return weapon
		EquipSlot.HELMET:
			return helmet
		EquipSlot.CLOTHES:
			return clothes
		EquipSlot.SHOES:
			return shoes
		EquipSlot.ACCESSORY:
			return accessory
	return 0


func set_uid(slot: String, uid: int) -> bool:
	if not EquipSlot.is_valid(slot):
		return false
	match slot:
		EquipSlot.WEAPON:
			weapon = uid
		EquipSlot.HELMET:
			helmet = uid
		EquipSlot.CLOTHES:
			clothes = uid
		EquipSlot.SHOES:
			shoes = uid
		EquipSlot.ACCESSORY:
			accessory = uid
	return true


func contains_uid(uid: int) -> bool:
	if uid <= 0:
		return false
	return weapon == uid or helmet == uid or clothes == uid or shoes == uid or accessory == uid


func clear_uid(uid: int) -> void:
	if weapon == uid:
		weapon = 0
	if helmet == uid:
		helmet = 0
	if clothes == uid:
		clothes = 0
	if shoes == uid:
		shoes = 0
	if accessory == uid:
		accessory = 0


func to_dictionary() -> Dictionary:
	return {
		"weapon": weapon,
		"helmet": helmet,
		"clothes": clothes,
		"shoes": shoes,
		"accessory": accessory,
	}


static func from_dictionary(data: Dictionary) -> EquipmentLoadout:
	var loadout := EquipmentLoadout.new()
	loadout.weapon = maxi(int(data.get("weapon", 0)), 0)
	loadout.helmet = maxi(int(data.get("helmet", 0)), 0)
	loadout.clothes = maxi(int(data.get("clothes", 0)), 0)
	loadout.shoes = maxi(int(data.get("shoes", 0)), 0)
	loadout.accessory = maxi(int(data.get("accessory", 0)), 0)
	return loadout
