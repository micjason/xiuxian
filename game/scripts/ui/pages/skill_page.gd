class_name SkillPage
extends VBoxContainer
## 功法页：已学功法列表，每门显示名称、层数、心法/功法、运转状态和运转/停止按钮。
## 数据：state.skills（skillSlug/level/runningSlot）+ content.skills。操作通过 action_requested 发出。

## kind: run / stop；args: [skillSlug]
signal action_requested(kind: String, slug: String)

var _state: Dictionary = {}
var _content: Dictionary = {}
var _summary: Label
var _hint: Label
var _list: VBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", UiTokens.SP_2)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := UiKit.label("功法", UiTokens.FS_H1, UiTokens.GOLD)
	title.add_theme_font_override("font", ArtLib.title_font())
	add_child(title)
	_summary = UiKit.label("", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED)
	add_child(_summary)
	_hint = UiKit.wrap_label("", UiTokens.FS_CAPTION, UiTokens.DANGER)
	_hint.visible = false
	add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = UiKit.vbox(UiTokens.SP_2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = not text.is_empty()


func bind(state: Dictionary, content: Dictionary) -> void:
	_state = state
	_content = content
	UiKit.clear(_list)
	var running_count := 0
	var learned := 0
	for row in state.get("skills", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var skill: Dictionary = row
		var running := BagModel.plain(skill.get("runningSlot", null))
		learned += 1
		if not running.is_empty():
			running_count += 1
		_list.add_child(_card(str(skill.get("skillSlug", "")), maxi(1, int(skill.get("level", 1))), running))
	if learned == 0:
		var empty := UiKit.card()
		(empty.body as VBoxContainer).add_child(UiKit.label("还没有功法", UiTokens.FS_BODY_L, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		(empty.body as VBoxContainer).add_child(UiKit.wrap_label("在「历练」里击败首领，掉落的功法书可在行囊中使用来学习。", UiTokens.FS_CAPTION))
		_list.add_child(empty.panel)
	_summary.text = "已学 %d 门 · 运转中 %d 门" % [learned, running_count]


func _def(slug: String) -> Dictionary:
	for row in _content.get("skills", []):
		if typeof(row) == TYPE_DICTIONARY and str((row as Dictionary).get("slug", "")) == slug:
			return row
	return {}


func _card(slug: String, level: int, running: String) -> Control:
	var definition := _def(slug)
	var is_heart := str(definition.get("role", "")) == "heart"
	var card := UiKit.card()
	var body := card.body as VBoxContainer
	var row := UiKit.hbox(UiTokens.SP_2)
	body.add_child(row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(150, 150)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_theme_stylebox_override("panel", ArtLib.nine("slot_r3" if is_heart else "slot_r2"))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(UiKit.icon("ui_yinyang" if is_heart else "cat_scroll", 96, UiTokens.rarity_color(3 if is_heart else 2).lightened(0.25)))
	row.add_child(frame)
	var info := UiKit.vbox(UiTokens.SP_1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var name := str(definition.get("displayName", ""))
	var name_label := UiKit.label(name if not name.is_empty() else "功法不存在", UiTokens.FS_H2, UiTokens.TEXT)
	name_label.add_theme_font_override("font", ArtLib.title_font())
	info.add_child(name_label)
	var status_text := "运转中" if not running.is_empty() else "未运转"
	var status_color := UiTokens.SUCCESS if not running.is_empty() else UiTokens.TEXT_MUTED
	info.add_child(UiKit.label("%d 层 · %s · %s" % [level, "心法" if is_heart else "功法", status_text], UiTokens.FS_CAPTION, status_color))
	row.add_child(info)
	var running_now := not running.is_empty()
	var action := UiKit.button("停止" if running_now else "运转", MainTheme.VAR_SECONDARY if running_now else MainTheme.VAR_JADE)
	action.size_flags_horizontal = Control.SIZE_SHRINK_END
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.custom_minimum_size = Vector2(220, UiTokens.H_TOUCH)
	action.pressed.connect(func() -> void: action_requested.emit("stop" if running_now else "run", slug))
	row.add_child(action)
	return card.panel
