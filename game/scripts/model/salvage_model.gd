class_name SalvageModel
extends RefCounted
## 分解界面的选择逻辑（SPEC_Q §17.2 / 17.9，第五批）：只管数据，界面在 kit/salvage_dialog.gd。
## - 只列行囊里没穿的装备；按品质从低到高、同品质按强化等级从低到高排。
## - 打开时一件都不选（负责人已定）。
## - 品质胶囊：点一下 = 勾上该品质全部并点亮；再点 = 取消该品质全部。胶囊亮不亮只看「该品质是否全部勾上」，
##   所以手动取消一件会自动熄灭，手动勾满会自动点亮。
## - 预览精粹 = Σ(品质 × 部位产出) + Σ(强化等级 × 每级返还)，和服务器 essenceYield 用同一份后台配置。
## - 选中里有紫 / 橙时确认要二次确认（「再想想」保留勾选）。

const QUALITY_NAMES := ["白", "绿", "蓝", "紫", "橙"]
## 二次确认里的品质叫法（稿 17.9：「紫装 ×2」/「珍品 +3」）。
const RARE_WORDS := {3: "紫装", 4: "橙装"}
const RARE_TIER := {3: "珍品", 4: "绝品"}
const RARE_MIN := 3

var items: Array[Dictionary] = []
var bag: BagModel
var _selected: Dictionary = {}


static func from_bag(model: BagModel) -> SalvageModel:
	var out := SalvageModel.new()
	out.bag = model
	out.items = candidates(model)
	return out


## 能分解的装备（没穿），按品质↑、强化等级↑、名字排（稳定顺序，便于测试）。
static func candidates(model: BagModel) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if model == null:
		return out
	for item in model.items:
		if BagModel.can_decompose(item):
			out.append(item)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.rarity) != int(b.rarity):
			return int(a.rarity) < int(b.rarity)
		if int(a.get("enhance", 0)) != int(b.get("enhance", 0)):
			return int(a.get("enhance", 0)) < int(b.get("enhance", 0))
		return str(a.get("id", "")) < str(b.get("id", "")))
	return out


## 换了一份新的行囊（分解完 / 心跳）：保留还在的勾选，去掉已经没了的。
func refresh(model: BagModel) -> void:
	bag = model
	items = candidates(model)
	var keep := {}
	for item in items:
		var id := str(item.get("id", ""))
		if _selected.has(id):
			keep[id] = true
	_selected = keep


func is_selected(id: String) -> bool:
	return _selected.has(id)


func toggle(id: String) -> void:
	if _selected.has(id):
		_selected.erase(id)
	elif not _find(id).is_empty():
		_selected[id] = true


func clear() -> void:
	_selected.clear()


func total() -> int:
	return items.size()


func selected_count() -> int:
	return _selected.size()


func selected_ids() -> Array[String]:
	var out: Array[String] = []
	for item in items:
		if _selected.has(str(item.get("id", ""))):
			out.append(str(item.get("id", "")))
	return out


func selected_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items:
		if _selected.has(str(item.get("id", ""))):
			out.append(item)
	return out


## 这个品质有几件可分解 / 选了几件。
func count_of(rarity: int) -> int:
	return items.filter(func(i: Dictionary) -> bool: return int(i.rarity) == rarity).size()


func selected_of(rarity: int) -> int:
	return selected_items().filter(func(i: Dictionary) -> bool: return int(i.rarity) == rarity).size()


## 胶囊亮不亮：这个品质有装备，且全部勾上了。
func chip_on(rarity: int) -> bool:
	var count := count_of(rarity)
	return count > 0 and selected_of(rarity) == count


## 点品质胶囊：没全选 → 全选；已全选 → 全部取消。
func toggle_quality(rarity: int) -> void:
	var on := chip_on(rarity)
	for item in items:
		if int(item.rarity) != rarity:
			continue
		var id := str(item.get("id", ""))
		if on:
			_selected.erase(id)
		else:
			_selected[id] = true


## 一件装备能分到多少精粹（BagModel.normalize 已按部位、强化等级算好放在 decompose_exp）。
static func gain_of(item: Dictionary) -> int:
	return int(item.get("decompose_exp", 0))


## 其中强化返还部分（等级 × 每级返还）。
func refund_of(item: Dictionary) -> int:
	if bag == null or bag.enhance == null:
		return 0
	return maxi(0, int(item.get("enhance", 0))) * bag.enhance.refund_per_level()


func total_gain() -> int:
	var sum := 0
	for item in selected_items():
		sum += gain_of(item)
	return sum


func total_refund() -> int:
	var sum := 0
	for item in selected_items():
		sum += refund_of(item)
	return sum


## 「白 2 · 绿 3 · 紫 1」：只写选了的品质。
func quality_line() -> String:
	var parts: Array[String] = []
	for rarity in QUALITY_NAMES.size():
		var n := selected_of(rarity)
		if n > 0:
			parts.append("%s %d" % [QUALITY_NAMES[rarity], n])
	return " · ".join(parts)


## 选中里有紫 / 橙 → 确认前要二次确认。
func needs_rare_confirm() -> bool:
	for item in selected_items():
		if int(item.rarity) >= RARE_MIN:
			return true
	return false


func rare_items() -> Array[Dictionary]:
	return selected_items().filter(func(i: Dictionary) -> bool: return int(i.rarity) >= RARE_MIN)


## 二次确认第一行：「包含 紫装 ×2 · 橙装 ×1」（只含一种时只写那一种）。
func rare_line() -> String:
	var parts: Array[String] = []
	for rarity in [3, 4]:
		var n := selected_of(rarity)
		if n > 0:
			parts.append("%s ×%d" % [RARE_WORDS[rarity], n])
	return ("包含 " + " · ".join(parts)) if not parts.is_empty() else ""


## 二次确认缩略图：≤4 件全列；更多时前 3 件 + 「+N」。返回 {shown: Array[Dictionary], more: int}。
func rare_preview() -> Dictionary:
	var rare := rare_items()
	if rare.size() <= 4:
		return {"shown": rare, "more": 0}
	return {"shown": rare.slice(0, 3), "more": rare.size() - 3}


static func rare_caption(item: Dictionary) -> String:
	var rarity := int(item.get("rarity", 0))
	var level := int(item.get("enhance", 0))
	return str(RARE_TIER.get(rarity, "")) + ((" +%d" % level) if level > 0 else "")


## 确认按钮：{enabled, sub}。N=0 时灰掉、副标「请先选择装备」。
func confirm_state() -> Dictionary:
	var n := selected_count()
	return {"enabled": n > 0, "sub": ("分解 %d 件" % n) if n > 0 else "请先选择装备"}


func _find(id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == id:
			return item
	return {}
