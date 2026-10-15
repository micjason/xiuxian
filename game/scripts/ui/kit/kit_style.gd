class_name KitStyle
extends RefCounted
## 通用组件（物品格、装备格、弹窗……）的样式出口。
## 框体、图标都从 ArtLib 取（res://assets/art/）；换正式美术时同名文件覆盖即可。
## 仍保留 Theme 覆盖口：Theme 里提供同名样式时优先用 Theme 的（类型 ItemSlot / EquipSlot / GamePopup）。
##   - 物品格边框：ItemSlot 的 slot_r0..slot_r5、slot_empty、slot_selected
##   - 装备格：EquipSlot 的 filled、empty、locked
##   - 物品图标：assets/art/items/<物品 slug>.png 存在就显示原图（不染色）；
##     没有就用部位/类别剪影图标，按品质染色。


static func box(fill: Color, border: Color, border_width: int, radius: int, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(padding)
	style.anti_aliasing = true
	return style


## 先问 Theme 有没有覆盖样式，没有就用美术资源。
static func themed(control: Control, style_name: StringName, theme_type: StringName, art: StyleBox) -> StyleBox:
	if control != null and control.has_theme_stylebox(style_name, theme_type):
		return control.get_theme_stylebox(style_name, theme_type)
	return art


static func slot_box(control: Control, rarity: int, selected: bool = false, pressed: bool = false) -> StyleBox:
	var name := "slot_selected" if selected else ArtLib.slot_frame(rarity)
	var art := ArtLib.nine(name, Color(1.25, 1.25, 1.25) if pressed else Color.WHITE)
	return themed(control, StringName(name), &"ItemSlot", art)


static func empty_slot_box(control: Control) -> StyleBox:
	return themed(control, &"slot_empty", &"ItemSlot", ArtLib.nine("slot_empty"))


static func locked_slot_box(control: Control) -> StyleBox:
	return themed(control, &"locked", &"EquipSlot", ArtLib.nine("slot_locked"))


## 物品图标。返回 {texture, tint}：tint=true 表示是白色剪影，需要按品质染色。texture 可能为 null。
static func icon_for(item: Dictionary) -> Dictionary:
	var found := ArtLib.item_icon(item)
	return {"texture": found.get("texture"), "tint": bool(found.get("tint", true))}


## 图标缺失时占位图标上显示的字：装备用部位字，其他用名称首字。
static func glyph_of(item: Dictionary) -> String:
	var slot := SlotConfig.find(str(item.get("slot_id", "")))
	if not slot.is_empty():
		return str(slot.get("glyph", ""))
	var name := str(item.get("name", ""))
	return name.substr(0, 1) if not name.is_empty() else "?"


## 品质光晕的强度：珍品以上才有光晕，越高越亮。
static func glow_alpha(rarity: int) -> float:
	return [0.0, 0.0, 0.0, 0.35, 0.5, 0.65][clampi(rarity, 0, 5)]
