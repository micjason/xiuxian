class_name StagePage
extends VBoxContainer
## 历练页（Q 版设计稿 q_adventure，底栏第二格）：
## 上半是挂机刷怪的场景（黑风岭背景、打坐的主角、正在刷的怪、本波进度圆点、击杀时飘「+修为」）；
## 下面是章节条 + 挂机地点下拉、关卡卡一排（每个已解锁关卡的怪 / 首领 / 下一个未解锁关卡）、
## 选中关卡的详情（怪物属性、推荐战力、掉落预览、首领首通奖励），最底下固定「自动挑战」开关（暂未开放）和「挑战」。
## 点「挑战」进入首领战界面（BattlePage）；只有选中有首领的关卡才有挑战按钮。数值都来自后台配置和 /me/state。

signal stage_selected(slug: String)
signal challenge_requested(slug: String)
## slug 为空串 = 恢复“自动（当前境界最高关卡）”。
signal idle_stage_requested(slug: String)
signal back_requested

## 页面区左上角在画布上的位置（紧凑顶栏 152 + 刘海 90 + 8，左右边距 24）。
const ORIGIN := Vector2(24, 250)
const SCENE_HEIGHT := 712.0
const CARD_SIZE := Vector2(236, 296)

var _state: Dictionary = {}
var _content: Dictionary = {}
var _stages: Array[Dictionary] = []
## 最近一个还没解锁的关卡（带锁图标显示）：{stage, realm, boss, monster, power}；没有就是空字典。
var _locked_stage: Dictionary = {}
## 当前境界之上最近一个有首领的关卡：{stage, boss, realm, power}。没有首领可打时用它说明“哪个境界解锁哪个首领”。
var _locked_next: Dictionary = {}
var selected := ""
var busy := false
var _dropdown_open := false

var _scene: Control
var _banner_title: Label
var _banner_chip: Label
var _pips: Array[Control] = []
var _monster: TextureRect
var _monster_far: TextureRect
var _monster_chip: Label
var _monster_hp: QBar
var _float_layer: Control
var _last_kills := -1
var _elapsed := 0.0

var _stage_view: ScrollContainer
var _stage_box: VBoxContainer
## 「挑战」按钮固定在页面底部（紧贴标签栏上方），详情在它上面滚动。
var _challenge_bar: HBoxContainer
var _challenge_button: Button
var _auto_toggle: Button


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_scene()
	_stage_view = ScrollContainer.new()
	_stage_view.name = "StageScroll"
	_stage_view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stage_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_stage_view)
	_stage_box = UiKit.vbox(18)
	_stage_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_view.add_child(_stage_box)
	_challenge_bar = UiKit.hbox(UiTokens.SP_2)
	_challenge_bar.name = "ChallengeBar"
	add_child(_challenge_bar)
	var orb_room := Control.new()
	orb_room.custom_minimum_size = Vector2(0, 96)
	orb_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb_room)


func _at(node: Control, rect: Rect2) -> Control:
	node.position = rect.position - ORIGIN
	node.size = rect.size
	_scene.add_child(node)
	return node


func _sprite(path: String, rect: Rect2, flip: bool = false) -> TextureRect:
	var node := TextureRect.new()
	node.texture = ArtLib.q(path) if ArtLib.has_q(path + ".png") else null
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.flip_h = flip
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(node, rect)
	return node


