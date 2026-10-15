class_name CavePage
extends VBoxContainer
## 洞府页（设计稿 03，原型阶段只展示）：五处建筑的等级与每小时产出，不能点击升级、没有收取。

var _grid: GridContainer


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(UiKit.page_title("洞府"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := UiKit.vbox(UiTokens.SP_2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(_gate_card())
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", UiTokens.SP_2)
	_grid.add_theme_constant_override("v_separation", UiTokens.SP_2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_grid)
	for building in CaveView.buildings():
		_grid.add_child(_building_card(building))
	var note := UiKit.card()
	column.add_child(note.panel)
	(note.body as VBoxContainer).add_child(UiKit.label("洞府 · 五处建筑", UiTokens.FS_BODY, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	(note.body as VBoxContainer).add_child(UiKit.wrap_label("各建筑的等级与每小时产出仅作展示，后续版本开放。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))


func _gate_card() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 220)
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(UiTokens.SP_1)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var gate := UiKit.icon("ui_gate", 120, UiTokens.GOLD_HOVER)
	gate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(gate)
	column.add_child(UiKit.label("洞府", UiTokens.FS_H2, UiTokens.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	return panel


func _building_card(building: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Building_%s" % str(building.get("id", ""))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", ArtLib.nine("panel_card"))
	var column := UiKit.vbox(UiTokens.SP_1)
	panel.add_child(column)
	var head := UiKit.hbox(UiTokens.SP_1)
	column.add_child(head)
	head.add_child(UiKit.icon(str(building.get("icon", "ui_pagoda")), 64, UiTokens.JADE))
	var names := UiKit.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(UiKit.label(str(building.get("name", "")), UiTokens.FS_BODY, UiTokens.GOLD_HOVER))
	names.add_child(UiKit.label(CaveView.level_text(building), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	column.add_child(UiKit.label(CaveView.output_text(building), UiTokens.FS_CAPTION, UiTokens.TEXT))
	return panel
