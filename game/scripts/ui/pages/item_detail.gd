class_name ItemDetail
extends RefCounted
## 物品详情弹层的内容：名称/品质/部位、属性、与已穿戴装备对比、强化、操作按钮（穿戴/脱下/强化/分解）。
## 行囊页和装备栏页共用。点击操作通过 handlers 回调出去，这里不碰网络。
## handlers 可用键：equip(id) unequip(id) use(id) enhance(id, to_max) breakthrough(id) decompose(id)
## pool 是玩家的强化经验池（用来强化）。分解装备得到强化经验，不出售、不换修为。


static func show_item(popup: GamePopup, item: Dictionary, worn: Dictionary, handlers: Dictionary, pool: int = 0) -> void:
	popup.clear_content()
	var id := str(item.get("id", ""))
	var rarity := int(item.get("rarity", 0))
	var color := UiTokens.rarity_color(rarity)
	var equipped := bool(item.get("equipped", false))
	var is_gear := str(item.get("category", "")) == "equip"

	var head := UiKit.hbox(UiTokens.SP_3)
	popup.body.add_child(head)
	var preview := ItemSlot.new()
	preview.custom_minimum_size = Vector2(ItemSlot.MIN_SIZE + 24, ItemSlot.MIN_SIZE + 24)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview.disabled = true
	preview.set_item(item)
	head.add_child(preview)
	var info := UiKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	var name_label := UiKit.label(str(item.get("name", "")), UiTokens.FS_H2, color)
	name_label.add_theme_font_override("font", ArtLib.title_font())
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	var slot := SlotConfig.find(str(item.get("slot_id", "")))
	var kind_text := str(slot.get("name", "")) if not slot.is_empty() else _kind_name(str(item.get("kind", "")))
	info.add_child(UiKit.label("%s · %s" % [str(item.get("rarity_name", "")), kind_text], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	if is_gear:
		var enhance := int(item.get("enhance", 0))
		var cap := int(item.get("enhance_cap", 0))
		var level_text := "未强化" if enhance == 0 else "强化 +%d" % enhance
		if cap > 0:
			level_text += "  /  上限 +%d" % cap
		info.add_child(UiKit.label(level_text, UiTokens.FS_CAPTION, UiTokens.GOLD if enhance > 0 else UiTokens.TEXT_MUTED))
	var flags: Array[String] = []
	if equipped:
		flags.append("已穿戴")
	if int(item.get("qty", 1)) > 1:
		flags.append("数量 %d" % int(item.get("qty", 1)))
	if not flags.is_empty():
		info.add_child(UiKit.label(" · ".join(flags), UiTokens.FS_CAPTION, UiTokens.JADE))

	var desc := str(item.get("desc", ""))
	if not desc.is_empty():
		popup.body.add_child(UiKit.wrap_label(desc))

	if is_gear:
		_add_attributes(popup.body, item, worn if not equipped else {})
		_add_enhance(popup, item, handlers, pool)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", UiTokens.TAP_GAP)
	grid.add_theme_constant_override("v_separation", UiTokens.TAP_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup.body.add_child(UiKit.spacer(UiTokens.SP_1))
	popup.body.add_child(grid)

	if is_gear:
		var slot_ok := SlotConfig.is_equippable(str(item.get("slot_id", "")))
		if equipped:
			grid.add_child(_action("脱下", MainTheme.VAR_PRIMARY, popup, handlers, "unequip", id))
		else:
			var text := "替换" if not worn.is_empty() else "穿戴"
			var equip_button := _action(text, MainTheme.VAR_PRIMARY, popup, handlers, "equip", id)
			equip_button.disabled = not slot_ok
			grid.add_child(equip_button)
		var decompose_button := _action("分解 +%d 强化经验" % int(item.get("decompose_exp", 0)), MainTheme.VAR_DANGER, popup, handlers, "decompose", id)
		var block_reason := BagModel.decompose_block_reason(item)
		decompose_button.disabled = not block_reason.is_empty()
		grid.add_child(decompose_button)
		if not block_reason.is_empty():
			# 不能分解时直接写出原因（已穿戴的装备不能分解，要先脱下）。
			popup.body.add_child(UiKit.wrap_label("不能分解：%s。" % block_reason, UiTokens.FS_CAPTION, UiTokens.WARNING))
		elif not worn.is_empty() and int(item.get("power", 0)) > int(worn.get("power", 0)):
			popup.body.add_child(UiKit.wrap_label("这件比身上的更强，建议先穿戴再处理旧的。", UiTokens.FS_MICRO, UiTokens.WARNING))
	elif str(item.get("kind", "")) == "skill_book":
		grid.add_child(_action("使用（学习功法）", MainTheme.VAR_PRIMARY, popup, handlers, "use", id))
	popup.open_popup("物品详情")


## 强化区：下一级所需经验、强化经验池、强化 / 一键强化；卡在突破节点时显示需要的材料和「突破」按钮。
## 强化只消耗强化经验，必定成功；突破只消耗行囊里的材料，也必定成功。
static func _add_enhance(popup: GamePopup, item: Dictionary, handlers: Dictionary, pool: int) -> void:
	var cap := int(item.get("enhance_cap", 0))
	if cap <= 0:
		return
	var id := str(item.get("id", ""))
	var level := int(item.get("enhance", 0))
	var card := UiKit.card("强化")
	popup.body.add_child(card.panel)
	if level >= cap:
		card.body.add_child(UiKit.label("已强化到上限 +%d" % cap, UiTokens.FS_BODY, UiTokens.GOLD))
		return
	var view: Dictionary = item.get("break_view", {})
	var pending: Dictionary = view.get("pending", {})
	if not pending.is_empty():
		_add_break_block(popup, card, id, level, pending, handlers)
		return
	var cost := int(item.get("enhance_cost", 0))
	var row := UiKit.hbox(UiTokens.SP_2)
	card.body.add_child(row)
	var left := UiKit.label("+%d → +%d" % [level, level + 1], UiTokens.FS_BODY_L, UiTokens.TEXT)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	row.add_child(UiKit.icon("res_enhance", 44, UiTokens.GOLD))
	row.add_child(UiKit.label("%d / %d" % [pool, cost], UiTokens.FS_BODY_L, UiTokens.SUCCESS if pool >= cost else UiTokens.WARNING, HORIZONTAL_ALIGNMENT_RIGHT))
	card.body.add_child(UiKit.ratio_bar(clampf(float(pool) / float(maxi(cost, 1)), 0.0, 1.0), "bar_fill_gold" if pool >= cost else "bar_fill_jade", 44))
	var buttons := UiKit.hbox(UiTokens.TAP_GAP)
	card.body.add_child(buttons)
	var one := UiKit.button("强化", MainTheme.VAR_JADE)
	one.disabled = pool < cost
	one.pressed.connect(func() -> void:
		popup.close_popup()
		var callback: Variant = handlers.get("enhance", null)
		if callback is Callable:
			(callback as Callable).call(id, false))
	buttons.add_child(one)
	var many := UiKit.button("一键强化", MainTheme.VAR_SECONDARY)
	many.disabled = pool < cost
	many.pressed.connect(func() -> void:
		popup.close_popup()
		var callback: Variant = handlers.get("enhance", null)
		if callback is Callable:
			(callback as Callable).call(id, true))
	buttons.add_child(many)
	if pool < cost:
		card.body.add_child(UiKit.wrap_label("强化经验不足。分解不用的装备可以获得强化经验。", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var upcoming: Dictionary = view.get("next", {})
	if not upcoming.is_empty():
		card.body.add_child(UiKit.divider())
		card.body.add_child(UiKit.wrap_label("下一个突破节点 +%d：%s。升到 +%d 后，需要先突破才能继续。" % [int(upcoming.level), _materials_text(upcoming), int(upcoming.level)], UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))


## 卡在突破节点：列出每种材料的 现有/需要，材料够了才能点「突破」。
static func _add_break_block(popup: GamePopup, card: Dictionary, id: String, level: int, node: Dictionary, handlers: Dictionary) -> void:
	card.body.add_child(UiKit.label("已到突破节点 +%d" % level, UiTokens.FS_BODY_L, UiTokens.GOLD))
	card.body.add_child(UiKit.wrap_label("交齐材料突破后，才能继续强化。材料从行囊扣除，突破不会失败。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	for material in node.get("materials", []):
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var enough := int(material.have) >= int(material.need)
		var name_label := UiKit.label(str(material.name), UiTokens.FS_BODY, UiTokens.TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(UiKit.label("%s %d / %d" % ["✓" if enough else "✗", int(material.have), int(material.need)], UiTokens.FS_BODY, UiTokens.SUCCESS if enough else UiTokens.DANGER, HORIZONTAL_ALIGNMENT_RIGHT))
	var ready := bool(node.get("ready", false))
	var go := UiKit.button("突破", MainTheme.VAR_PRIMARY)
	go.disabled = not ready
	go.pressed.connect(func() -> void:
		popup.close_popup()
		var callback: Variant = handlers.get("breakthrough", null)
		if callback is Callable:
			(callback as Callable).call(id))
	card.body.add_child(go)
	if not ready:
		card.body.add_child(UiKit.wrap_label("材料不足，凑齐后才能突破。", UiTokens.FS_MICRO, UiTokens.WARNING))


static func _materials_text(node: Dictionary) -> String:
	var parts: Array[String] = []
	for material in node.get("materials", []):
		parts.append("%s ×%d（有 %d）" % [str(material.name), int(material.need), int(material.have)])
	return "、".join(parts)


static func _add_attributes(body: VBoxContainer, item: Dictionary, worn: Dictionary) -> void:
	var compare := not worn.is_empty()
	var card := UiKit.card("属性" if not compare else "属性（对比身上的 %s）" % str(worn.get("name", "")))
	body.add_child(card.panel)
	var rows := BagModel.compare(item, worn)
	if rows.is_empty():
		card.body.add_child(UiKit.label("没有属性加成", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
	for row in rows:
		var line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(line)
		var key := UiKit.label(str(row.label), UiTokens.FS_BODY, UiTokens.TEXT_MUTED)
		key.custom_minimum_size = Vector2(160, 0)
		line.add_child(key)
		var value := UiKit.label(str(BagModel.shown(float(row.value))), UiTokens.FS_BODY, UiTokens.TEXT)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		if compare:
			line.add_child(_delta_label(BagModel.shown(float(row.delta))))
	if str(item.get("category", "")) == "equip":
		var power_line := UiKit.hbox(UiTokens.SP_2)
		card.body.add_child(UiKit.divider())
		card.body.add_child(power_line)
		var power_key := UiKit.label("战力", UiTokens.FS_BODY, UiTokens.GOLD)
		power_key.custom_minimum_size = Vector2(160, 0)
		power_line.add_child(power_key)
		var power_value := UiKit.label(str(int(item.get("power", 0))), UiTokens.FS_BODY, UiTokens.GOLD)
		power_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		power_line.add_child(power_value)
		if compare:
			power_line.add_child(_delta_label(int(item.get("power", 0)) - int(worn.get("power", 0))))


## 对比差值：同时用符号和颜色表达（▲ 变强 / ▼ 变弱 / － 持平），不只靠颜色。
static func _delta_label(delta: int) -> Label:
	if delta > 0:
		return UiKit.label("▲ +%d" % delta, UiTokens.FS_BODY, UiTokens.SUCCESS, HORIZONTAL_ALIGNMENT_RIGHT)
	if delta < 0:
		return UiKit.label("▼ %d" % delta, UiTokens.FS_BODY, UiTokens.DANGER, HORIZONTAL_ALIGNMENT_RIGHT)
	return UiKit.label("－ 持平", UiTokens.FS_BODY, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


static func _action(text: String, variation: StringName, popup: GamePopup, handlers: Dictionary, key: String, id: String, close_first: bool = true) -> Button:
	var button := UiKit.button(text, variation)
	button.pressed.connect(func() -> void:
		if close_first:
			popup.close_popup()
		var callback: Variant = handlers.get(key, null)
		if callback is Callable:
			(callback as Callable).call(id))
	return button


## 二次确认（分解等危险操作）。
static func show_confirm(popup: GamePopup, title: String, message: String, confirm_text: String, on_confirm: Callable) -> void:
	popup.clear_content()
	popup.body.add_child(UiKit.wrap_label(message, UiTokens.FS_BODY, UiTokens.TEXT))
	popup.set_actions([
		{"text": "取消", "variation": MainTheme.VAR_SECONDARY},
		{"text": confirm_text, "variation": MainTheme.VAR_DANGER, "callback": on_confirm},
	])
	popup.open_popup(title)


static func _kind_name(kind: String) -> String:
	match kind:
		"equipment":
			return "装备"
		"material":
			return "材料"
		"consumable", "pill", "elixir":
			return "丹药"
		"skill_book":
			return "功法书"
		_:
			return "物品"
