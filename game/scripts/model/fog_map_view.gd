class_name FogMapView
extends RefCounted
## 迷雾秘境状态整形；服 fog DTO 权威。地图定妆贴图见 FogMapPage / FogLevelTiles。

static func from_payload(data: Dictionary) -> Dictionary:
	var fog: Variant = data.get("fog", data)
	if typeof(fog) != TYPE_DICTIONARY:
		return {}
	var f := fog as Dictionary
	var collect: Dictionary = f.get("collect", {}) if typeof(f.get("collect", {})) == TYPE_DICTIONARY else {}
	return {
		"protocol": str(f.get("protocol", "")),
		"revision": str(f.get("revision", "")),
		"map_id": str(f.get("mapId", "fog_wenxin_valley")),
		"name": str(f.get("displayName", "问心谷")),
		"rows": int(f.get("rows", 12)),
		"cols": int(f.get("cols", 8)),
		"pos": f.get("pos", {"x": 3, "y": 10}),
		"revealed": f.get("revealed", []),
		"blocks": f.get("blocks", []),
		"objects": f.get("objects", []),
		"travel": int(f.get("travelPoints", 0)),
		"travel_max": int(f.get("travelPointsMax", 200)),
		"explore_revealed": int(f.get("exploreRevealed", 0)),
		"explore_total": int(f.get("exploreTotal", 0)),
		"explore_full": bool(f.get("exploreFull", false)),
		"chests_opened": int(collect.get("chestsOpened", 0)),
		"chests_total": int(collect.get("chestsTotal", 3)),
		"monsters_defeated": int(collect.get("monstersDefeated", 0)),
		"monsters_total": int(collect.get("monstersTotal", 2)),
	}


static func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


static func is_revealed(view: Dictionary, x: int, y: int) -> bool:
	var arr: Variant = view.get("revealed", [])
	if typeof(arr) != TYPE_ARRAY:
		return false
	return cell_key(x, y) in (arr as Array)


static func is_blocked(view: Dictionary, x: int, y: int) -> bool:
	var arr: Variant = view.get("blocks", [])
	if typeof(arr) != TYPE_ARRAY:
		return false
	for b in arr:
		if typeof(b) != TYPE_DICTIONARY:
			continue
		if int(b.get("x", -1)) == x and int(b.get("y", -1)) == y:
			return true
	return false
