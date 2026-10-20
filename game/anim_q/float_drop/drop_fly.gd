extends Node2D
## 掉落物飞入背包：先原地弹出，再沿弧线飞到目标（背包 Tab 图标），到达时发出 arrived 信号。
## 用法：var d = preload(".../drop_fly.tscn").instantiate(); add_child(d); d.icon = 物品贴图; d.fly(起点全局坐标, 背包图标全局坐标)
## 收到 arrived 后对背包图标播 bag_pulse.tscn 的 "hit" 动画。

signal arrived

@export var icon: Texture2D:
	set(v):
		icon = v
		var s := get_node_or_null("Item/Icon") as Sprite2D
		if s and v:
			s.texture = v
## 图标显示大小（像素，按长边）
@export var icon_size: float = 100.0
## 弧线高度（像素，越大抛得越高）
@export var arc_height: float = 260.0
## 飞行时长（秒）
@export var duration: float = 0.7
## 到达后自动删除自己
@export var auto_free: bool = true

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _ctrl := Vector2.ZERO

func _ready() -> void:
	if icon:
		$Item/Icon.texture = icon
	_fit_icon()

func _fit_icon() -> void:
	var s := $Item/Icon as Sprite2D
	if s.texture:
		var ts := s.texture.get_size()
		s.scale = Vector2.ONE * (icon_size / maxf(ts.x, ts.y))

func fly(from_global: Vector2, to_global: Vector2) -> void:
	_fit_icon()
	_from = from_global
	_to = to_global
	var mid := (from_global + to_global) * 0.5
	_ctrl = Vector2(mid.x + (from_global.x - to_global.x) * 0.25, minf(from_global.y, to_global.y) - arc_height)
	global_position = from_global
	var item := $Item as Node2D
	var trail := $Trail as CPUParticles2D
	item.scale = Vector2.ZERO
	item.rotation = 0.0
	item.visible = true
	trail.emitting = false
	var tw := create_tween()
	# 1) 原地弹出
	tw.tween_property(item, "scale", Vector2.ONE * 1.25, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(item, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.10)
	tw.tween_callback(func(): trail.emitting = true)
	# 2) 弧线飞行（先慢后快），边飞边缩小、轻微旋转
	tw.tween_method(_step, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(item, "scale", Vector2.ONE * 0.6, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(item, "rotation", -0.35, duration)
	tw.tween_callback(_arrive)

func _step(t: float) -> void:
	var a := _from.lerp(_ctrl, t)
	var b := _ctrl.lerp(_to, t)
	global_position = a.lerp(b, t)

func _arrive() -> void:
	$Item.visible = false
	$Trail.emitting = false
	arrived.emit()
	if auto_free:
		get_tree().create_timer(0.6).timeout.connect(queue_free)
