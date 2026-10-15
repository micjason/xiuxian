class_name BagModel
extends RefCounted
## 行囊数据模型：把服务器的物品行（id/itemSlug/equippedSlot/quantity）和内容定义
## （名称/类别/部位/品质/属性）合并成界面用的展示数据，并负责分类、排序、容量、对比、批量选择规则。
## 纯数据，不依赖节点，便于单元测试。
##
## 强化：每件装备的强化等级来自服务器（enhanceLevel），属性按强化规则（EnhanceModel）放大。
## 没有"出售"：分解装备得到强化经验（进强化经验池，用来强化其他装备）。

const CATEGORIES: Array[Dictionary] = [
	{"id": "equip", "name": "装备"},
	{"id": "material", "name": "材料"},
	{"id": "pill", "name": "丹药"},
	{"id": "other", "name": "其他"},
]
const SORTS: Array[Dictionary] = [
	{"id": "default", "name": "默认"},
	{"id": "rarity", "name": "品质"},
	{"id": "power", "name": "战力"},
	{"id": "name", "name": "名称"},
]
const QUALITY_INDEX := {"white": 0, "green": 1, "blue": 2, "purple": 3, "orange": 4, "red": 5}
const STAT_KEYS: Array[String] = ["attack", "defense", "hp", "speed"]
const STAT_NAMES := {"attack": "攻击", "defense": "防御", "hp": "气血", "speed": "速度"}
## 行囊初始容量（设计定为 20）。正常情况下服务器 state.bagCapacity 一定会给；
## 只有离线预览和单元测试没有这个字段时才用它。
const DEFAULT_CAPACITY := 20
## 没有下发战力权重时使用的数值方案默认值（与后台「战斗公式与参数」默认值一致）。
const DEFAULT_WEIGHTS := {"attack": 4.7, "defense": 1.6, "hp": 0.95, "speed": 2.6}

var capacity := DEFAULT_CAPACITY
var weights: Dictionary = DEFAULT_WEIGHTS.duplicate()
var items: Array[Dictionary] = []
var enhance: EnhanceModel = EnhanceModel.new()
## 强化经验池（分解装备得到，用来强化装备）。
var enhance_exp := 0
## 物品定义（slug → 定义），用来显示突破材料的名字。
var defs: Dictionary = {}