## 上半场景（设计稿 y 258–960）。
func _build_scene() -> void:
	_scene = Control.new()
	_scene.name = "IdleScene"
	_scene.custom_minimum_size = Vector2(0, SCENE_HEIGHT)
	_scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene)
	# 关卡横幅（左上）
	var banner := PanelContainer.new()
	banner.name = "StageBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_stylebox_override("panel", QKit.cut_box("panel_pill_100", 18, 0) if ArtLib.qui("panel_pill_100") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 50, 6, 18, 0))
	var row := UiKit.hbox(10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(row)
	row.add_child(UiKit.icon("tab_adventure", 76))
	_banner_title = QKit.title("", 44, UiTokens.TEXT)
	_banner_title.name = "BannerTitle"
	row.add_child(_banner_title)
	var chip := QKit.tag("挂机中", "orange", 30, 16)
	_banner_chip = chip.get_child(0) as Label
	row.add_child(chip)
	_at(banner, Rect2(26, 258, 520, 108))
	# 本波圆点（右上）
	var pips := PanelContainer.new()
	pips.name = "WavePips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_theme_stylebox_override("panel", QKit.cut_box("panel_pill_100", 22, 0) if ArtLib.qui("panel_pill_100") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 50, 6, 22, 0))
	var pip_row := UiKit.hbox(10)
	pip_row.name = "PipRow"
	pip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_child(pip_row)
	pip_row.add_child(QKit.title("本波", 34, UiTokens.TEXT_MUTED))
	_at(pips, Rect2(780, 258, 274, 108))
	# 主角 + 莲台 + 光晕
	_sprite("sprites/fx_aura_radial", Rect2(30, 520, 380, 380)).modulate = Color(1, 1, 1, 0.7)
	_sprite("sprites/lotus_platform", Rect2(60, 780, 280, 140))
	_sprite("sprites/hero_meditate", Rect2(54, 520, 300, 300))
	# 飞剑（装饰）
	var sword := TextureRect.new()
	sword.texture = ArtLib.icon("tab_adventure")
	sword.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sword.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sword.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sword.pivot_offset = Vector2(65, 65)
	sword.rotation = deg_to_rad(30)
	_at(sword, Rect2(470, 600, 130, 130))
	# 怪物（远处小一只 + 目标一只，都朝左）
	_monster_far = _sprite("sprites/mon_snake", Rect2(412, 450, 166, 166), true)
	_monster_far.modulate = Color(1, 1, 1, 0.9)
	_monster = _sprite("sprites/mon_snake", Rect2(560, 510, 340, 370), true)
	_monster.name = "TargetMonster"
	var name_chip := QKit.tag("", "cream", 30, 16)
	name_chip.name = "MonsterName"
	_monster_chip = name_chip.get_child(0) as Label
	_at(name_chip, Rect2(596, 432, 150, 52))
	_monster_hp = QKit.bar(1.0, UiTokens.Q_RED, 30, 1, UiTokens.Q_TRACK, "red") as QBar
	_monster_hp.name = "MonsterHp"
	_at(_monster_hp, Rect2(756, 444, 170, 30))
	_float_layer = Control.new()
	_float_layer.name = "KillFloats"
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_float_layer, Rect2(0, 258, 1080, 700))


## stages = 当前境界已解锁的全部关卡（有首领的和只刷怪的）；locked_stage = 下一个未解锁关卡；
## locked_boss = 之上最近的首领关（见 _locked_next）。
func bind(state: Dictionary, content: Dictionary, stages: Array[Dictionary], selected_slug: String, locked_boss: Dictionary = {}, locked_stage: Dictionary = {}) -> void:
	_state = state
	_content = content
	_stages = stages
	_locked_next = locked_boss
	_locked_stage = locked_stage
	selected = selected_slug
	_elapsed = 0.0
	_render_scene()
	_render_stages()


func set_busy(value: bool) -> void:
	busy = value
	_render_stages()


func _wave() -> Dictionary:
	return _state.get("wave", {}) if typeof(_state.get("wave", null)) == TYPE_DICTIONARY else {}


func _render_scene() -> void:
	var wave := _wave()
	var shown := WaveView.display(_state, 0.0)
	_banner_title.text = str(wave.get("stageName", "")) if bool(shown.available) else "未开启"
	_banner_chip.text = "挂机中" if bool(shown.available) else "未开启"
	var monster_name := str(shown.get("monster", ""))
	_monster_chip.text = monster_name
	_monster_chip.get_parent().visible = not monster_name.is_empty()
	_monster_hp.visible = not monster_name.is_empty()
	var sprite := ArtLib.monster_sprite_id(monster_name)
	var tex: Texture2D = ArtLib.q("sprites/" + sprite) if not sprite.is_empty() else (ArtLib.icon(ArtLib.boss_icon_name(monster_name)) if not monster_name.is_empty() else null)
	_monster.texture = tex
	_monster_far.texture = tex
	_monster.visible = tex != null
	_monster_far.visible = tex != null
	var pip_row := _scene.find_child("PipRow", true, false) as HBoxContainer
	while pip_row.get_child_count() > 1:
		var child := pip_row.get_child(1)
		pip_row.remove_child(child)
		child.queue_free()
	_pips.clear()
	for i in maxi(1, int(shown.get("wave_size", 3))):
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(44, 44)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip_row.add_child(pip)
		_pips.append(pip)
	_refresh_wave(shown)


