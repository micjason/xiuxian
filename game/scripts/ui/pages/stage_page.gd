class_name StagePage
extends VBoxContainer
## 历练页（Q 版设计稿 q_adventure / q_adventure_stages，底栏第二格）：
## 上半是挂机刷怪的场景（章节背景、打坐的主角、正在刷的怪、本波进度圆点、击杀时飘「+修为」）；
## 下面是挂机地点下拉、章节页签、竖排关卡卡（第三批 SPEC_Q §14.5：每关 = 挂机小怪 + 精英 / 章末首领，
## 解锁看服务器 stageAccess，卡上直接有「挑战 / 再战 / 未解锁」按钮）。原来底部的「自动挑战」开关拿掉了
## （自动挑战改成后台按首领规则在结算里打，结果用提示告诉玩家）。数值都来自后台配置和 /me/state。

signal stage_selected(slug: String)
signal challenge_requested(slug: String)
## slug 为空串 = 恢复“自动（当前境界最高关卡）”。
signal idle_stage_requested(slug: String)
signal back_requested

## 页面区左上角在画布上的位置（紧凑顶栏 152 + 刘海 90 + 8，左右边距 24）。
const ORIGIN := Vector2(24, 250)
const SCENE_HEIGHT := 712.0
## 挂机打小怪特效（anim_q/battle_idle，README 第 1 步）：飞剑出手、命中、伤害数字、击杀溶解、灵气、「+N 修为」、掉落飞进背包。
const IdleBattle := preload("res://anim_q/battle_idle/idle_battle.tscn")

var _state: Dictionary = {}
var _content: Dictionary = {}
## StageAccessView.chapters 的结果（章节 → 关卡卡数据）。
var _chapters: Array[Dictionary] = []
## 当前打开的章节页签 slug。
var _tab := ""
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
var _battle_fx: Node2D
var _hero: Control
var _last_kills := -1
var _elapsed := 0.0

var _stage_view: ScrollContainer
var _stages_sig := 0
## 本波圆点两种样式（亮 / 暗）只建一次；原来每帧给每个圆点新建 StyleBox，整页每帧重绘。
var _pip_on: StyleBox
var _pip_off: StyleBox
var _pip_lit := -1
var _stage_box: VBoxContainer
## 选中关卡卡上的挑战按钮（测试用）；全部卡的按钮按 slug。
var _challenge_button: Button
var _challenge_buttons := {}


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
	node.texture = ArtLib.q(path) if not path.is_empty() and ArtLib.has_q(path + ".png") else null
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
	var hero := QHero.new(false, false)  # 动画主角（只要人物，莲台在下面）
	hero.name = "StageHero"
	_at(hero, Rect2(54, 520, 300, 300))
	_hero = hero
	# 原来 (470,600) 的装饰飞剑去掉了：特效里自带会飞的剑（battle_idle/art/sword.png）。
	# 怪物（远处小一只 + 目标一只，都朝左）：贴图按当前怪物的 artKey 在 _render_scene 里查（ArtLib.monster_sprite_for）
	_monster_far = _sprite("", Rect2(412, 450, 166, 166), true)
	_monster_far.modulate = Color(1, 1, 1, 0.9)
	_monster = _sprite("", Rect2(560, 510, 340, 370), true)
	_monster.name = "TargetMonster"
	_monster.visible = false  # 只用来取贴图和翻转；目标怪由特效里的怪物模板画（README 第 2 步）
	# 特效层加在怪物名牌和血条之前 → 名牌、血条永远画在特效上面。全部用设计稿坐标，减掉页面原点对齐。
	_battle_fx = IdleBattle.instantiate() as Node2D
	_battle_fx.name = "IdleBattleFx"
	_battle_fx.position = -ORIGIN
	_scene.add_child(_battle_fx)
	_battle_fx.call("bind_hero", hero)
	# 掉落物是 top_level、用全局坐标飞到底栏；调高层级，飞到底栏时不被底栏（z 30）盖住。
	var drops := _battle_fx.get_node_or_null("Drops") as CanvasItem
	if drops != null:
		drops.z_as_relative = false
		drops.z_index = 50
	var name_chip := QKit.tag("", "cream", 30, 16)
	name_chip.name = "MonsterName"
	_monster_chip = name_chip.get_child(0) as Label
	_at(name_chip, Rect2(596, 432, 150, 52))
	_monster_hp = QKit.bar(1.0, UiTokens.Q_RED, 30, 1, UiTokens.Q_TRACK, "red") as QBar
	_monster_hp.name = "MonsterHp"
	_at(_monster_hp, Rect2(756, 444, 170, 30))


