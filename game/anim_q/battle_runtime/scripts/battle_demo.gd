extends Node2D
## 独立演示：固定脚底的 SpriteFrames 动画 + 12 秒单次战斗时间轴。

const C := preload("res://anim_q/battle_runtime/scripts/battle_config.gd")

var _hero: AnimatedSprite2D
var _boss: Sprite2D
var _effect_layer: Node2D
var _sword: AnimatedSprite2D
var _blast: AnimatedSprite2D
var _counter: AnimatedSprite2D
var _log_text: Label
var _elapsed := 0.0
var capture_mode := false
const FRAME_ROOT := "res://anim_q/battle_runtime/frames/"
const HERO_ANCHOR := Vector2(240, 280)
const STANDING_HEIGHT := 130.0
const ACTION_COUNTS := {"移动":7, "奔跑":4, "冲刺":3, "跳跃":3, "普通攻击":5,
 "技能攻击":4, "技能施放":5, "受击":4, "倒地":5, "胜利":3}


func _ready() -> void:
	_build_background()
	_build_characters()
	_effect_layer = Node2D.new()
	_effect_layer.name = "EffectLayer"
	_effect_layer.z_index = 20
	add_child(_effect_layer)
	_build_ui()
	_sword = _make_fx("技能特效-剑气", 7)
	_blast = _make_fx("技能特效-爆炸", 6)
	_counter = _make_fx("技能特效-剑气", 7)
	_counter.flip_h = true
	_counter.modulate = Color(1.0, 0.66, 0.42)
	seek_demo(0.0)
	print("BATTLE_DEMO_LAYOUT ready feet_y=", C.FEET_Y,
		" hero_h=", C.HERO_DISPLAY_H, " boss_h=", C.BOSS_DISPLAY_H,
		" hero_x=", C.HERO_CENTER_X, " boss_x=", C.BOSS_CENTER_X)


