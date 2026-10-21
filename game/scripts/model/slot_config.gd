class_name SlotConfig
extends RefCounted
## 装备部位配置表。装备栏界面完全按这张表生成，不在界面代码里写死部位。
##
## 6 个核心部位（武器、头部、身体、手部、腿/鞋、饰品）+ 2 个预留位（法宝、灵宠，第三期开放）。
## 服务器部位键与这里的 server 字段一一对应。
## locked=true 的部位显示为锁定占位。
## 批次②：部位名字以服务器部位表为准（/content/current 的 globals.slots，Catalog.apply → apply_names），
## 这里的 name 只是拿到内容前的默认值（和服务器 catalog.ts 一致）。

const CORE: Array[Dictionary] = [
	{"id": "weapon", "name": "武器", "glyph": "剑", "server": "weapon", "supported": true, "side": "left"},
	{"id": "helmet", "name": "头冠", "glyph": "冠", "server": "helmet", "supported": true, "side": "left"},
	{"id": "clothes", "name": "衣服", "glyph": "袍", "server": "clothes", "supported": true, "side": "left"},
	{"id": "gloves", "name": "护手", "glyph": "护", "server": "gloves", "supported": true, "side": "right"},
	{"id": "shoes", "name": "鞋子", "glyph": "靴", "server": "shoes", "supported": true, "side": "right"},
	{"id": "accessory", "name": "饰品", "glyph": "佩", "server": "accessory", "supported": true, "side": "right"},
]

const EXTRA: Array[Dictionary] = [
	{"id": "artifact", "name": "法宝", "glyph": "宝", "server": "", "supported": false, "locked": true, "note": "第三期开放"},
	{"id": "pet", "name": "灵宠", "glyph": "宠", "server": "", "supported": false, "locked": true, "note": "第三期开放"},
]


## 服务器部位键 → 名字（Catalog.apply 写入）。空 = 用默认名。
static var _names: Dictionary = {}


static func apply_names(names: Dictionary) -> void:
	_names = names.duplicate()


static func _named(list: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in list:
		var key := str(slot.get("server", ""))
		if not key.is_empty() and _names.has(key):
			var copy := slot.duplicate()
			copy["name"] = str(_names[key])
			out.append(copy)
		else:
			out.append(slot)
	return out


static func core() -> Array[Dictionary]:
	return _named(CORE)


static func extra() -> Array[Dictionary]:
	return EXTRA


static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(core())
	out.append_array(EXTRA)
	return out


static func find(slot_id: String) -> Dictionary:
	for slot in all():
		if str(slot.get("id", "")) == slot_id:
			return slot
	return {}


## 服务器部位键（如 "helmet"）→ 界面部位 id。未知键返回空字符串。
static func id_from_server(server_key: String) -> String:
	if server_key.is_empty():
		return ""
	for slot in all():
		if str(slot.get("server", "")) == server_key:
			return str(slot.get("id", ""))
	return ""


## 能穿戴的部位（服务器支持，且没有锁）。
static func is_equippable(slot_id: String) -> bool:
	var slot := find(slot_id)
	return not slot.is_empty() and bool(slot.get("supported", false)) and not bool(slot.get("locked", false))


## 服务器已支持的部位数量，用来在界面上提示缺口。
static func server_supported_count() -> int:
	var count := 0
	for slot in CORE:
		if bool(slot.get("supported", false)):
			count += 1
	return count