## 第三批：关卡列表按章节分组、能不能打看服务器 stageAccess（StageAccessView 算好每张卡）。
## selected_slug = 选中（高亮、展开奖励）的关卡。
func bind(state: Dictionary, content: Dictionary, selected_slug: String) -> void:
	_state = state
	_content = content
	_chapters = StageAccessView.chapters(content, state)
	selected = selected_slug
	# 页签跟着选中的关卡走（点页签时 select_tab 会把选中换到那一章，两边一致）。
	var own := StageAccessView.chapter_of(_chapters, selected)
	if not own.is_empty():
		_tab = str(own.slug)
	elif _tab.is_empty() or not _has_chapter(_tab):
		_tab = StageAccessView.default_chapter(_chapters, str(_wave().get("stageSlug", "")))
	_elapsed = 0.0
	_render_scene()
	_render_stages_if_changed()


func _has_chapter(slug: String) -> bool:
	for chapter in _chapters:
		if str(chapter.slug) == slug:
			return true
	return false


## 当前打开的章节页签。
func current_tab() -> String:
	return _tab


## 切章节页签（点页签 / 测试用）。选中关卡跟着换到这一章默认的那关。
func select_tab(slug: String) -> void:
	if slug == _tab or not _has_chapter(slug):
		return
	_tab = slug
	var chapter: Dictionary = {}
	for row in _chapters:
		if str(row.slug) == slug:
			chapter = row
	var pick := StageAccessView.default_stage([chapter] as Array[Dictionary])
	if not pick.is_empty():
		selected = pick
		stage_selected.emit(pick)
	_render_stages()


## 心跳每次都会 bind；列表内容没变就不重建（v14：原来每次心跳都整列重建，
## 正在拖的列表会被打断、横排关卡卡跳回开头，还会卡一下）。
func _render_stages_if_changed() -> void:
	var sig := _stages_signature()
	if sig == _stages_sig and _stage_box.get_child_count() > 0:
		return
	_render_stages()