func _build_background() -> void:
	var bg_root := Node2D.new()
	bg_root.name = "Background"
	bg_root.z_index = 0
	add_child(bg_root)

	# 画布底色，避免背景图下方露黑边以外的空白突兀
	var clear := ColorRect.new()
	clear.name = "Clear"
	clear.position = Vector2.ZERO
	clear.size = Vector2(C.CANVAS_W, C.CANVAS_H)
	clear.color = Color(0.06, 0.08, 0.07, 1.0)
	clear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_root.add_child(clear)

	var tex: Texture2D = load(C.TEX_BG) as Texture2D
	var bg := TextureRect.new()
	bg.name = "BattleBg"
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.position = Vector2(0, C.BG_TOP)
	bg.size = Vector2(C.CANVAS_W, C.BG_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_root.add_child(bg)

	# 背景下沿淡到底色，衔接战报区
	var fade := ColorRect.new()
	fade.name = "BgFade"
	fade.position = Vector2(0, C.BG_TOP + C.BG_H - 120.0)
	fade.size = Vector2(C.CANVAS_W, 160.0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(0.06, 0.08, 0.07, 0.0)
	# 用简单半透明条压一下接缝
	fade.color = Color(0.06, 0.08, 0.07, 0.55)
	bg_root.add_child(fade)


func _build_characters() -> void:
	var chars := Node2D.new()
	chars.name = "Characters"
	chars.z_index = 10
	add_child(chars)

	_hero = AnimatedSprite2D.new()
	_hero.name = "Hero"
	_hero.sprite_frames = SpriteFrames.new()
	_hero.sprite_frames.remove_animation("default")
	for action: String in ACTION_COUNTS:
		_hero.sprite_frames.add_animation(action)
		_hero.sprite_frames.set_animation_speed(action, 11.0)
		_hero.sprite_frames.set_animation_loop(action, false)
		for i in int(ACTION_COUNTS[action]):
			_hero.sprite_frames.add_frame(action, load(FRAME_ROOT + "hero/" + action + "/%02d.png" % i))
	# No 待机 label is used: the quieter 移动 poses are slowed and ping-ponged.
	_hero.sprite_frames.add_animation("idle")
	_hero.sprite_frames.set_animation_speed("idle", 11.0)
	_hero.sprite_frames.set_animation_loop("idle", true)
	for i in [2, 3, 4, 3]:
		_hero.sprite_frames.add_frame("idle", _hero.sprite_frames.get_frame_texture("移动", i))
	_hero.centered = false
	_hero.offset = -HERO_ANCHOR
	_hero.position = Vector2(C.HERO_CENTER_X, C.FEET_Y)
	_hero.scale = Vector2.ONE * (C.HERO_DISPLAY_H / STANDING_HEIGHT)
	chars.add_child(_hero)

	_boss = _make_char_sprite("Boss", C.TEX_BOSS, C.BOSS_CENTER_X, C.FEET_Y, C.BOSS_DISPLAY_H)
	chars.add_child(_boss)


## 脚底锚点：Sprite2D offset 使脚底落在 (center_x, feet_y)。
func _make_char_sprite(node_name: String, path: String, center_x: float, feet_y: float, display_h: float) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.name = node_name
	var tex: Texture2D = load(path if ResourceLoader.exists(path) else "res://anim_q/battle_runtime/art/boss_bear.png") as Texture2D
	spr.texture = tex
	var src_h := float(tex.get_height())
	var scale_v := display_h / src_h
	spr.scale = Vector2(scale_v, scale_v)
	# 默认 centered=true：本地原点在贴图中心。把中心抬到脚底上方 display_h/2。
	spr.position = Vector2(center_x, feet_y - display_h * 0.5)
	spr.centered = true
	return spr


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	layer.layer = 30
	add_child(layer)

	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_boss_hud(root)
	_build_hero_hud(root)
	_build_log(root)


func _build_boss_hud(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "BossHud"
	panel.position = Vector2(80, C.BOSS_HUD_TOP)
	panel.size = Vector2(C.CANVAS_W - 160, C.BOSS_HUD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.72)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	v.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = C.BOSS_NAME
	name_lbl.add_theme_font_size_override("font_size", 36)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	name_row.add_child(name_lbl)

	var lvl := Label.new()
	lvl.text = "首领 · 黑风岭"
	lvl.add_theme_font_size_override("font_size", 26)
	lvl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 0.9))
	name_row.add_child(lvl)

	var bar := _make_hp_bar(
		"BossHp",
		float(C.BOSS_HP) / float(C.BOSS_HP_MAX),
		Color(0.82, 0.22, 0.18, 1.0),
		"%d / %d" % [C.BOSS_HP, C.BOSS_HP_MAX]
	)
	v.add_child(bar)


func _build_hero_hud(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "HeroHud"
	panel.position = Vector2(48, C.HERO_HUD_TOP)
	panel.size = Vector2(420, C.HERO_HUD_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.1, 0.78)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var name_lbl := Label.new()
	name_lbl.text = "青衣剑修"
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0, 1.0))
	v.add_child(name_lbl)

	var bar := _make_hp_bar(
		"HeroHp",
		float(C.HERO_HP) / float(C.HERO_HP_MAX),
		Color(0.25, 0.78, 0.55, 1.0),
		"%d / %d" % [C.HERO_HP, C.HERO_HP_MAX]
	)
	v.add_child(bar)


func _make_hp_bar(bar_name: String, ratio: float, fill: Color, text: String) -> Control:
	var wrap := Control.new()
	wrap.name = bar_name
	wrap.custom_minimum_size = Vector2(0, 28)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track := ColorRect.new()
	track.name = "Track"
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.color = Color(0.12, 0.12, 0.14, 0.95)
	wrap.add_child(track)

	var fill_r := ColorRect.new()
	fill_r.name = "Fill"
	fill_r.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fill_r.anchor_right = clampf(ratio, 0.0, 1.0)
	fill_r.offset_left = 0
	fill_r.offset_right = 0
	fill_r.offset_top = 0
	fill_r.offset_bottom = 0
	fill_r.color = fill
	wrap.add_child(fill_r)

	var lbl := Label.new()
	lbl.name = "HpText"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	wrap.add_child(lbl)
	return wrap