static func from_state(state: Dictionary, content: Dictionary, seen: Dictionary = {}) -> BagModel:
	var model := BagModel.new()
	var globals: Dictionary = content.get("globals", {}) if typeof(content.get("globals", {})) == TYPE_DICTIONARY else {}
	var cap := int(state.get("bagCapacity", 0))
	if cap <= 0:
		cap = int(globals.get("bagCapacity", 0))
	model.capacity = cap if cap > 0 else DEFAULT_CAPACITY
	model.enhance = EnhanceModel.from_content(content)
	model.enhance_exp = int(state.get("enhanceExp", 0))
	var raw_weights: Variant = globals.get("powerWeights", null)
	if typeof(raw_weights) == TYPE_DICTIONARY:
		for key in STAT_KEYS:
			if (raw_weights as Dictionary).has(key):
				model.weights[key] = float((raw_weights as Dictionary)[key])
	var defs := {}
	for def in content.get("items", []):
		if typeof(def) == TYPE_DICTIONARY:
			defs[str((def as Dictionary).get("slug", ""))] = def
	model.defs = defs
	for row in state.get("items", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		model.items.append(normalize(row as Dictionary, defs.get(str((row as Dictionary).get("itemSlug", "")), {}), model.weights, model.enhance, seen))
	for item in model.items:
		item["break_view"] = model.break_view_of(item)
	return model


## 行囊里某种材料的总数量（只数堆叠物品）。
func material_count(slug: String) -> int:
	var total := 0
	for item in items:
		if str(item.get("slug", "")) == slug and bool(item.get("stackable", false)):
			total += int(item.get("qty", 1))
	return total


func item_name(slug: String) -> String:
	return str((defs.get(slug, {}) as Dictionary).get("displayName", slug))


## 突破节点的界面数据：{level, ready, materials:[{slug, name, need, have}]}；没有节点返回空字典。
## which = "pending" 取正卡着的节点，"next" 取下一个节点。
func node_view(node: Dictionary) -> Dictionary:
	if node.is_empty():
		return {}
	var materials: Array[Dictionary] = []
	var ready := true
	for material in node.get("materials", []):
		var slug := str(material.get("itemSlug", ""))
		var need := int(material.get("count", 0))
		var have := material_count(slug)
		if have < need:
			ready = false
		materials.append({"slug": slug, "name": item_name(slug), "need": need, "have": have})
	return {"level": int(node.get("level", 0)), "ready": ready, "materials": materials}


func break_view_of(item: Dictionary) -> Dictionary:
	return {"pending": node_view(item.get("break_pending", {})), "next": node_view(item.get("break_next", {}))}


static func plain(value: Variant) -> String:
	if value == null:
		return ""
	var text := str(value).strip_edges()
	return "" if text == "<null>" else text


static func category_of(def: Dictionary) -> String:
	match str(def.get("kind", "")):
		"equipment":
			return "equip"
		"material":
			return "material"
		"consumable", "pill", "elixir":
			return "pill"
		_:
			return "other"


static func rarity_of(def: Dictionary) -> int:
	return int(QUALITY_INDEX.get(str(def.get("quality", "white")), 0))


## 界面显示用：属性是小数，只在显示时四舍五入成整数（服务端给什么小数就用什么小数算）。
static func shown(value: float) -> int:
	return int(round(value))


static func power_of(stats: Dictionary, weights: Dictionary) -> int:
	var total := 0.0
	for key in STAT_KEYS:
		total += float(stats.get(key, 0)) * float(weights.get(key, 0))
	return int(round(total))


static func normalize(row: Dictionary, def: Dictionary, weights: Dictionary, enhance_model: EnhanceModel = null, seen: Dictionary = {}) -> Dictionary:
	var id := str(row.get("id", ""))
	var level := maxi(0, int(row.get("enhanceLevel", 0)))
	var rarity := rarity_of(def)
	var category := category_of(def)
	var is_gear := category == "equip"
	var stats := {}
	var base_stats := {}
	for key in STAT_KEYS:
		var base := float(def.get(key, 0))
		base_stats[key] = base
		stats[key] = enhance_model.stat(base, level, rarity) if (enhance_model != null and is_gear) else base
	var server_slot := str(def.get("slot", "")) if def.get("slot", null) != null else ""
	var equipped_server := plain(row.get("equippedSlot", null))
	var cap := 0
	var next_cost := 0
	var break_level := maxi(0, int(row.get("breakLevel", 0)))
	var pending := {}
	var upcoming := {}
	if is_gear and enhance_model != null and enhance_model.supports(rarity):
		cap = enhance_model.cap(rarity)
		next_cost = enhance_model.cost(rarity, level) if level < cap else 0
		pending = enhance_model.pending_node(rarity, level, break_level)
		upcoming = enhance_model.next_node(rarity, level, break_level)
	return {
		"id": id,
		"slug": str(row.get("itemSlug", "")),
		"name": str(def.get("displayName", row.get("itemSlug", ""))),
		"desc": str(def.get("description", "")),
		"kind": str(def.get("kind", "")),
		"category": category,
		"server_slot": server_slot,
		"slot_id": SlotConfig.id_from_server(server_slot),
		"rarity": rarity,
		"rarity_name": UiTokens.RARITY_NAMES[clampi(rarity, 0, UiTokens.RARITY_NAMES.size() - 1)],
		"qty": maxi(1, int(row.get("quantity", 1))),
		"stackable": bool(row.get("isStack", def.get("stackable", false))),
		"equipped": not equipped_server.is_empty(),
		"equipped_slot_id": SlotConfig.id_from_server(equipped_server),
		"enhance": level,
		"enhance_cap": cap,
		"enhance_cost": next_cost,
		"break_level": break_level,
		## 正卡着的突破节点（没有就是空字典）和下一个还没突破的节点；材料够不够由 BagModel 实例补上 break_view。
		"break_pending": pending,
		"break_next": upcoming,
		"decompose_exp": enhance_model.decompose_exp(rarity, level) if (is_gear and enhance_model != null) else 0,
		"is_new": not seen.is_empty() and not seen.has(id),
		"stats": stats,
		"base_stats": base_stats,
		"power": power_of(stats, weights) if is_gear else 0,
		"required_realm_order": int(def.get("requiredRealmOrder", 0)),
	}


func find(item_id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == item_id:
			return item
	return {}


## 行囊占用格数：已穿戴的不占格，堆叠物品算一格。
func used_slots() -> int:
	var count := 0
	for item in items:
		if not bool(item.get("equipped", false)):
			count += 1
	return count


func is_full() -> bool:
	return used_slots() >= capacity


## 自动分解能腾出格子的装备：没穿、白/绿、没强化过（与服务器 pickAutoDecomposeCandidate 一致）。
func auto_decomposable_count() -> int:
	var count := 0
	for item in items:
		if str(item.get("category", "")) == "equip" and not bool(item.get("equipped", false)) and int(item.get("rarity", 0)) <= 1 and int(item.get("enhance", 0)) == 0:
			count += 1
	return count


## 挑战前的行囊检查：服务器在满格时，开关开且能找到可分解的白/绿装备就腾一格，否则拒绝（BAG_FULL）。
## 返回 {full, blocked, used, capacity, will_free}。
func challenge_gate(auto_decompose: bool) -> Dictionary:
	var used := used_slots()
	var full := used >= capacity
	var will_free := full and auto_decompose and auto_decomposable_count() > 0
	return {"full": full, "blocked": full and not will_free, "used": used, "capacity": capacity, "will_free": will_free}


func category_count(category: String) -> int:
	var count := 0
	for item in items:
		if not bool(item.get("equipped", false)) and str(item.get("category", "")) == category:
			count += 1
	return count


## 某分类下的展示列表（不含已穿戴）。
func visible_items(category: String, sort_id: String = "default") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items:
		if bool(item.get("equipped", false)):
			continue
		if category == "all" or str(item.get("category", "")) == category:
			out.append(item)
	sort_items(out, sort_id)
	return out


static func sort_items(list: Array[Dictionary], sort_id: String) -> void:
	match sort_id:
		"rarity":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if int(a.rarity) != int(b.rarity):
					return int(a.rarity) > int(b.rarity)
				return int(a.power) > int(b.power))
		"power":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if int(a.power) != int(b.power):
					return int(a.power) > int(b.power)
				return int(a.rarity) > int(b.rarity))
		"name":
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.name) < str(b.name))
		_:
			# 默认：新获得的在前，其次品质高的在前，保持稳定。
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if bool(a.is_new) != bool(b.is_new):
					return bool(a.is_new)
				return int(a.rarity) > int(b.rarity))


