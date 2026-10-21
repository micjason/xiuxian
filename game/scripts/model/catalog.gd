class_name Catalog
extends RefCounted
## 部位表 / 品质表（批次②统一）：服务器 catalog.ts 是唯一的一份，经 /content/current 的 globals.slots / globals.qualities 下发。
## 游戏不再自己写部位名、品质名：拿到内容后调 apply(content)，SlotConfig / UiTokens.RARITY_NAMES 就换成服务器的名字。
## 品质固定 5 档 白→橙（红已去掉，迁移 0028 把旧红装并到橙）；下标 0..4 对应 UiTokens 的颜色。

const QUALITY_KEYS: Array[String] = ["white", "green", "blue", "purple", "orange"]


## 品质键 → 下标。未知键按白；老数据里的 red 按橙（服务器已迁移，这里只是兜底）。
static func quality_index(key: String) -> int:
	if key == "red":
		return QUALITY_KEYS.size() - 1
	return maxi(0, QUALITY_KEYS.find(key))


static func quality_name(index: int) -> String:
	return UiTokens.RARITY_NAMES[clampi(index, 0, UiTokens.RARITY_NAMES.size() - 1)]


static func slot_name(server_key: String) -> String:
	for slot in SlotConfig.core():
		if str(slot.get("server", "")) == server_key:
			return str(slot.get("name", server_key))
	return server_key


static func apply(content: Dictionary) -> void:
	var globals: Variant = content.get("globals", null)
	if typeof(globals) != TYPE_DICTIONARY:
		return
	var qualities: Variant = (globals as Dictionary).get("qualities", null)
	if typeof(qualities) == TYPE_ARRAY and not (qualities as Array).is_empty():
		var names: Array[String] = UiTokens.RARITY_NAMES.duplicate()
		while names.size() < QUALITY_KEYS.size():
			names.append("")
		for row in qualities:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var index := QUALITY_KEYS.find(str((row as Dictionary).get("key", "")))
			var name := str((row as Dictionary).get("name", ""))
			if index >= 0 and not name.is_empty():
				names[index] = name
		UiTokens.RARITY_NAMES = names.slice(0, QUALITY_KEYS.size())
	var slots: Variant = (globals as Dictionary).get("slots", null)
	if typeof(slots) == TYPE_ARRAY and not (slots as Array).is_empty():
		var slot_names := {}
		for row in slots:
			if typeof(row) == TYPE_DICTIONARY and not str((row as Dictionary).get("name", "")).is_empty():
				slot_names[str((row as Dictionary).get("key", ""))] = str((row as Dictionary).get("name", ""))
		SlotConfig.apply_names(slot_names)
