class_name SectPanelController
extends VBoxContainer

var session: CultivationSession
var expanded := false
var _summary_button: Button
var _details: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_summary_button = Button.new()
	_summary_button.custom_minimum_size.y = 58
	_summary_button.pressed.connect(func() -> void:
		expanded = not expanded
		_refresh()
	)
	add_child(_summary_button)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	add_child(_details)
	_refresh()


func bind_session(value: CultivationSession) -> void:
	session = value
	_refresh()


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	if _summary_button == null:
		return
	for child in _details.get_children():
		child.queue_free()
	_details.visible = expanded
	if session == null or session.state == null:
		_summary_button.text = "门派 · 尚未开启"
		return
	var sect := session.state.long_term.sect
	var position := session.long_term_config.position_by_id(sect.position_id)
	var sect_def := session.long_term_config.sect_by_id(sect.sect_id)
	_summary_button.text = "门派 · %s%s" % [
		sect_def.display_name if sect_def != null else "散修",
		(" · %s" % position.display_name) if position != null else "",
	]
	if not expanded:
		return
	if not sect.has_joined():
		for definition in session.long_term_config.sects:
			var button := Button.new()
			button.text = "拜入 %s" % definition.display_name
			button.disabled = (
				session.state.long_term.cave.building_level(definition.join_building_id)
				< definition.join_building_level
			)
			button.pressed.connect(_join.bind(definition.id))
			_details.add_child(button)
		return
	_add_label("贡献 %d · 同门 %d 人" % [
		sect.contribution,
		sect.joined_npc_ids.size(),
	])
	for definition in session.long_term_config.positions:
		var button := Button.new()
		button.text = "职位：%s（需贡献 %d）" % [
			definition.display_name,
			definition.contribution_required,
		]
		button.disabled = (
			sect.position_id == definition.id
			or sect.contribution < definition.contribution_required
		)
		button.pressed.connect(_claim_position.bind(definition.id))
		_details.add_child(button)
	for npc in session.long_term_config.npcs:
		var button := Button.new()
		button.text = "%s · %s" % [
			npc.display_name,
			"已结交" if sect.has_npc(npc.id) else "结交需贡献 %d" % npc.contribution_required,
		]
		button.disabled = sect.has_npc(npc.id) or sect.contribution < npc.contribution_required
		button.pressed.connect(_recruit.bind(npc.id))
		_details.add_child(button)


func _join(sect_id: String) -> void:
	session.join_sect(sect_id)
	_refresh()


func _claim_position(position_id: String) -> void:
	session.claim_sect_position(position_id)
	_refresh()


func _recruit(npc_id: String) -> void:
	session.recruit_sect_npc(npc_id)
	_refresh()


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.add_child(label)