## 与已穿戴装备对比。返回每项属性的 {key, label, value, other, delta}，delta>0 表示比身上的强。
static func compare(item: Dictionary, worn: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stats: Dictionary = item.get("stats", {})
	var other: Dictionary = worn.get("stats", {}) if not worn.is_empty() else {}
	for key in STAT_KEYS:
		var value := float(stats.get(key, 0))
		var base := float(other.get(key, 0))
		if is_zero_approx(value) and is_zero_approx(base):
			continue
		out.append({"key": key, "label": str(STAT_NAMES[key]), "value": value, "other": base, "delta": value - base})
	return out


## 能否分解：只有没穿的装备（与服务器 decompose 接口一致，它只处理装备）。
static func can_decompose(item: Dictionary) -> bool:
	return decompose_block_reason(item).is_empty()


## 不能分解的原因（给界面显示）；能分解返回空字符串。已穿戴的装备不能分解，要先脱下。
static func decompose_block_reason(item: Dictionary) -> String:
	if str(item.get("category", "")) != "equip":
		return "只有装备可以分解"
	if bool(item.get("equipped", false)):
		return "已穿戴，无法分解"
	return ""


## 能否强化：装备有强化规则、没到上限、也没有卡在没突破的节点上。强化经验够不够由界面另外判断。
static func can_enhance(item: Dictionary) -> bool:
	return str(item.get("category", "")) == "equip" and int(item.get("enhance_cap", 0)) > int(item.get("enhance", 0)) and not is_blocked_by_node(item)


## 卡在没突破的节点上：必须先突破才能继续强化。
static func is_blocked_by_node(item: Dictionary) -> bool:
	return not (item.get("break_pending", {}) as Dictionary).is_empty()


## 能否突破：装备卡在节点上（材料够不够由界面另外判断）。
static func can_break(item: Dictionary) -> bool:
	return str(item.get("category", "")) == "equip" and is_blocked_by_node(item)


## 批量选择里允许被选中的物品。
static func selectable_for_batch(item: Dictionary) -> bool:
	return can_decompose(item)


## 过滤出批量可分解的 id；已穿戴、非装备的会被跳过。
func batch_ids(selected: Array) -> Array[String]:
	var out: Array[String] = []
	for id in selected:
		var item := find(str(id))
		if not item.is_empty() and can_decompose(item):
			out.append(str(id))
	return out