func _process(delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_elapsed += delta
	var online := true
	var last: Variant = _state.get("lastSettle", null)
	if typeof(last) == TYPE_DICTIONARY and (last as Dictionary).has("online"):
		online = bool((last as Dictionary).get("online", true)) or int((last as Dictionary).get("seconds", 0)) == 0
	_refresh_wave(WaveView.display(_state, _elapsed if online else 0.0))


## 本波圆点 = 已击杀只数；怪物血条 = 当前这只还剩多少（按本地经过的时间推算，只是显示）。
func _refresh_wave(shown: Dictionary) -> void:
	var kills := int(shown.get("kills", 0))
	for i in _pips.size():
		var on := i < kills
		(_pips[i] as Panel).add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_MINT if on else Color("f1e2c6"), UiTokens.Q_COCOA, 4, 999, 0, 0, 0))
	var per := maxi(1, int(_wave().get("killsPerWave", shown.get("wave_size", 3))))
	var progress := float(shown.get("ratio", 0.0)) * float(per)
	_monster_hp.set_ratio(1.0 - (progress - floorf(progress)))
	if _last_kills >= 0 and kills > _last_kills and float(shown.get("kill_cultivation", 0)) > 0.0:
		_float_gain(float(shown.get("kill_cultivation", 0)) * float(kills - _last_kills))
	_last_kills = kills


## 击杀飘字「+N 修为」（美术位图数字 digits_xiuwei + 文字图 float_word_xiuwei）。
func _float_gain(amount: float) -> void:
	var row := UiKit.hbox(4)
	row.name = "KillFloat"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var number := Label.new()
	number.text = "+%s" % CultivationFormat.amount(amount)
	var font := ArtLib.digits_font("xiuwei")
	if font != null:
		number.add_theme_font_override("font", font)
		number.add_theme_font_size_override("font_size", 60)
		number.add_theme_color_override("font_color", Color.WHITE)
	else:
		number = QKit.outlined(number.text, 54, UiTokens.Q_WHITE, Color("2e8fd8"), 10)
	row.add_child(number)
	var word := QKit.cut_rect("float_word_xiuwei")
	row.add_child(word)
	row.position = Vector2(60, 40)
	_float_layer.add_child(row)
	row.scale = Vector2(0.6, 0.6)
	var tween := row.create_tween()
	tween.tween_property(row, "scale", Vector2(1.15, 1.15), 0.12)
	tween.tween_property(row, "scale", Vector2.ONE, 0.06)
	tween.tween_property(row, "position:y", row.position.y - 80.0, 0.8)
	tween.parallel().tween_property(row, "modulate:a", 0.0, 0.8)
	tween.tween_callback(row.queue_free)


func _render_stages() -> void:
	var keep_scroll := _stage_view.scroll_vertical
	UiKit.clear(_stage_box)
	UiKit.clear(_challenge_bar)
	_challenge_button = null
	var power := int(_state.get("power", 0))
	_stage_box.add_child(_idle_card())
	_stage_box.add_child(_cards_row(power))
	var current := _find(selected)
	if not current.is_empty():
		_stage_box.add_child(_detail_card(current, power))
	elif _stages.is_empty():
		var empty := QKit.panel()
		empty.panel.name = "StageDetailCard"
		empty.body.add_child(UiKit.wrap_label("这个境界还没有开放的关卡。", UiTokens.FS_BODY, UiTokens.TEXT_MUTED))
		_stage_box.add_child(empty.panel)
	_build_challenge_bar(current)
	_restore_scroll.call_deferred(keep_scroll)


func _restore_scroll(value: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_stage_view):
		_stage_view.scroll_vertical = value


static func _has_boss(stage: Dictionary) -> bool:
	return not (stage.get("bosses", []) as Array).is_empty()