func _stages_signature() -> int:
	var wave := _wave()
	return hash([_chapters, selected, _tab, int(_state.get("power", 0)), str(_state.get("realmName", "")),
		wave.get("stageSlug", null), wave.get("chosenStageSlug", null), wave.get("selectable", []),
		_state.get("challengeCooldownSeconds", null), _state.get("bossDaily", null),
		busy, _dropdown_open])


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
	var mon_row: Dictionary = wave.get("monster", {}) if typeof(wave.get("monster", null)) == TYPE_DICTIONARY else {}
	var sprite := ArtLib.monster_sprite_for({"artKey": mon_row.get("artKey", null), "name": monster_name})
	var tex: Texture2D = ArtLib.q("sprites/" + sprite) if not sprite.is_empty() else (ArtLib.icon(ArtLib.boss_icon_name(monster_name)) if not monster_name.is_empty() else null)
	_monster.texture = tex
	_monster_far.texture = tex
	var flip := ArtLib.monster_needs_flip(sprite) if not sprite.is_empty() else true
	_monster.flip_h = flip
	_monster_far.flip_h = flip
	_monster.visible = false
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
	_pip_lit = -1
	# 当前怪物交给特效（贴图或气血变了才重新刷怪，重复调用没关系）。气血 = 配置值 wave.monster.hp，伤害数字加起来正好等于它。
	# 第 4 个参数 = 每只击杀修为：灵气飞到主角时飘「+N 修为」（原来页面自己的 _float_gain 已删，不会飘两次）。
	var mon: Dictionary = wave.get("monster", {}) if typeof(wave.get("monster", null)) == TYPE_DICTIONARY else {}
	_battle_fx.call("set_monster", _monster.texture, _monster.flip_h, int(mon.get("hp", 0)), float(shown.get("kill_cultivation", 0)))
	_battle_fx.visible = tex != null and bool(shown.available)
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
	if kills != _pip_lit:
		_pip_lit = kills
		if _pip_on == null:
			_pip_on = QSkin.custom(UiTokens.Q_MINT, UiTokens.Q_COCOA, 4, 999, 0, 0, 0)
			_pip_off = QSkin.custom(Color("f1e2c6"), UiTokens.Q_COCOA, 4, 999, 0, 0, 0)
		for i in _pips.size():
			(_pips[i] as Panel).add_theme_stylebox_override("panel", _pip_on if i < kills else _pip_off)
	var per := maxi(1, int(_wave().get("killsPerWave", shown.get("wave_size", 3))))
	var progress := float(shown.get("ratio", 0.0)) * float(per)
	var hp_ratio := 1.0 - (progress - floorf(progress))
	_monster_hp.set_ratio(hp_ratio)
	_battle_fx.call("sync", hp_ratio, kills)  # 和血条同一个值、本波击杀数（README 第 4 步）
	# 怪物溶解到下一只刷出之前先藏血条（名牌留着）
	_monster_hp.visible = bool(_battle_fx.call("monster_showing")) and _monster_chip.get_parent().visible
	_last_kills = kills


## 这次结算真的进了背包的掉落（图标），下一只怪死的时候从怪身上弹出、飞进背包（README 第 5 步）。只传真实掉落。
func queue_drops(icons: Array[Texture2D]) -> void:
	if not icons.is_empty():
		_battle_fx.call("queue_drops", icons)


## 掉落飞去的画布坐标（底栏背包页签）。
func set_bag_target(point: Vector2) -> void:
	_battle_fx.set("bag_target_global", point)


func battle_fx() -> Node2D:
	return _battle_fx

func _render_stages() -> void:
	_stages_sig = _stages_signature()
	var keep_scroll := _stage_view.scroll_vertical
	UiKit.clear(_stage_box)
	_challenge_button = null
	_challenge_buttons.clear()
	_stage_box.add_child(_idle_card())
	if _chapters.is_empty():
		var empty := QKit.panel()
		empty.panel.name = "NoStages"
		empty.body.add_child(UiKit.wrap_label("还没有开放的关卡。", UiTokens.FS_BODY, UiTokens.TEXT_MUTED))
		_stage_box.add_child(empty.panel)
		return
	_stage_box.add_child(_chapter_tabs())
	var list := UiKit.vbox(16)
	list.name = "StageCards"
	_stage_box.add_child(list)
	var power := int(_state.get("power", 0))
	for chapter in _chapters:
		if str(chapter.slug) != _tab:
			continue
		for card_data in chapter.cards:
			list.add_child(_stage_card(card_data, power))
	_restore_scroll.call_deferred(keep_scroll)


func _restore_scroll(value: int) -> void:
	await get_tree().process_frame
	if is_instance_valid(_stage_view):
		_stage_view.scroll_vertical = value

## 挂机地点条（设计稿 36,962,1008,100）：境界 + 「挂机地点」下拉（服务器 wave.selectable / chosenStageSlug，null = 自动）。
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
	row.add_child(QKit.title(str(_state.get("realmName", "")), 40, UiTokens.TEXT))
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

