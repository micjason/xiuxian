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
## 第五批（SPEC_Q §17.5）：点「行囊已满」提示条 / 「去分解」→ 直接打开分解弹窗（外壳管）。
signal salvage_requested

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

var _preview: Button
var _preview_art: TextureRect
var _preview_plate: TextureRect
var _preview_power: Label
var _preview_slug := ""

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
## 行囊已满提示条（§17.5）。
var _bag_hint: Button
var _bag_pulse: TextureRect
var _bag_go: Button
var _bag_tween: Tween
var _bag_full := false
## 远处小怪的原始位置（提示条出现时往下挪 70，避开 y366–494）。
const MONSTER_FAR_Y := 450.0


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
	_build_preview()
	_build_bag_hint()


## 「行囊已满」提示条（稿 q_bag_full_hint，SPEC_Q §17.5）：hint_bagfull_bg（26,366）580×128；
## 背包图标 96 + badge_full 52 +「行囊已满」/「装备不再掉落」+ 橙色「去分解」200×88（下垫 fx_btn_pulse 脉冲）。整条都能点。
func _build_bag_hint() -> void:
	_bag_hint = Button.new()
	_bag_hint.name = "BagFullHint"
	_bag_hint.focus_mode = Control.FOCUS_NONE
	_bag_hint.visible = false
	var bg: StyleBox = ArtLib.q_nine("hint_bagfull_bg") if ArtLib.qui("hint_bagfull_bg") != null else QSkin.custom(Color("ffe6dc"), Color("f3a08a"), 4, 40, 8, 0, 0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_bag_hint.add_theme_stylebox_override(state, bg)
	_bag_hint.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_bag_hint.pressed.connect(func() -> void: salvage_requested.emit())
	_at(_bag_hint, Rect2(26, 366, 580, 128))
	var pouch := TextureRect.new()
	pouch.texture = ArtLib.icon("tab_bag")
	pouch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pouch.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pouch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pouch.position = Vector2(20, 12)
	pouch.size = Vector2(96, 96)
	_bag_hint.add_child(pouch)
	var badge := TextureRect.new()
	badge.name = "FullBadge"
	badge.texture = ArtLib.qui("badge_full")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.position = Vector2(84, 4)
	badge.size = Vector2(52, 52)
	_bag_hint.add_child(badge)
	var title := QKit.title("行囊已满", 40, Color("d93a3f"))
	title.position = Vector2(132, 14)
	title.size = Vector2(240, 56)
	_bag_hint.add_child(title)
	var sub := UiKit.label("装备不再掉落", 28, Color("9a8478"))
	sub.position = Vector2(132, 70)
	sub.size = Vector2(240, 40)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_hint.add_child(sub)
	_bag_pulse = TextureRect.new()
	_bag_pulse.name = "Pulse"
	_bag_pulse.texture = ArtLib.qui("fx_btn_pulse")
	_bag_pulse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bag_pulse.stretch_mode = TextureRect.STRETCH_SCALE
	_bag_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_pulse.position = Vector2(326, -11)
	_bag_pulse.size = Vector2(260, 150)
	_bag_pulse.pivot_offset = Vector2(130, 75)
	_bag_hint.add_child(_bag_pulse)
	_bag_go = QKit.button("去分解", "o", 88, 40, 30)
	_bag_go.name = "GoSalvage"
	_bag_go.position = Vector2(356, 16)
	_bag_go.size = Vector2(200, 88)
	_bag_go.pivot_offset = Vector2(100, 44)
	_bag_go.pressed.connect(func() -> void: salvage_requested.emit())
	_bag_hint.add_child(_bag_go)


## 背包满（未穿戴的格数 ≥ 容量，和服务器 bagUsed 一样算；有 state.bagUsed 就用它）。
static func bag_is_full(state: Dictionary, content: Dictionary) -> bool:
	var cap := int(state.get("bagCapacity", 0))
	if cap <= 0:
		var globals: Variant = content.get("globals", {})
		cap = int((globals as Dictionary).get("bagCapacity", 0)) if typeof(globals) == TYPE_DICTIONARY else 0
	if cap <= 0:
		return false
	var used := -1
	if state.has("bagUsed") and state.get("bagUsed") != null:
		used = int(state.get("bagUsed"))
	if used < 0:
		used = 0
		for row in state.get("items", []):
			if typeof(row) == TYPE_DICTIONARY and BagModel.plain((row as Dictionary).get("equippedSlot", null)).is_empty():
				used += 1
	return used >= cap


func bag_hint() -> Button:
	return _bag_hint


func _render_bag_hint() -> void:
	var full := bag_is_full(_state, _content)
	_monster_far.position.y = MONSTER_FAR_Y + (70.0 if full else 0.0) - ORIGIN.y
	if full == _bag_full and _bag_hint.visible == full:
		return
	_bag_full = full
	if _bag_tween != null:
		_bag_tween.kill()
		_bag_tween = null
	var home_x := 26.0 - ORIGIN.x
	if not full:
		if _bag_hint.visible and is_inside_tree():
			var out := create_tween()
			out.tween_property(_bag_hint, "position:x", -600.0, 0.2)
			out.tween_callback(func() -> void: _bag_hint.visible = false)
		else:
			_bag_hint.visible = false
		return
	_bag_hint.visible = true
	_bag_hint.position.x = home_x
	if not is_inside_tree():
		return
	_bag_hint.position.x = -600.0
	create_tween().tween_property(_bag_hint, "position:x", home_x, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# 脉冲：fx_btn_pulse scale 0.92↔1.08、alpha 0.5↔1，按钮 1.0↔1.04，周期 1.2s。
	_bag_tween = create_tween().set_loops()
	_bag_tween.set_parallel(true)
	_bag_tween.tween_property(_bag_pulse, "scale", Vector2(1.08, 1.08), 0.6).from(Vector2(0.92, 0.92))
	_bag_tween.tween_property(_bag_pulse, "modulate:a", 1.0, 0.6).from(0.5)
	_bag_tween.tween_property(_bag_go, "scale", Vector2(1.04, 1.04), 0.6).from(Vector2.ONE)
	_bag_tween.chain().tween_property(_bag_pulse, "scale", Vector2(0.92, 0.92), 0.6)
	_bag_tween.parallel().tween_property(_bag_pulse, "modulate:a", 0.5, 0.6)
	_bag_tween.parallel().tween_property(_bag_go, "scale", Vector2.ONE, 0.6)


## 精英预览小卡（SPEC_Q §14.5：884,630,170,230）：挂机所在关的精英 / 章末首领立绘 + 名牌 + 「战力 N」，点了 = 挑战。
## 只在这关首领现在能打、而且打了有东西拿的时候显示（没首通，或还有今日奖励次数）。
func _build_preview() -> void:
	_preview = Button.new()
	_preview.name = "ElitePreview"
	_preview.focus_mode = Control.FOCUS_NONE
	var box := QSkin.custom(Color(1.0, 0.973, 0.925, 0.94), UiTokens.Q_COCOA, 4, 28, 6, 0, 0)
	for state in ["normal", "hover", "pressed", "disabled"]:
		_preview.add_theme_stylebox_override(state, box)
	_preview.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_at(_preview, Rect2(884, 630, 170, 230))
	_preview_art = TextureRect.new()
	_preview_art.name = "PreviewArt"
	_preview_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_art.position = Vector2(19, 8)
	_preview_art.size = Vector2(132, 150)
	_preview.add_child(_preview_art)
	_preview_plate = TextureRect.new()
	_preview_plate.name = "PreviewPlate"
	_preview_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_plate.position = Vector2(19, 146)
	_preview_plate.size = Vector2(132, 42)
	_preview.add_child(_preview_plate)
	_preview_power = QKit.title("", 24, UiTokens.Q_RED, HORIZONTAL_ALIGNMENT_CENTER)
	_preview_power.name = "PreviewPower"
	_preview_power.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_power.position = Vector2(0, 190)
	_preview_power.size = Vector2(170, 34)
	_preview.add_child(_preview_power)
	_preview.pressed.connect(func() -> void:
		if not _preview_slug.is_empty() and not busy:
			challenge_requested.emit(_preview_slug))
	_preview.visible = false


func _render_preview() -> void:
	var idle := str(_wave().get("stageSlug", ""))
	var card := {}
	var fx := "default"
	for chapter in _chapters:
		for row in chapter.cards:
			if str(row.slug) == idle:
				card = row
				fx = str(chapter.boss_fx)
	_preview_slug = ""
	var action := StageAccessView.button(card, _state) if not card.is_empty() else {}
	var shown := not card.is_empty() and bool(action.get("enabled", false)) and str(action.get("kind", "")) == "o"
	_preview.visible = shown
	if not shown:
		return
	_preview_slug = str(card.slug)
	# 第四批：统一首领样式（SPEC_Q §17.10）：boss_* 立绘 + plate_chief；不再区分精英 / 章末首领
	_preview_art.texture = preview_texture(str(card.boss_art), true, fx, str(card.boss_name))
	_preview_plate.texture = ArtLib.qui("plate_chief")
	_preview_power.text = "战力 %d" % int(card.recommended) if int(card.recommended) > 0 else ""
	_preview.tooltip_text = "挑战首领「%s」" % str(card.boss_name)


## 首领立绘（预览小卡、关卡卡头像）：统一首领立绘 boss_<怪>（第 3 章已是赤炎描边），没有再用普通立绘。
## 旧的 elite_* / chief_* 预渲染图已废弃（SPEC_Q §17.10），不再引用；chief / fx 参数只为兼容旧调用。
static func preview_texture(art_key: String, _chief: bool = true, _fx: String = "default", boss_name: String = "") -> Texture2D:
	var sprite := BattlePage.boss_sprite_of({"artKey": art_key if not art_key.is_empty() else null, "name": boss_name})
	return ArtLib.q("sprites/" + sprite) if not sprite.is_empty() else null


## 关卡 slug → 所在章节的首领特效（default / chiyan），关卡卡头像的光圈用。
var _chapter_fx := {}

const AURA_CHIEF := "res://anim_q/battle_idle/art/boss_aura_chief.png"
const AURA_CHIEF_CHIYAN := "res://anim_q/battle_idle/art/boss_aura_chief_chiyan.png"


## 统一首领头像（SPEC_Q §17.10）：身后 boss_aura_chief（赤炎章 _chiyan），圆底 #FFF4EE→#FFD3C4 + boss_* 立绘，
## 外圈 ring_chief_204，右上 badge_chief（直径 × 0.42），下沿压 plate_chief（烘焙「首领」）。locked = 去饱和 + 锁。
static func boss_portrait(art_key: String, boss_name: String, diameter: int, locked: bool, fx: String = "default") -> Control:
	var root := Control.new()
	root.name = "BossPortrait"
	var d := float(diameter)
	root.custom_minimum_size = Vector2(d + 20.0, d + 24.0)
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aura_path := AURA_CHIEF_CHIYAN if fx == "chiyan" else AURA_CHIEF
	if not locked and ResourceLoader.exists(aura_path):
		var aura := TextureRect.new()
		aura.name = "Aura"
		aura.texture = load(aura_path) as Texture2D
		aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		aura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		aura.position = Vector2(-10.0, d * 0.55)
		aura.size = Vector2(d + 40.0, d * 0.5)
		root.add_child(aura)
	var disc := Panel.new()
	disc.name = "Disc"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	disc.position = Vector2(10, 6)
	disc.size = Vector2(d, d)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("ffe4da") if not locked else Color("dcd4cb")
	fill.set_corner_radius_all(diameter)
	disc.add_theme_stylebox_override("panel", fill)
	var art := TextureRect.new()
	art.name = "BossArt"
	art.texture = preview_texture(art_key, true, fx, boss_name)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.position = Vector2(d * 0.06, d * 0.04)
	art.size = Vector2(d * 0.88, d * 0.9)
	if locked:
		art.modulate = Color(0.35, 0.33, 0.32, 0.7)
	disc.add_child(art)
	root.add_child(disc)
	var ring := QKit.cut_rect("ring_chief_204", Vector2(d + 12.0, d + 12.0))
	ring.position = Vector2(4, 0)
	ring.size = Vector2(d + 12.0, d + 12.0)
	if locked:
		ring.modulate = Color(0.7, 0.7, 0.7, 1)
	root.add_child(ring)
	var badge_w := d * 0.42
	var badge := QKit.cut_rect("badge_chief", Vector2(badge_w, badge_w * 0.875))
	badge.name = "BadgeChief"
	badge.position = Vector2(d - badge_w * 0.45, -badge_w * 0.25)
	badge.size = Vector2(badge_w, badge_w * 0.875)
	root.add_child(badge)
	var plate_w := d * 0.8
	var plate := QKit.cut_rect("plate_chief", Vector2(plate_w, plate_w * 0.307))
	plate.name = "BossPlate"
	plate.position = Vector2(10.0 + (d - plate_w) / 2.0, d - plate_w * 0.12)
	plate.size = Vector2(plate_w, plate_w * 0.307)
	if locked:
		plate.modulate = Color(0.75, 0.75, 0.75, 1)
	root.add_child(plate)
	if locked:
		var lock := QKit.lock_icon(56)
		lock.position = Vector2(10.0 + d / 2.0 - 28.0, d / 2.0 - 28.0)
		root.add_child(lock)
	return root


## 供测试：预览小卡（不显示时 visible = false）和它对应的关卡。
func preview_card() -> Button:
	return _preview


func preview_slug() -> String:
	return _preview_slug


## 第三批：关卡列表按章节分组、能不能打看服务器 stageAccess（StageAccessView 算好每张卡）。
## selected_slug = 选中（高亮、展开奖励）的关卡。
func bind(state: Dictionary, content: Dictionary, selected_slug: String) -> void:
	_state = state
	_content = content
	_chapters = StageAccessView.chapters(content, state)
	_chapter_fx = {}
	for chapter in _chapters:
		for row in chapter.cards:
			_chapter_fx[str(row.slug)] = str(chapter.boss_fx)
	selected = selected_slug
	# 页签跟着选中的关卡走（点页签时 select_tab 会把选中换到那一章，两边一致）。
	var own := StageAccessView.chapter_of(_chapters, selected)
	if not own.is_empty():
		_tab = str(own.slug)
	elif _tab.is_empty() or not _has_chapter(_tab):
		_tab = StageAccessView.default_chapter(_chapters, str(_wave().get("stageSlug", "")))
	_elapsed = 0.0
	_render_scene()
	_render_bag_hint()
	_render_preview()
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
		StageAccessView.daily_total(_state), busy, _dropdown_open])


