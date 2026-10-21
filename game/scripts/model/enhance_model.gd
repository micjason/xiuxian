class_name EnhanceModel
extends RefCounted
## 装备强化规则的客户端镜像（数字全部来自 /content/current 的 globals.enhance，后台「装备强化」页可改）。
## 公式与服务器 backend/src/modules/content/enhance.ts 一致：
##   升一级的经验 = round(expBase × 经验增长倍数^当前等级 × 品质经验倍数)   （品质可单独覆盖经验增长倍数）
##   强化后属性 = 基础值 × (1 + 等级 × 每级属性加成 / 10000)               （品质可单独覆盖每级属性加成）
##   分解得到 = 品质基础经验 + 已投入经验 × refundBp / 10000
##   突破节点：装备强化到节点等级后，要交齐材料「突破」才能继续升级（不会失败）。
## 强化经验池没有上限。已穿戴的装备不能分解（见 BagModel.can_decompose）。
## 第五批（SPEC_Q §17.2 / 17.3）：规则里有 essence 时，分解得「炼器精粹」、强化消耗精粹（uses_essence() 为真）：
##   分解得到 = 品质产出（× 部位倍数，或单独指定）+ 强化等级 × 每级返还
##   升一级的精粹 = 单独指定的每级消耗表，没有就 round(基础消耗 × 增长倍数^等级 × 品质倍数)
## 和服务器 enhance.ts 的 essenceYield / essenceCost 一致；cost() / decompose_exp() 在有精粹规则时返回精粹数。
## 规则缺失时 rules 为空，所有查询都会报错而不是用默认数字（和服务器同样的要求）。
## 这个文件里没有任何玩法数字；突破节点也只读配置。品质 5 档白→橙（红已去掉）。

const QUALITY_KEYS: Array[String] = Catalog.QUALITY_KEYS

var rules: Dictionary = {}


static func from_content(content: Dictionary) -> EnhanceModel:
	var model := EnhanceModel.new()
	var globals: Variant = content.get("globals", {})
	if typeof(globals) == TYPE_DICTIONARY and typeof((globals as Dictionary).get("enhance", null)) == TYPE_DICTIONARY:
		model.rules = (globals as Dictionary)["enhance"]
	return model


func is_ready() -> bool:
	return not rules.is_empty()


func _quality(rarity: int) -> Dictionary:
	var qualities: Dictionary = rules.get("qualities", {})
	var key := QUALITY_KEYS[clampi(rarity, 0, QUALITY_KEYS.size() - 1)]
	return qualities.get(key, {})


## 这个品质的装备能强化吗（没配规则的品质不能；服务器也是同样处理）。
func supports(rarity: int) -> bool:
	return is_ready() and not _quality(rarity).is_empty()


func cap(rarity: int) -> int:
	return int(_quality(rarity).get("cap", 0))


## 这个品质实际使用的每级经验增长倍数（品质自己的覆盖通用的）。
func exp_growth(rarity: int) -> float:
	var row := _quality(rarity)
	return float(row.get("expGrowth", rules.get("expGrowth", 1)))


## 这个品质实际使用的每级属性加成（万分比）。
func stat_growth_bp(rarity: int) -> float:
	var row := _quality(rarity)
	return float(row.get("statGrowthBp", rules.get("statGrowthBp", 0)))


## 有没有炼器精粹规则（第五批服务器都有；老服务器没有就按旧的强化经验算）。
func uses_essence() -> bool:
	return typeof(rules.get("essence", null)) == TYPE_DICTIONARY


func _essence() -> Dictionary:
	return rules.get("essence", {}) if uses_essence() else {}


## 精粹对应的物品编号（默认 refine_essence）；没有精粹规则返回空串。
func essence_slug() -> String:
	return str(_essence().get("itemSlug", ""))


## 从 level 级升到 level+1 级要多少（有精粹规则 = 精粹，否则 = 旧的强化经验）。
func cost(rarity: int, level: int) -> int:
	var row := _quality(rarity)
	if uses_essence():
		var essence := _essence()
		var table: Variant = (essence.get("costTable", {}) as Dictionary).get(QUALITY_KEYS[clampi(rarity, 0, QUALITY_KEYS.size() - 1)], null) if typeof(essence.get("costTable", null)) == TYPE_DICTIONARY else null
		if typeof(table) == TYPE_ARRAY and level < (table as Array).size() and (table as Array)[level] != null and float((table as Array)[level]) > 0:
			return int((table as Array)[level])
		return maxi(1, int(round(float(essence.get("costBase", 0)) * pow(float(essence.get("costGrowth", 1)), level) * float(row.get("costMult", 1)))))
	return maxi(1, int(round(float(rules.get("expBase", 0)) * pow(exp_growth(rarity), level) * float(row.get("costMult", 1)))))