## 章节页签（SPEC_Q §14.5）：当前章橙色、已解锁奶油色、未解锁灰色带锁和条件（不可点）。
func _chapter_tabs() -> Control:
	var row := UiKit.hbox(12)
	row.name = "ChapterTabs"
	for chapter in _chapters:
		var slug := str(chapter.slug)
		var on := slug == _tab
		var open := bool(chapter.unlocked)
		var tab := Button.new()
		tab.name = "ChapterTab_%s" % (slug if not slug.is_empty() else "other")
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size = Vector2(0, 96)
		var fill := UiTokens.Q_ORANGE if on else (UiTokens.Q_CREAM if open else Color("d9d0c6"))
		var box := QSkin.custom(fill, UiTokens.Q_COCOA, 4, 30, 5, 12, 4)
		for state in ["normal", "hover", "pressed", "disabled"]:
			tab.add_theme_stylebox_override(state, box)
		tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var column := UiKit.vbox(0)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		tab.add_child(column)
		var text := str(chapter.name) if open else "🔒 " + str(chapter.name)
		var label := QKit.outlined(text, 38, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_CENTER) if on else QKit.title(text, 38, UiTokens.TEXT if open else UiTokens.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_CENTER)
		label.clip_text = true
		column.add_child(label)
		if not open and not str(chapter.lock_text).is_empty():
			var hint := UiKit.label(str(chapter.lock_text), 24, UiTokens.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_CENTER)
			hint.clip_text = true
			column.add_child(hint)
		tab.disabled = not open
		tab.pressed.connect(func() -> void: select_tab(slug))
		row.add_child(tab)
	return row