## 章节条（设计稿 36,962,1008,100）：章节名 + 「挂机地点」下拉（服务器 wave.selectable / chosenStageSlug，null = 自动）。
## 点下拉展开选项列表（就在章节条下面），选了发 idle_stage_requested。
func _idle_card() -> Control:
	var wave := _wave()
	var box := UiKit.vbox(10)
	box.name = "IdleStageCard"
	var bar := QKit.panel(UiTokens.Q_CREAM, 50, 26, 10)
	bar.panel.custom_minimum_size = Vector2(0, 100)
	box.add_child(bar.panel)
	var row := UiKit.hbox(14)
	(bar.body as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(bar.body as VBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.body.add_child(row)
	var chapter := str(_stages[0].get("displayName", "")).get_slice("·", 0) if not _stages.is_empty() else str(_state.get("realmName", ""))
	row.add_child(QKit.title(chapter, 44, UiTokens.TEXT))
	row.add_child(UiKit.label("%s" % str(_state.get("realmName", "")), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(UiKit.label("挂机地点", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var chosen := BagModel.plain(wave.get("chosenStageSlug", null))
	var options: Array = wave.get("selectable", [])
	var current_text := "自动（最高关卡）"
	for option in options:
		if typeof(option) == TYPE_DICTIONARY and str((option as Dictionary).get("slug", "")) == chosen:
			current_text = str((option as Dictionary).get("name", chosen))
	var drop := Button.new()
	drop.name = "IdleDropdown"
	drop.focus_mode = Control.FOCUS_NONE
	drop.custom_minimum_size = Vector2(400, 68)
	drop.text = current_text + "   ▼"
	drop.alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop.clip_text = true
	var field: StyleBox = QKit.cut_box("field_dropdown_68", 24, 0) if ArtLib.qui("field_dropdown_68") != null else QSkin.custom(Color.WHITE, UiTokens.Q_COCOA, 4, 34, 4, 24, 0)
	field.content_margin_bottom = 4
	for state in ["normal", "hover", "pressed", "disabled"]:
		drop.add_theme_stylebox_override(state, field)
	drop.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	drop.add_theme_font_size_override("font_size", 34)
	drop.add_theme_color_override("font_color", UiTokens.TEXT)
	drop.add_theme_color_override("font_pressed_color", UiTokens.TEXT)
	drop.add_theme_color_override("font_hover_color", UiTokens.TEXT)
	drop.disabled = options.is_empty() or busy
	drop.pressed.connect(func() -> void:
		_dropdown_open = not _dropdown_open
		_render_stages())
	row.add_child(drop)
	if options.is_empty():
		box.add_child(UiKit.wrap_label("这个境界还没有可以刷怪的关卡。", UiTokens.FS_CAPTION, UiTokens.TEXT_MUTED))
		return box
	if _dropdown_open:
		var list := QKit.panel(UiTokens.Q_CREAM, 30, 20, 14)
		list.panel.name = "IdleOptions"
		box.add_child(list.panel)
		var auto := QKit.button("自动（最高关卡）" + ("  ✔" if chosen.is_empty() else ""), "o" if chosen.is_empty() else "c", 100, 34)
		auto.name = "IdleAuto"
		auto.pressed.connect(func() -> void:
			_dropdown_open = false
			idle_stage_requested.emit(""))
		list.body.add_child(auto)
		for option in options:
			if typeof(option) != TYPE_DICTIONARY:
				continue
			var slug := str((option as Dictionary).get("slug", ""))
			var on := slug == chosen
			var text := "%s · %s" % [str((option as Dictionary).get("name", slug)), str((option as Dictionary).get("monsterName", ""))]
			var button := QKit.button(text + ("  ✔" if on else ""), "o" if on else "c", 100, 34)
			button.name = "Idle_%s" % slug
			button.disabled = busy
			button.pressed.connect(func() -> void:
				_dropdown_open = false
				idle_stage_requested.emit(slug))
			list.body.add_child(button)
	return box


## 关卡卡一排（横向可滑）：每个已解锁关卡一张（怪物），有首领的关卡再加一张首领卡，最后是下一个未解锁关卡的锁定卡。
func _cards_row(power: int) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "StageCards"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, CARD_SIZE.y + 30)
	var row := UiKit.hbox(12)
	row.name = "CardRow"
	row.custom_minimum_size = Vector2(0, CARD_SIZE.y + 24)
	scroll.add_child(row)
	var cards: Array[Control] = []
	for stage in _stages:
		cards.append(_stage_card(stage))
	for stage in _stages:
		if _has_boss(stage):
			cards.append(_boss_card(stage, power))
	if not _locked_stage.is_empty():
		cards.append(_locked_card(_locked_stage))
	for index in cards.size():
		if index > 0:
			var link := QKit.cut_rect("btn_next_connector", Vector2(40, 40))
			link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(link)
		row.add_child(cards[index])
	return scroll


func _card_shell(name: String, cut: String, chosen: bool) -> Dictionary:
	var button := Button.new()
	button.name = name
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = CARD_SIZE + Vector2(0, 6)
	button.size_flags_vertical = Control.SIZE_SHRINK_END
	var box: StyleBox
	if ArtLib.qui(cut) != null:
		box = QKit.cut_box(cut, 10, 10)
	else:
		box = QSkin.custom(Color("ffe9b8") if chosen else UiTokens.Q_CARD, UiTokens.Q_COCOA, 4, 28, 6, 10, 10)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if chosen:
		button.custom_minimum_size = CARD_SIZE + Vector2(0, 22)
	var column := UiKit.vbox(6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 10
	column.offset_right = -10
	column.offset_top = 12
	column.offset_bottom = -16
	button.add_child(column)
	return {"button": button, "column": column}


func _stage_card(stage: Dictionary) -> Control:
	var slug := str(stage.get("slug", ""))
	var chosen := slug == selected and not _has_boss(stage)
	var idle_here := slug == str(_wave().get("stageSlug", ""))
	var shell := _card_shell("Stage_%s" % slug, "card_current_gold" if chosen else "card_apricot", chosen)
	var column := shell.column as VBoxContainer
	var title := QKit.title(str(stage.get("displayName", slug)), 30, UiTokens.Q_ORANGE_DARK if chosen else UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	title.clip_text = true
	column.add_child(title)
	column.add_child(QKit.portrait(_monster_name(stage), 136))
	var name := QKit.title(_monster_name(stage), 32, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name.clip_text = true
	column.add_child(name)
	var chip := QKit.tag("挂机中" if idle_here else "可挂机", "orange" if idle_here else "mint", 30, 14)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(chip)
	(shell.button as Button).pressed.connect(func() -> void: stage_selected.emit(slug))
	return shell.button


## 首领卡：首领立绘 + 「首领」+ 名字 + 状态（已击败 / 可挑战，已击败来自服务器的突破关卡 cleared）。
func _boss_card(stage: Dictionary, power: int) -> Control:
	var slug := str(stage.get("slug", ""))
	var chosen := slug == selected
	var shell := _card_shell("Boss_%s" % slug, "card_current_gold" if chosen else "card_apricot", chosen)
	var column := shell.column as VBoxContainer
	column.add_child(QKit.title("首领", 30, UiTokens.Q_ORANGE_DARK if chosen else UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(QKit.portrait(_boss_name(stage), 136, UiTokens.Q_ORANGE))
	var name := QKit.title(_boss_name(stage), 32, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name.clip_text = true
	column.add_child(name)
	var tag := _tag_text(stage)
	var status := power_status(power, int(stage.get("recommendedPower", 0)))
	var chip := QKit.tag(tag if not tag.is_empty() else "可挑战", "mint" if not tag.is_empty() else ("orange" if str(status.level) != "bad" else "red"), 30, 14)
	chip.name = "Tag"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(chip)
	var badge := QKit.tag("BOSS", "badge_orange", 30, 14)
	badge.name = "BossBadge"
	badge.position = Vector2(CARD_SIZE.x - 96, -18)
	badge.rotation = deg_to_rad(6)
	(shell.button as Button).add_child(badge)
	(shell.button as Button).pressed.connect(func() -> void: stage_selected.emit(slug))
	return shell.button


## 卡片右上角的小标签：真实状态才显示（已击败只来自服务器的突破关卡 cleared），不编造。
func _tag_text(stage: Dictionary) -> String:
	var gate: Variant = (_state.get("breakthrough", {}) as Dictionary).get("requiredStage", null) if typeof(_state.get("breakthrough", null)) == TYPE_DICTIONARY else null
	if typeof(gate) == TYPE_DICTIONARY and str((gate as Dictionary).get("slug", "")) == str(stage.get("slug", "")) and bool((gate as Dictionary).get("cleared", false)):
		return "已击败 ✓"
	return ""


## 下一个还没解锁的关卡：灰色卡片 + 锁 + 解锁条件（不可点）。
func _locked_card(info: Dictionary) -> Control:
	var shell := _card_shell("LockedStageCard", "card_locked", false)
	var button := shell.button as Button
	button.disabled = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := shell.column as VBoxContainer
	var has_boss := not str(info.get("boss", "")).is_empty()
	var title := QKit.title(str(info.get("stage", "")), 30, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	title.clip_text = true
	column.add_child(title)
	var who := str(info.get("boss", "")) if has_boss else str(info.get("monster", ""))
	var portrait := QKit.portrait(who, 136, Color("b9ada2"), true)
	var lock := QKit.lock_icon(64)
	QKit.center_in(lock, lock.custom_minimum_size)
	portrait.add_child(lock)
	column.add_child(portrait)
	var what := ("首领 %s" % who) if has_boss else who
	var name := QKit.title(what, 30, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	name.clip_text = true
	column.add_child(name)
	var unlock := QKit.title("%s解锁" % str(info.get("realm", "更高境界")), 30, UiTokens.Q_RED, HORIZONTAL_ALIGNMENT_CENTER)
	unlock.clip_text = true
	column.add_child(unlock)
	return button


func _find(slug: String) -> Dictionary:
	for stage in _stages:
		if str(stage.get("slug", "")) == slug:
			return stage
	return {}


## 当前境界没有首领可挑战时的说明。挂机地点里列的是普通关卡（只刷怪、没有首领），
## 两者不矛盾：首领关要到更高的境界才解锁。
static func empty_text(realm_name: String, locked_next: Dictionary) -> String:
	var head := "%s还没有首领可以挑战。" % realm_name if not realm_name.is_empty() else "当前境界还没有首领可以挑战。"
	if locked_next.is_empty():
		return head + "上面「挂机地点」里的关卡只刷小怪，会自动刷。"
	var text := head + "突破到「%s」后解锁「%s」的首领「%s」" % [str(locked_next.get("realm", "更高境界")), str(locked_next.get("stage", "")), str(locked_next.get("boss", ""))]
	if int(locked_next.get("power", 0)) > 0:
		text += "（推荐战力 %d）" % int(locked_next.get("power", 0))
	return text + "。现在可以先选「挂机地点」刷怪积累修为。"


## 战力对比：用文字+符号表达，不只靠颜色。
static func power_status(mine: int, recommended: int) -> Dictionary:
	if recommended <= 0:
		return {"text": "无推荐战力", "symbol": "－", "level": "none"}
	if mine >= recommended:
		return {"text": "战力足够", "symbol": "✔", "level": "ok"}
	if float(mine) >= float(recommended) * 0.8:
		return {"text": "略低于推荐", "symbol": "!", "level": "warn"}
	return {"text": "战力差距大", "symbol": "✖", "level": "bad"}


static func _boss_name(stage: Dictionary) -> String:
	var bosses: Array = stage.get("bosses", [])
	return str((bosses[0] as Dictionary).get("name", "")) if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else ""


static func _monster_name(stage: Dictionary) -> String:
	var monsters: Array = stage.get("monsters", [])
	return str((monsters[0] as Dictionary).get("name", "")) if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else "怪物"


## 选中关卡的详情（设计稿 36,1410,1008,462）：怪物、每只修为、属性与推荐战力、我的战力、掉落预览；
## 有首领时加首领属性与首通奖励；没有首领时写明首领在哪个境界解锁（NoBossHint）。
func _detail_card(stage: Dictionary, power: int) -> Control:
	var card := QKit.panel(UiTokens.Q_CREAM, 34, 28, 22)
	card.panel.name = "StageDetailCard"
	var body := card.body as VBoxContainer
	body.add_theme_constant_override("separation", 12)
	var has_boss := _has_boss(stage)
	var monsters: Array = stage.get("monsters", [])
	var monster: Dictionary = monsters[0] if not monsters.is_empty() and typeof(monsters[0]) == TYPE_DICTIONARY else {}
	var head := UiKit.hbox(12)
	body.add_child(head)
	head.add_child(QKit.portrait(_monster_name(stage), 64))
	var title := QKit.title("%s · %s" % [str(stage.get("displayName", "")), _monster_name(stage)], 42, UiTokens.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	head.add_child(title)
	if monster.has("killCultivation"):
		head.add_child(UiKit.label("每只修为 +%d" % int(monster.get("killCultivation", 0)), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var parts: Array[String] = []
	for entry in [["气血", "hp"], ["攻击", "attack"], ["防御", "defense"]]:
		if monster.has(entry[1]):
			parts.append("%s %d" % [entry[0], int(monster[entry[1]])])
	var stats := UiKit.hbox(12)
	body.add_child(stats)
	var stat_line := UiKit.label(" · ".join(parts), UiTokens.FS_MICRO, UiTokens.TEXT)
	stat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(stat_line)
	stats.add_child(UiKit.label("我的战力 %d" % power, UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK, HORIZONTAL_ALIGNMENT_RIGHT))
	var drops := QKit.inset(UiTokens.Q_CARD, 26, 22, 14)
	drops.panel.name = "DropPreview"
	body.add_child(drops.panel)
	var drop_head := UiKit.hbox(8)
	drops.body.add_child(drop_head)
	var label := QKit.title("掉落预览", 32, UiTokens.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_head.add_child(label)
	var slots := UiKit.hbox(18)
	slots.name = "DropSlots"
	drops.body.add_child(slots)
	var drop: Variant = stage.get("monsterDrop", null)
	if typeof(drop) == TYPE_DICTIONARY and (drop as Dictionary).has("chanceBp"):
		_slot_cell(slots, QKit.slot(_gear_icon("weapon"), 1, 104, "", "", Color.WHITE), "小怪装备", "%.1f%%" % (float((drop as Dictionary).get("chanceBp", 0)) / 100.0))
	if has_boss:
		_boss_rows(stage, body, slots, drop_head, power)
	else:
		var hint := UiKit.wrap_label(empty_text(str(_state.get("realmName", "")), _locked_next), UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK)
		hint.name = "NoBossHint"
		body.add_child(hint)
	if slots.get_child_count() == 0:
		slots.add_child(UiKit.label("没有掉落", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	return card.panel


func _slot_cell(row: HBoxContainer, slot: Control, caption: String, corner: String = "", first: bool = false) -> void:
	var cell := UiKit.vbox(2)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cell)
	cell.add_child(slot)
	if not corner.is_empty():
		var tag := QKit.outlined(corner, 30, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_RIGHT)
		tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		tag.offset_top = -40
		tag.offset_right = -6
		slot.add_child(tag)
	if first:
		var badge := QKit.tag("首通", "red", 30, 10)
		badge.position = Vector2(30, -14)
		slot.add_child(badge)
	var name := UiKit.label(caption, UiTokens.FS_MICRO, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name.custom_minimum_size = Vector2(120, 0)
	name.clip_text = true
	cell.add_child(name)


## 「随机装备」格子用的部位图（Q 版装备图标）。
static func _gear_icon(slot_id: String) -> Texture2D:
	var path := "items/gear_" + slot_id
	return ArtLib.q(path) if ArtLib.has_q(path + ".png") else ArtLib.icon(ArtLib.slot_icon_name(slot_id))


## 首领那部分：首领属性、推荐战力、重复掉落（装备 + 额外物品概率）、首通奖励（修为 + 物品，角标「首通」）。
func _boss_rows(stage: Dictionary, body: VBoxContainer, slots: HBoxContainer, drop_head: HBoxContainer, power: int) -> void:
	var bosses: Array = stage.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	var recommended := int(stage.get("recommendedPower", 0))
	var status := power_status(power, recommended)
	var line := UiKit.hbox(10)
	body.add_child(line)
	body.move_child(line, 2)
	var parts: Array[String] = ["首领 %s" % str(boss.get("name", ""))]
	for entry in [["气血", "hp"], ["攻击", "attack"], ["防御", "defense"]]:
		if boss.has(entry[1]):
			parts.append("%s %d" % [entry[0], int(boss[entry[1]])])
	var boss_line := UiKit.label(" · ".join(parts), UiTokens.FS_MICRO, UiTokens.TEXT)
	boss_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_line.clip_text = true
	line.add_child(boss_line)
	if recommended > 0:
		var colour := UiTokens.Q_MINT_DARK if str(status.level) == "ok" else (UiTokens.Q_ORANGE_DARK if str(status.level) == "warn" else UiTokens.Q_RED)
		line.add_child(UiKit.label("推荐战力 %d %s" % [recommended, str(status.symbol)], UiTokens.FS_MICRO, colour, HORIZONTAL_ALIGNMENT_RIGHT))
	var repeat: Variant = boss.get("repeat", null)
	if typeof(repeat) == TYPE_DICTIONARY:
		if bool((repeat as Dictionary).get("gear", false)):
			_slot_cell(slots, QKit.slot(_gear_icon("helmet"), 2, 104, "", "", Color.WHITE), "首领装备")
		for extra in (repeat as Dictionary).get("extras", []):
			if typeof(extra) == TYPE_DICTIONARY:
				var slug := str((extra as Dictionary).get("itemSlug", ""))
				var view := QKit.reward_view(_content, slug)
				var qty := int((extra as Dictionary).get("maxQty", 1))
				_slot_cell(slots, QKit.reward_slot(_content, slug, 104, qty), str(view.name), "%d%%" % int(round(float((extra as Dictionary).get("chanceBp", 0)) / 100.0)))
	for reward in boss.get("firstClear", []):
		if typeof(reward) != TYPE_DICTIONARY:
			continue
		if str((reward as Dictionary).get("kind", "")) == "cultivation":
			var amount := QKit.title("首领首通：修为 +%s" % CultivationFormat.amount(float((reward as Dictionary).get("amount", 0))), 32, UiTokens.Q_ORANGE_DARK, HORIZONTAL_ALIGNMENT_RIGHT)
			amount.name = "FirstClearCultivation"
			drop_head.add_child(amount)
			continue
		var reward_slug := str((reward as Dictionary).get("itemSlug", ""))
		var reward_view := QKit.reward_view(_content, reward_slug)
		_slot_cell(slots, QKit.reward_slot(_content, reward_slug, 104, int((reward as Dictionary).get("quantity", 1))), str(reward_view.name), "", true)
	var cooldown: Variant = _state.get("challengeCooldownSeconds", null)
	if cooldown != null:
		body.add_child(UiKit.label("挑战冷却 %s 秒" % str(cooldown), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	if recommended > 0 and power < recommended:
		body.add_child(UiKit.wrap_label("我的战力低于推荐值，可能打不过。可以先去背包换装备。", UiTokens.FS_MICRO, UiTokens.Q_ORANGE_DARK))


## 底部固定一行（设计稿 y 1890）：「自动挑战」开关（还没有这个功能：展示，点了提示暂未开放）+「挑战」。
func _build_challenge_bar(current: Dictionary) -> void:
	var pill := PanelContainer.new()
	pill.name = "AutoChallenge"
	pill.custom_minimum_size = Vector2(330, 108)
	pill.add_theme_stylebox_override("panel", QKit.cut_box("panel_pill_100", 24, 0) if ArtLib.qui("panel_pill_100") != null else QSkin.custom(UiTokens.Q_CREAM, UiTokens.Q_COCOA, 4, 50, 6, 24, 0))
	var row := UiKit.hbox(12)
	pill.add_child(row)
	row.add_child(QKit.title("自动挑战", 36, UiTokens.TEXT))
	_auto_toggle = QKit.toggle(false)
	_auto_toggle.name = "AutoChallengeToggle"
	_auto_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	LockedFeature.wire(_auto_toggle, "auto_challenge")
	row.add_child(_auto_toggle)
	_challenge_bar.add_child(pill)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_challenge_bar.add_child(spacer)
	if current.is_empty() or not _has_boss(current):
		return
	var bosses: Array = current.get("bosses", [])
	var boss: Dictionary = bosses[0] if not bosses.is_empty() and typeof(bosses[0]) == TYPE_DICTIONARY else {}
	_challenge_button = QKit.button("挑战", "o", 100, 58)
	_challenge_button.name = "StageChallengeButton"
	_challenge_button.custom_minimum_size.x = 340
	_challenge_button.tooltip_text = "挑战首领「%s」" % str(boss.get("name", ""))
	_challenge_button.disabled = busy or boss.is_empty()
	_challenge_button.pressed.connect(func() -> void: challenge_requested.emit(str(current.get("slug", ""))))
	_challenge_bar.add_child(_challenge_button)


## 供测试：固定在底部的挑战按钮（没选中首领关卡时为 null）。
func challenge_button() -> Button:
	return _challenge_button


func auto_toggle() -> Button:
	return _auto_toggle