func invested(rarity: int, level: int) -> int:
	var total := 0
	for step in level:
		total += cost(rarity, step)
	return total


## 一件装备强化后的属性。rarity < 0 时使用通用的每级属性加成（只在不知道品质的场合）。
## 返回小数（和服务端 enhancedStat 一样保留 2 位），不在这里取整；界面只在显示时取整（BagModel.shown）。
func stat(base: float, level: int, rarity: int = -1) -> float:
	if not is_ready():
		return base
	var growth := float(rules.get("statGrowthBp", 0)) if rarity < 0 else stat_growth_bp(rarity)
	return round(base * (1.0 + float(level) * growth / 10000.0) * 100.0) / 100.0


## 分解一件得到多少（有精粹规则 = 精粹，按部位；否则 = 旧的强化经验）。slot_id 是客户端部位 id（weapon/helmet/…）。
func decompose_exp(rarity: int, level: int, slot_id: String = "") -> int:
	if not supports(rarity):
		return 0
	if uses_essence():
		return essence_yield(rarity, slot_id, level)
	return int(_quality(rarity).get("decomposeExp", 0)) + int(floor(float(invested(rarity, level)) * float(rules.get("refundBp", 0)) / 10000.0))


## 精粹产出的品质部分（不含强化返还）。
func essence_base(rarity: int, slot_id: String = "") -> int:
	var essence := _essence()
	var key := QUALITY_KEYS[clampi(rarity, 0, QUALITY_KEYS.size() - 1)]
	var server_slot := str(SlotConfig.find(slot_id).get("server", slot_id)) if not slot_id.is_empty() else ""
	var overrides: Variant = essence.get("slotOverrides", {})
	if typeof(overrides) == TYPE_DICTIONARY and typeof((overrides as Dictionary).get(key, null)) == TYPE_DICTIONARY:
		var fixed: Variant = ((overrides as Dictionary)[key] as Dictionary).get(server_slot, null)
		if fixed != null:
			return int(fixed)
	var mults: Variant = essence.get("slotMultBp", {})
	var mult := float((mults as Dictionary).get(server_slot, 10000)) if typeof(mults) == TYPE_DICTIONARY else 10000.0
	var yields: Variant = essence.get("yields", {})
	var base := float((yields as Dictionary).get(key, 0)) if typeof(yields) == TYPE_DICTIONARY else 0.0
	return int(round(base * mult / 10000.0))


## 强化返还：每级多少精粹。
func refund_per_level() -> int:
	return int(_essence().get("refundPerLevel", 0))


## 分解一件 +level 的装备得到的精粹 = 品质（部位）产出 + 等级 × 每级返还。
func essence_yield(rarity: int, slot_id: String, level: int) -> int:
	if not uses_essence():
		return 0
	return essence_base(rarity, slot_id) + maxi(0, level) * refund_per_level()


## 这个品质的全部突破节点（按等级从小到大）：[{level, materials:[{itemSlug, count}]}]。
func nodes(rarity: int) -> Array:
	var list: Array = (_quality(rarity).get("breakthroughs", []) as Array).duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 0)) < int(b.get("level", 0)))
	return list


## 装备现在卡在哪个节点：等级正好等于节点等级、节点没突破过、且节点低于上限。没卡住返回空字典。
func pending_node(rarity: int, level: int, broken_level: int) -> Dictionary:
	if not supports(rarity):
		return {}
	for node in nodes(rarity):
		var at := int(node.get("level", 0))
		if at == level and at > broken_level and at < cap(rarity):
			return node
	return {}


## 从当前等级往上看，下一个还没突破的节点（含正卡着的）；没有返回空字典。
func next_node(rarity: int, level: int, broken_level: int) -> Dictionary:
	if not supports(rarity):
		return {}
	for node in nodes(rarity):
		var at := int(node.get("level", 0))
		if at >= level and at > broken_level and at < cap(rarity):
			return node
	return {}


## 用 pool 点经验最多能把 level 升到几级（不超过上限，也不会越过没突破的节点）。
func levels_affordable(rarity: int, level: int, pool: int, broken_level: int = 0) -> int:
	var reached := level
	var left := pool
	while reached < cap(rarity):
		if not pending_node(rarity, reached, broken_level).is_empty():
			break
		var need := cost(rarity, reached)
		if left < need:
			break
		left -= need
		reached += 1
	return reached