func _build_log(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "BattleLog"
	panel.position = Vector2(36, C.LOG_TOP)
	panel.size = Vector2(C.CANVAS_W - 72, C.CANVAS_H - C.LOG_TOP - C.LOG_BOTTOM_PAD)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.82)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var title := Label.new()
	title.text = "战报"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.7, 1.0))
	v.add_child(title)

	_log_text = Label.new()
	_log_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_text.add_theme_font_size_override("font_size", 28)
	_log_text.add_theme_color_override("font_color", Color(0.82, 0.89, 0.94))
	v.add_child(_log_text)


func _make_fx(action: String, count: int) -> AnimatedSprite2D:
	var fx := AnimatedSprite2D.new()
	fx.name = action
	fx.sprite_frames = SpriteFrames.new()
	fx.sprite_frames.set_animation_speed("default", 11.0)
	for i in count:
		fx.sprite_frames.add_frame("default", load(FRAME_ROOT + "fx/" + action + "/%02d.png" % i))
	# FX canvases use a bottom-center anchor at (160,210).
	fx.centered = false
	fx.offset = Vector2(-160, -210)
	fx.scale = Vector2.ONE * 1.8
	fx.visible = false
	_effect_layer.add_child(fx)
	return fx


func _process(delta: float) -> void:
	if not capture_mode:
		_elapsed += delta
		seek_demo(_elapsed)


# Both the real-time scene and deterministic capture use this same timeline.
func _pose(action: String, local_time: float, slow := 1.0) -> void:
	var count := _hero.sprite_frames.get_frame_count(action)
	_hero.animation = action
	var index := int(maxf(local_time, 0.0) * 11.0 * slow)
	_hero.frame = index % count if action == "idle" else mini(index, count - 1)
	var base := C.HERO_DISPLAY_H / STANDING_HEIGHT
	var breathe := sin(local_time * TAU / 2.4) * 0.006 if action == "idle" else 0.0
	_hero.scale = Vector2(base, base * (1.0 + breathe))
	_hero.position = Vector2(C.HERO_CENTER_X, C.FEET_Y)


func _fly(fx: AnimatedSprite2D, t: float, start: float, duration: float, from: Vector2, to: Vector2) -> void:
	fx.visible = t >= start and t < start + duration
	if fx.visible:
		var phase := clampf((t - start) / duration, 0.0, 0.999)
		fx.position = from.lerp(to, phase)
		fx.frame = mini(int(phase * 7.0), 6)


func seek_demo(t: float) -> void:
	if t < 2.0:
		_pose("idle", t, 0.22)
	elif t < 2.65:
		_pose("普通攻击", t - 2.0)
	elif t < 3.1:
		_pose("idle", t, 0.22)
	elif t < 4.0:
		_pose("技能施放", t - 3.1)
	elif t < 4.8:
		_pose("技能攻击", t - 4.0)
	elif t >= 8.45 and t < 9.2:
		_pose("受击", t - 8.45)
	else:
		_pose("idle", t, 0.22)
	_fly(_sword, t, 4.35, 1.15, Vector2(350, 1180), Vector2(800, 1180))
	_blast.visible = t >= 5.4 and t < 6.15
	_blast.position = Vector2(C.BOSS_CENTER_X, C.FEET_Y - 15)
	if _blast.visible:
		_blast.frame = mini(int((t - 5.4) * 11.0), 5)
	_fly(_counter, t, 7.5, 1.05, Vector2(780, 1190), Vector2(280, 1190))
	_hero.modulate = Color(1.0, 0.78, 0.73) if t >= 8.45 and t < 8.7 else Color.WHITE
	var lines: Array[String] = ["· 进入黑风岭 · 遭遇黑风熊王", "· 青衣剑修凝神调息，蓄势待发"]
	if t >= 2.0: lines.append("· 青锋出鞘 · 普通攻击")
	if t >= 3.1: lines.append("· 聚灵施法 · 剑气凝形")
	if t >= 4.35: lines.append("· 苍岚剑气破空，直取熊王")
	if t >= 5.4: lines.append("· 剑气命中 · 灵光迸发")
	if t >= 7.5: lines.append("· 熊王反击 · 妖气袭来")
	if t >= 8.45: lines.append("· 剑修受击，稳住身形")
	if t >= 9.2: lines.append("· 收剑调息 · 回到待战")
	_log_text.text = "\n\n".join(lines)
