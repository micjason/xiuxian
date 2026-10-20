class_name QHero
extends Control
## 主角（拆层拼合、双手搭膝；动画交付 anim_q/hero_meditate）：打坐待机 idle 自动循环（呼吸、衣摆、闭眼，偶尔睁眼），
## 身边灵气光点、飘带、法阵。场景锚点 = 设计稿角色框（706×690）底边中点；这里按控件大小等比缩放、
## 底边居中摆放（和原来 TextureRect + KEEP_ASPECT_CENTERED 摆静态图的框一样大）。
## effects=false：只留人物本身（小尺寸的位置：背包纸娃娃、历练场景），不画灵气、法阵、光点。
## cushion=false：隐藏薄荷坐垫（下面已经有莲台的位置，如突破弹窗）。
## 场景缺失时退回静态拼合图 sprites/hero_meditate。

const FRAME := Vector2(706, 690)
const EFFECT_NODES := ["AuraGlow", "GroundCircle", "QiOrbs", "RiseSparkles", "Rig/Glow", "Rig/QiRibbonL", "Rig/QiRibbonR"]

var hero: Node2D
var _fallback: TextureRect


func _init(effects: bool = true, cushion: bool = true) -> void:
	name = "Hero"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero = QFx.make(QFx.HERO) as Node2D
	if hero == null:
		_fallback = TextureRect.new()
		_fallback.texture = ArtLib.q("sprites/hero_meditate") if ArtLib.has_q("sprites/hero_meditate.png") else null
		_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_fallback)
		return
	add_child(hero)
	if not effects:
		for path in EFFECT_NODES:
			var node := hero.get_node_or_null(path) as CanvasItem
			if node != null:
				node.visible = false
				if node is CPUParticles2D:
					(node as CPUParticles2D).emitting = false
	var seat := hero.get_node_or_null("Rig/Cushion") as CanvasItem
	if seat != null:
		seat.visible = cushion


func _notification(what: int) -> void:
	# 尺寸在进树前就定好时不会发 RESIZED，所以 READY 时也摆一次
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		_fit()


func _fit() -> void:
	if hero == null:
		return
	var s := minf(size.x / FRAME.x, size.y / FRAME.y)
	hero.scale = Vector2(s, s)
	hero.position = Vector2(size.x / 2.0, size.y / 2.0 + FRAME.y * s / 2.0)


## 是动画主角（不是静态图退回）。
func is_animated() -> bool:
	return hero != null


func current_animation() -> String:
	var ap := QFx.player(hero)
	return ap.current_animation if ap != null else ""
