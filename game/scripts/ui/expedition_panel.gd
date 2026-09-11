class_name ExpeditionPanelController
extends VBoxContainer

var session: CultivationSession
var _result_text := ""


func _ready() -> void:
	add_theme_constant_override("separation", 7)
	_refresh()


func bind_session(value: CultivationSession) -> void:
	session = value
	_refresh()


func refresh() -> void:
	_refresh()


func _refresh() -> void:
	for child in get_children():
		child.queue_free()
	if session == null or session.state == null:
		return
	var heading := Label.new()
	heading.text = "秘境与奇遇 · 委托战力 %d" % session.expedition_power()
	heading.add_theme_font_size_override("font_size", 21)
	heading.add_theme_color_override("font_color", Color("dcc076"))
	add_child(heading)
	var state := session.state.long_term.expedition
	for definition in session.long_term_config.expeditions:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s · 钥印 %d · 需战力 %d" % [
			definition.display_name,
			state.key_count(definition.key_id),
			definition.required_power,
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var enter := Button.new()
		enter.text = "探索"
		enter.disabled = (
			state.key_count(definition.key_id) <= 0
			or session.expedition_power() < definition.required_power
		)
		enter.pressed.connect(_run.bind(definition.id))
		row.add_child(enter)
		var auto := Button.new()
		var active := state.auto_expedition_id == definition.id
		auto.text = "委托中" if active else "自动"
		auto.disabled = active
		auto.pressed.connect(_set_auto.bind(definition.id))
		row.add_child(auto)
		add_child(row)
	if not state.auto_expedition_id.is_empty():
		var stop := Button.new()
		stop.text = "停止自动委托"
		stop.pressed.connect(_set_auto.bind(""))
		add_child(stop)
	if not _result_text.is_empty():
		var result := Label.new()
		result.text = _result_text
		result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(result)


func _run(expedition_id: String) -> void:
	var result := session.run_expedition(expedition_id)
	if bool(result.get("success", false)):
		var definition := session.long_term_config.expedition_by_id(expedition_id)
		var encounter_id := str(result.get("encounter_id", ""))
		var encounter_name := encounter_id
		if definition != null:
			for encounter in definition.encounters:
				if encounter.id == encounter_id:
					encounter_name = encounter.display_name
					break
		_result_text = "奇遇：%s。所得已送回洞府。" % encounter_name
	else:
		_result_text = "此次未能进入秘境，请检查钥印与战力。"
	_refresh()


func _set_auto(expedition_id: String) -> void:
	session.set_auto_expedition(expedition_id)
	_result_text = "自动委托已%s。" % ("停止" if expedition_id.is_empty() else "启用")
	_refresh()
