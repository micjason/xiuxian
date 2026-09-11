class_name ItemDef
extends RefCounted

const KIND_EQUIPMENT := "equipment"
const KIND_SKILL_BOOK := "skill_book"
const KIND_PILL := "pill"
const KIND_MATERIAL := "material"

const KIND_DISPLAY := {
	KIND_EQUIPMENT: "装备",
	KIND_SKILL_BOOK: "功法",
	KIND_PILL: "丹药",
	KIND_MATERIAL: "材料",
}

var id: String
var display_name: String
var kind: String
var quality: String
var slot: String
var skill_id: String
var attack: float
var defense: float
var hp: float
var speed: float
var min_realm_order: int
var stackable: bool
var description: String
var affixes: PackedStringArray = PackedStringArray()


func is_equipment() -> bool:
	return kind == KIND_EQUIPMENT


func is_skill_book() -> bool:
	return kind == KIND_SKILL_BOOK


func is_pill() -> bool:
	return kind == KIND_PILL


func is_material() -> bool:
	return kind == KIND_MATERIAL


func kind_display_name() -> String:
	return str(KIND_DISPLAY.get(kind, kind))


func set_id() -> String:
	return "tier_%d" % min_realm_order


func to_stats(stack: ItemStack = null) -> CombatStats:
	var scale := 1.0
	if stack != null:
		scale = 1.0 + 0.12 * float(clampi(stack.merge_level, 0, ItemStack.MAX_MERGE))
	var stats := CombatStats.new()
	stats.attack = attack * scale
	stats.defense = defense * scale
	stats.hp = hp * scale
	stats.speed = speed * scale
	if stack != null and stack.tempered:
		match slot:
			EquipSlot.SHOES:
				stats.speed += 0.4
			EquipSlot.HELMET, EquipSlot.CLOTHES:
				stats.defense += 1.2
			_:
				stats.attack += 0.8
	return stats


func gear_power(stack: ItemStack = null) -> float:
	var stats := to_stats(stack)
	return CombatStats.piece_power(stats.attack, stats.defense, stats.speed, stats.hp)


static func is_kind(id: String) -> bool:
	return KIND_DISPLAY.has(id)


static func default_speed(slot: String, realm_order: int) -> float:
	var tier := float(maxi(realm_order, 0))
	match slot:
		EquipSlot.WEAPON:
			return 0.4 + tier * 0.3
		EquipSlot.HELMET:
			return 0.1 + tier * 0.1
		EquipSlot.CLOTHES:
			return 0.2 + tier * 0.15
		EquipSlot.SHOES:
			return 1.6 + tier * 0.8
		EquipSlot.ACCESSORY:
			return 0.6 + tier * 0.35
	return 0.0


static func default_affixes(quality: String, slot: String) -> PackedStringArray:
	var lines := PackedStringArray()
	match quality:
		QualityId.WHITE:
			lines.append("凡铁")
		QualityId.BLUE:
			lines.append("灵纹")
		QualityId.PURPLE:
			lines.append("幽光")
		QualityId.GOLD:
			lines.append("金篆")
		QualityId.RED:
			lines.append("劫纹")
			lines.append("古意")
	match slot:
		EquipSlot.WEAPON:
			lines.append("破势")
		EquipSlot.HELMET:
			lines.append("镇神")
		EquipSlot.CLOTHES:
			lines.append("厚实")
		EquipSlot.SHOES:
			lines.append("轻灵")
		EquipSlot.ACCESSORY:
			lines.append("聚灵")
	return lines
