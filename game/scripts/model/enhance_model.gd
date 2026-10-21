class_name EnhanceModel
extends RefCounted
## 装备强化规则的客户端镜像（数字全部来自 /content/current 的 globals.enhance，后台「装备强化」页可改）。
## 公式与服务器 backend/src/modules/content/enhance.ts 一致：
##   升一级的经验 = round(expBase × 经验增长倍数^当前等级 × 品质经验倍数)   （品质可单独覆盖经验增长倍数）
##   强化后属性 = 基础值 × (1 + 等级 × 每级属性加成 / 10000)               （品质可单独覆盖每级属性加成）
##   分解得到 = 品质基础经验 + 已投入经验 × refundBp / 10000
##   突破节点：装备强化到节点等级后，要交齐材料「突破」才能继续升级（不会失败）。
## 强化经验池没有上限。已穿戴的装备不能分解（见 BagModel.can_decompose）。
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


## 从 level 级升到 level+1 级要多少强化经验。
func cost(rarity: int, level: int) -> int:
	var row := _quality(rarity)
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


func decompose_exp(rarity: int, level: int) -> int:
	if not supports(rarity):
		return 0
	return int(_quality(rarity).get("decomposeExp", 0)) + int(floor(float(invested(rarity, level)) * float(rules.get("refundBp", 0)) / 10000.0))


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