func set_busy(value: bool) -> void:
	busy = value
	_preview.disabled = value
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
	var total_bar := _daily_total_bar()
	if total_bar != null:
		_stage_box.add_child(total_bar)
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
		tab.clip_contents = true
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
			var hint := UiKit.label(str(chapter.lock_text).replace("击败章末首领", "需击败").replace("击败首领", "需击败").replace("击败精英", "需击败").replace("「", "").replace("」", ""), 24, UiTokens.TEXT_DISABLED, HORIZONTAL_ALIGNMENT_CENTER)
			hint.clip_text = true
			column.add_child(hint)
		tab.disabled = not open
		tab.pressed.connect(func() -> void: select_tab(slug))
		row.add_child(tab)
	return row


## 第四批：章节页签下面一条「今日首领挑战 剩余/总数」（全局，所有首领共用；首次挑战不耗）。
## 奶油底条 + 沙漏 + 红胶囊（用完灰）+ 说明；服务器没给 bossDailyTotal 就不显示。
func _daily_total_bar() -> Control:
	var info := StageAccessView.daily_total_text(_state)
	if info.is_empty():
		return null
	var bar := QKit.panel(UiTokens.Q_CREAM, 30, 22, 8)
	bar.panel.name = "DailyTotalBar"
	var row := UiKit.hbox(12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.body.add_child(row)
	row.add_child(QKit.cut_rect("icon_hourglass", Vector2(40, 44)))
	var spent := bool(info.spent)
	var chip := QKit.tag(str(info.chip), "grey" if spent else "red", 26, 16)
	chip.name = "DailyTotalChip"
	row.add_child(chip)
	var hint := UiKit.label(str(info.hint), 24, UiTokens.Q_RED if spent else UiTokens.TEXT_MUTED)
	hint.name = "DailyTotalHint"
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(hint)
	return bar.panel


## 竖排关卡卡（第四批统一首领样式，SPEC_Q §17.10，替换 §14.5 的精英 / 章末两套）：小怪头像（挂机）▶ 首领头像
## （boss_* + ring_chief_204 + badge_chief + plate_chief + 光圈）+ 关卡名、首领名（白字红描边）、推荐战力、
## 解锁条件（✓/✗）、按钮（挑战 / 再战 / 未解锁）。可挑战 / 选中的卡金底，未解锁灰底；选中的卡展开首通 / 重复奖励。
func _stage_card(card_data: Dictionary, power: int) -> Control:
	var slug := str(card_data.slug)
	var chosen := slug == selected
	var playable := bool(card_data.playable)
	var current := playable and not bool(card_data.cleared)
	var idle_here := slug == str(_wave().get("stageSlug", ""))
	var action := StageAccessView.button(card_data, _state)
	var cut := "card_locked" if not playable else ("card_current_gold" if chosen or current else "card_apricot")
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
	row.add_child(QKit.title("▶", 30, UiTokens.Q_ORANGE_DARK))
	var boss := boss_portrait(str(card_data.boss_art), str(card_data.boss_name), 178 if current else 150, not playable, str(_chapter_fx.get(slug, "default")))
	if bool(card_data.cleared):
		var ok := QKit.check(true, 44)
		ok.name = "ClearedCheck"
		ok.position = Vector2(0, 0)
		boss.add_child(ok)
	row.add_child(boss)
	# 文字列
	var info := UiKit.vbox(4)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(head)
	var title_colour := UiTokens.Q_ORANGE_DARK if current else (Color("4a3a33") if playable else UiTokens.TEXT_MUTED)
	var title := QKit.title(str(card_data.name), 40, title_colour)
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if idle_here and playable:
		var idle_chip := QKit.tag("挂机中 ···", "mint", 22, 10)
		idle_chip.name = "IdleChip"
		head.add_child(idle_chip)
	var name_row := UiKit.hbox(8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_row)
	var boss_name := QKit.outlined(str(card_data.boss_name), 34, UiTokens.Q_WHITE if playable else Color("efe4d6"), Color("c02e2a") if playable else Color("9a8b7e"), 7)
	boss_name.name = "BossName"
	boss_name.clip_text = true
	boss_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(boss_name)
	# 第四批：次数是全局的，卡片上不再显示「今日 n/总」（只在列表顶上 DailyTotalBar 显示一次）
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
	var button := QKit.button(str(action.text), str(action.kind), 100, 38)
	button.name = "Challenge_%s" % slug
	button.custom_minimum_size.x = 200
	button.disabled = busy or not bool(action.enabled)
	button.tooltip_text = "挑战首领「%s」" % str(card_data.boss_name)
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
		info.add_child(_reward_row(card_data))
	var height := 250.0 if not playable else 240.0
	if current:
		height += 30.0
	if chosen and playable:
		height += 70.0
	shell.custom_minimum_size = Vector2(0, height)
	return shell


## 选中卡展开的奖励行（设计稿 q_adventure_stages：文字列里一行「首通奖励」+ 小格子，数量写在格子角上，不写名字，名字在悬停提示里）。
## 没首通 = 首通奖励（修为 / 灵石 / 物品 / 随机装备）；打过 = 重复掉落（首领装备 + 额外物品概率）。
func _reward_row(card_data: Dictionary) -> Control:
	var row := UiKit.hbox(8)
	row.name = "RewardRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var first := not bool(card_data.cleared)
	var label := UiKit.label("首通奖励" if first else "掉落", 26, UiTokens.Q_ORANGE_DARK if first else UiTokens.TEXT_MUTED)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var slots := UiKit.hbox(8)
	slots.name = "DropSlots"
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slots)
	if first:
		for reward in card_data.first_clear:
			if typeof(reward) != TYPE_DICTIONARY:
				continue
			var data := reward as Dictionary
			var kind := str(data.get("kind", ""))
			match kind:
				"cultivation":
					_reward_slot(slots, _q_icon("icons/tab_cultivate"), 3, CultivationFormat.amount(float(data.get("amount", 0))), "修为 +%s" % CultivationFormat.amount(float(data.get("amount", 0))), "FirstClearCultivation")
				"spiritStones":
					_reward_slot(slots, _q_icon("icons/res_stone"), 1, str(int(data.get("amount", 0))), "灵石 +%d" % int(data.get("amount", 0)), "FirstClearStones")
				"gear":
					var count := int(data.get("count", 1))
					_reward_slot(slots, _gear_icon("weapon"), 2, "×%d" % count if count > 1 else "", "随机装备 ×%d" % count)
				_:
					var slug := str(data.get("itemSlug", ""))
					var view := QKit.reward_view(_content, slug)
					var qty := int(data.get("quantity", 1))
					_reward_slot(slots, view.texture, int(view.rarity), "×%d" % qty if qty > 1 else "", str(view.name))
	else:
		var repeat: Variant = card_data.repeat
		var rules: Dictionary = card_data.rules
		if not bool(rules.get("repeatRewards", true)):
			slots.add_child(UiKit.label("再战没有奖励", 26, UiTokens.TEXT_MUTED))
		elif typeof(repeat) == TYPE_DICTIONARY:
			if bool((repeat as Dictionary).get("gear", false)):
				var pct: Dictionary = rules.get("gearQualityPct", {}) if typeof(rules.get("gearQualityPct", null)) == TYPE_DICTIONARY else {}
				var orange := int(pct.get("orange", 0))
				_reward_slot(slots, _gear_icon("helmet"), 4 if orange > 0 else 2, ("橙%d%%" % orange) if orange > 0 else "", "首领装备")
			for extra in (repeat as Dictionary).get("extras", []):
				if typeof(extra) == TYPE_DICTIONARY:
					var item := str((extra as Dictionary).get("itemSlug", ""))
					var view := QKit.reward_view(_content, item)
					_reward_slot(slots, view.texture, int(view.rarity), "%d%%" % int(round(float((extra as Dictionary).get("chanceBp", 0)) / 100.0)), str(view.name))
	if slots.get_child_count() == 0:
		slots.add_child(UiKit.label("没有奖励", 26, UiTokens.TEXT_MUTED))
	return row


## 奖励小格子（64）：数量 / 概率写在格子右下角，名字放提示。
func _reward_slot(row: HBoxContainer, tex: Texture2D, rarity: int, corner: String, tip: String, node_name: String = "") -> void:
	var slot := QKit.slot(tex, rarity, 64, corner, "", Color.WHITE)
	slot.tooltip_text = tip
	if not node_name.is_empty():
		slot.name = node_name
	row.add_child(slot)


static func _q_icon(path: String) -> Texture2D:
	return ArtLib.q(path) if ArtLib.has_q(path + ".png") else null


## 战力对比：用文字+符号表达，不只靠颜色。
static func power_status(mine: int, recommended: int) -> Dictionary:
	if recommended <= 0:
		return {"text": "无推荐战力", "symbol": "－", "level": "none"}
	if mine >= recommended:
		return {"text": "战力足够", "symbol": "✔", "level": "ok"}
	if float(mine) >= float(recommended) * 0.8:
		return {"text": "略低于推荐", "symbol": "!", "level": "warn"}
	return {"text": "战力差距大", "symbol": "✖", "level": "bad"}


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
