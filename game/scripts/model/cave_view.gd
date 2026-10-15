class_name CaveView
extends RefCounted
## 洞府页（原型阶段只展示）：五处建筑的等级和每小时产出。
## 这是设计稿里的静态展示数据，服务器没有洞府系统；后续版本开放时换成服务器数据。

const BUILDINGS: Array[Dictionary] = [
	{"id": "alchemy", "name": "炼丹房", "level": 5, "output_name": "丹药", "per_hour": 6, "icon": "cat_pill"},
	{"id": "library", "name": "藏经阁", "level": 3, "output_name": "道经", "per_hour": 2, "icon": "cat_book"},
	{"id": "field", "name": "灵田", "level": 6, "output_name": "灵草", "per_hour": 24, "icon": "cat_herb"},
	{"id": "forge", "name": "炼器室", "level": 4, "output_name": "精铁", "per_hour": 10, "icon": "cat_material"},
	{"id": "array", "name": "聚灵阵", "level": 8, "output_name": "灵气", "per_hour": 320, "icon": "ui_sparkle"},
]


static func buildings() -> Array[Dictionary]:
	return BUILDINGS


static func output_text(building: Dictionary) -> String:
	return "产出 %s +%d/时" % [str(building.get("output_name", "")), int(building.get("per_hour", 0))]


static func level_text(building: Dictionary) -> String:
	return "Lv.%d" % int(building.get("level", 0))