## 竖排关卡卡（SPEC_Q §14.5）：怪物头像（挂机）▶ 首领头像（精英蓝环 / 章末首领橙环）+ 关卡名、首领、推荐战力、
## 解锁条件（✓/✗）、今日奖励次数、按钮（挑战 / 再战 / 未解锁）。选中的卡加金框，展开首通 / 重复奖励。
func _stage_card(card_data: Dictionary, power: int) -> Control:
	var slug := str(card_data.slug)
	var chosen := slug == selected
	var chief := str(card_data.tier) == "chief"
	var playable := bool(card_data.playable)
	var idle_here := slug == str(_wave().get("stageSlug", ""))
	var action := StageAccessView.button(card_data, _state)
	var cut := "card_locked" if not playable else ("card_current_gold" if chosen else ("card_chief" if chief else "card_apricot"))
	var shell := Button.new()
	shell.name = "Stage_%s" % slug
	shell.focus_mode = Control.FOCUS_NONE
	var box: StyleBox = QKit.cut_box(cut, 22, 18) if ArtLib.qui(cut) != null else QSkin.custom(Color("ffe9b8") if chosen else UiTokens.Q_CARD, UiTokens.Q_COCOA, 4, 28, 6, 22, 18)
	for state in ["normal", "hover", "pressed", "disabled"]:
		shell.add_theme_stylebox_override(state, box)
	shell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	shell.pressed.connect(func() -> void: stage_selected.emit(slug))
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	shell.add_child(margin)
	var outer := UiKit.vbox(10)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(outer)
	var row := UiKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(row)
	# 头像：小怪（挂机）▶ 首领
	var mon := QKit.portrait(str(card_data.monster_name), 96, UiTokens.Q_MINT, not playable, str(card_data.monster_art))
	mon.name = "MonsterPortrait"
	if idle_here:
		var tag := QKit.tag("挂机", "orange", 24, 10)
		tag.position = Vector2(4, 64)
		mon.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		mon.add_child(tag)
	row.add_child(mon)
	row.add_child(QKit.title("▶", 30, UiTokens.TEXT_MUTED))
	var ring := Color("f08a24") if chief else Color("4c8fd6")
	var boss_size := 156 if chief else 128
	var boss := QKit.portrait(str(card_data.boss_name), boss_size, ring, not playable, str(card_data.boss_art))
	boss.name = "BossPortrait"
	if not playable:
		var lock := QKit.lock_icon(56)
		QKit.center_in(lock, lock.custom_minimum_size)
		boss.add_child(lock)
	row.add_child(boss)
	# 文字列
	var info := UiKit.vbox(4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var title := QKit.title(str(card_data.name), 38, UiTokens.TEXT if playable else UiTokens.TEXT_MUTED)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var tier_tag := QKit.tag("章末首领" if chief else "精英", "orange" if chief else "blue", 24, 12)
	tier_tag.name = "TierTag"
	head.add_child(tier_tag)
	var boss_name := QKit.title(str(card_data.boss_name), 32, UiTokens.Q_RED if chief else UiTokens.TEXT)
	boss_name.clip_text = true
	info.add_child(boss_name)
	var recommended := int(card_data.recommended)
	if recommended > 0:
		var status := power_status(power, recommended)
		var colour := UiTokens.Q_MINT_DARK if str(status.level) == "ok" else (UiTokens.Q_ORANGE_DARK if str(status.level) == "warn" else UiTokens.Q_RED)
		var line := UiKit.label("推荐战力 %d %s" % [recommended, str(status.symbol)], 28, colour if playable and not bool(card_data.cleared) else UiTokens.TEXT_MUTED)
		line.name = "PowerLine"
		info.add_child(line)
	if not playable:
		for need in card_data.needs_lines:
			var need_row := UiKit.hbox(6)
			need_row.name = "Need"
			need_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			need_row.add_child(QKit.check(bool(need.ok), 32))
			need_row.add_child(UiKit.label(str(need.text), 26, UiTokens.Q_MINT_DARK if bool(need.ok) else UiTokens.Q_RED))
			info.add_child(need_row)
	# 右列：状态 + 次数 + 按钮
	var side := UiKit.vbox(6)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	if bool(card_data.cleared):
		var done := QKit.tag("已击败 ✓", "mint", 24, 10)
		done.name = "ClearedChip"
		done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		side.add_child(done)
	var day := StageAccessView.daily(card_data, _state)
	if not day.is_empty() and (bool(card_data.cleared) or chief):
		var chip := QKit.tag("今日 %d/%d" % [int(day.left), int(day.limit)], "cream" if int(day.left) > 0 else "red", 24, 10)
		chip.name = "DailyChip"
		chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		side.add_child(chip)
	var button := QKit.button(str(action.text), str(action.kind), 100, 38)
	button.name = "Challenge_%s" % slug
	button.custom_minimum_size.x = 200
	button.disabled = busy or not bool(action.enabled)
	button.tooltip_text = "挑战%s「%s」" % ["章末首领" if chief else "精英", str(card_data.boss_name)]
	button.pressed.connect(func() -> void: challenge_requested.emit(slug))
	side.add_child(button)
	_challenge_buttons[slug] = button
	if chosen:
		_challenge_button = button
	if not str(action.sub).is_empty():
		var sub := UiKit.label(str(action.sub), 24, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		sub.name = "ButtonSub"
		side.add_child(sub)
	if chosen and playable:
		outer.add_child(_reward_row(card_data))
	var height := 230.0 if not playable else 250.0
	if chief:
		height += 30.0
	if chosen and playable:
		height += 170.0
	shell.custom_minimum_size = Vector2(0, height)
	return shell


## 选中卡展开的奖励行：没首通 = 首通奖励（修为 + 物品，角标「首通」）；打过 = 重复掉落（首领装备 + 额外物品概率）。
func _reward_row(card_data: Dictionary) -> Control:
	var well := QKit.inset(UiTokens.Q_CARD, 22, 16, 8)
	well.panel.name = "RewardRow"
	well.panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slots := UiKit.hbox(14)
	slots.name = "DropSlots"
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.body.add_child(slots)
	var first := not bool(card_data.cleared)
	slots.add_child(QKit.title("首通" if first else "掉落", 30, UiTokens.Q_ORANGE_DARK if first else UiTokens.TEXT_MUTED))
	if first:
		for reward in card_data.first_clear:
			if typeof(reward) != TYPE_DICTIONARY:
				continue
			if str((reward as Dictionary).get("kind", "")) == "cultivation":
				var amount := QKit.title("修为 +%s" % CultivationFormat.amount(float((reward as Dictionary).get("amount", 0))), 30, UiTokens.Q_ORANGE_DARK)
				amount.name = "FirstClearCultivation"
				slots.add_child(amount)
				continue
			var slug := str((reward as Dictionary).get("itemSlug", ""))
			_slot_cell(slots, QKit.reward_slot(_content, slug, 88, int((reward as Dictionary).get("quantity", 1))), str(QKit.reward_view(_content, slug).name), "", true)
	else:
		var repeat: Variant = card_data.repeat
		var rules: Dictionary = card_data.rules
		if not bool(rules.get("repeatRewards", true)):
			slots.add_child(UiKit.label("再战没有奖励", 28, UiTokens.TEXT_MUTED))
		elif typeof(repeat) == TYPE_DICTIONARY:
			if bool((repeat as Dictionary).get("gear", false)):
				var pct: Dictionary = rules.get("gearQualityPct", {}) if typeof(rules.get("gearQualityPct", null)) == TYPE_DICTIONARY else {}
				var orange := int(pct.get("orange", 0))
				_slot_cell(slots, QKit.slot(_gear_icon("helmet"), 4 if orange > 0 else 2, 88, "", "", Color.WHITE), "首领装备", ("橙 %d%%" % orange) if orange > 0 else "")
			for extra in (repeat as Dictionary).get("extras", []):
				if typeof(extra) == TYPE_DICTIONARY:
					var item := str((extra as Dictionary).get("itemSlug", ""))
					_slot_cell(slots, QKit.reward_slot(_content, item, 88, int((extra as Dictionary).get("maxQty", 1))), str(QKit.reward_view(_content, item).name), "%d%%" % int(round(float((extra as Dictionary).get("chanceBp", 0)) / 100.0)))
	if slots.get_child_count() <= 1:
		slots.add_child(UiKit.label("没有奖励", 28, UiTokens.TEXT_MUTED))
	return well.panel


## 战力对比：用文字+符号表达，不只靠颜色。
static func power_status(mine: int, recommended: int) -> Dictionary:
	if recommended <= 0:
		return {"text": "无推荐战力", "symbol": "－", "level": "none"}
	if mine >= recommended:
		return {"text": "战力足够", "symbol": "✔", "level": "ok"}
	if float(mine) >= float(recommended) * 0.8:
		return {"text": "略低于推荐", "symbol": "!", "level": "warn"}
	return {"text": "战力差距大", "symbol": "✖", "level": "bad"}


func _slot_cell(row: HBoxContainer, slot: Control, caption: String, corner: String = "", first: bool = false) -> void:
	var cell := UiKit.vbox(2)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cell)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(slot)
	if not corner.is_empty():
		var tag := QKit.outlined(corner, 26, UiTokens.Q_WHITE, UiTokens.Q_COCOA, 8, HORIZONTAL_ALIGNMENT_RIGHT)
		tag.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		tag.offset_top = -36
		tag.offset_right = -4
		slot.add_child(tag)
	if first:
		var badge := QKit.tag("首通", "red", 22, 8)
		badge.position = Vector2(20, -12)
		slot.add_child(badge)
	var name := UiKit.label(caption, 24, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	name.custom_minimum_size = Vector2(100, 0)
	name.clip_text = true
	cell.add_child(name)


## 「随机装备」格子用的部位图（Q 版装备图标）。
static func _gear_icon(slot_id: String) -> Texture2D:
	var path := "items/gear_" + slot_id
	return ArtLib.q(path) if ArtLib.has_q(path + ".png") else ArtLib.icon(ArtLib.slot_icon_name(slot_id))


## 供测试：选中关卡卡上的挑战按钮（没有选中关卡时为 null）。
func challenge_button() -> Button:
	return _challenge_button


## 供测试：某一关卡卡上的按钮。
func challenge_button_for(slug: String) -> Button:
	return _challenge_buttons.get(slug, null)
