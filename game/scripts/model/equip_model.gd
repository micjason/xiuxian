class_name EquipModel
extends RefCounted
## 装备栏数据模型：按 SlotConfig 把已穿戴物品摆进各个部位，汇总战力与属性，并给出某部位可替换的候选。

## 返回 {部位 id: 物品展示数据 或 {}}，包含配置里的所有部位（含未开放、锁定的）。
static func slots_of(bag: BagModel) -> Dictionary:
	var out := {}
	for slot in SlotConfig.all():
		out[str(slot.id)] = {}
	for item in bag.items:
		if bool(item.get("equipped", false)):
			var slot_id := str(item.get("equipped_slot_id", ""))
			if out.has(slot_id):
				out[slot_id] = item
	return out


static func worn_in(bag: BagModel, slot_id: String) -> Dictionary:
	var slots := slots_of(bag)
	return slots.get(slot_id, {})


## 已穿戴装备提供的属性合计。
static func stat_totals(slots: Dictionary) -> Dictionary:
	var totals := {"attack": 0.0, "defense": 0.0, "hp": 0.0, "speed": 0.0}
	for slot_id in slots:
		var item: Dictionary = slots[slot_id]
		if item.is_empty():
			continue
		for key in BagModel.STAT_KEYS:
			totals[key] = float(totals[key]) + float((item.stats as Dictionary).get(key, 0))
	return totals


## 已穿戴装备贡献的战力（按权重折算，仅装备部分）。
static func gear_power(slots: Dictionary) -> int:
	var total := 0
	for slot_id in slots:
		var item: Dictionary = slots[slot_id]
		if not item.is_empty():
			total += int(item.get("power", 0))
	return total


static func worn_count(slots: Dictionary) -> int:
	var count := 0
	for slot_id in slots:
		if not (slots[slot_id] as Dictionary).is_empty():
			count += 1
	return count


## 某部位在行囊里的可替换装备，战力高的在前。
static func candidates_for(bag: BagModel, slot_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in bag.items:
		if bool(item.get("equipped", false)):
			continue
		if str(item.get("category", "")) == "equip" and str(item.get("slot_id", "")) == slot_id:
			out.append(item)
	BagModel.sort_items(out, "power")
	return out


## 洞府强化入口预选：已穿戴、还能强化的装备。按核心部位顺序取第一件（武器优先）。
## 到上限、卡在突破节点、没穿上的都不预选。没有则返回空字符串。
static func worn_enhance_target(bag: BagModel) -> String:
	if bag == null:
		return ""
	var slots := slots_of(bag)
	for slot in SlotConfig.core():
		var item: Dictionary = slots.get(str(slot.get("id", "")), {})
		if item.is_empty() or not BagModel.can_enhance(item):
			continue
		return str(item.get("id", ""))
	return ""


## 「一键穿戴」：每个核心部位里战力比身上更高的最强候选，返回物品 id 列表（没有更强的部位不动）。
static func best_upgrades(bag: BagModel) -> Array[String]:
	var out: Array[String] = []
	var slots := slots_of(bag)
	for slot in SlotConfig.core():
		if not bool(slot.get("supported", false)):
			continue
		var worn: Dictionary = slots.get(str(slot.id), {})
		var candidates := candidates_for(bag, str(slot.id))
		if candidates.is_empty():
			continue
		var best: Dictionary = candidates[0]
		if int(best.get("power", 0)) > int(worn.get("power", 0)):
			out.append(str(best.get("id", "")))
	return out
