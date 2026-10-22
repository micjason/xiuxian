class_name QFx
extends RefCounted
## 动画 / 特效统一入口（2026-10-20 动画交付，game/anim_q/，说明见 /workspace/anim_out_q/README.md）。
## 场景都是独立的 .tscn：这里只负责实例化、找节点、播动画；找不到场景时返回 null，调用方退回静态图（不报错）。

const DIR := "res://anim_q/"
const HERO := DIR + "hero_meditate/hero_meditate.tscn"
const BREAK_ORB := DIR + "ui_fx/ui_break_orb.tscn"
const BUTTON_BOUNCE := DIR + "ui_fx/ui_button_bounce.tscn"
const POPUP := DIR + "ui_fx/ui_popup.tscn"
const FLOAT_NUMBER := DIR + "float_drop/float_number.tscn"
const DROP_FLY := DIR + "float_drop/drop_fly.tscn"
const BAG_PULSE := DIR + "float_drop/bag_pulse.tscn"
## 短特效：舞台待机 / 充能，以及结算弹窗上的循环装饰。正式突破成功路径不播它的 success。
const BREAKTHROUGH := DIR + "breakthrough/breakthrough_fx.tscn"
## 天雷渡劫。服务端确认突破成功后播放，时长见 TRIBULATION_SECONDS（与 TribulationFx.DURATION 一致）。
const TRIBULATION := DIR + "breakthrough_tribulation/tribulation_fx.tscn"
const TRIBULATION_SECONDS := 10.0
const CHEST := DIR + "chest_open/chest_open.tscn"

## 通用按钮按下 / 松开回弹（照 ui_button_bounce 的 press / release 关键帧：0.08s 缩到 0.93；松开 0.12s 到 1.07 → 0.98 → 1）。
const PRESS_SCALE := 0.93


static func has(path: String) -> bool:
	return ResourceLoader.exists(path)


static func make(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed != null else null


static func player(node: Node, name: String = "AnimationPlayer") -> AnimationPlayer:
	return node.get_node_or_null(name) as AnimationPlayer if node != null else null


## 播动画（没有这个动画就什么都不做）。返回是否播了。
static func play(node: Node, anim: String, player_name: String = "AnimationPlayer") -> bool:
	var ap := player(node, player_name)
	if ap == null or not ap.has_animation(anim):
		return false
	ap.play(anim)
	return true


## 给现有按钮加 ui_button_bounce 同样的按下 / 回弹（不换按钮本身，原来的样式和信号都不变）。
static func bounce(button: BaseButton) -> void:
	if button == null or button.has_meta(&"q_bounce"):
		return
	button.set_meta(&"q_bounce", true)
	var center := func() -> void: button.pivot_offset = button.size / 2.0
	button.resized.connect(center)
	center.call()
	button.button_down.connect(func() -> void:
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE * PRESS_SCALE, 0.08))
	button.button_up.connect(func() -> void:
		var tween := button.create_tween()
		tween.tween_property(button, "scale", Vector2.ONE * 1.07, 0.12).set_trans(Tween.TRANS_SINE)
		tween.tween_property(button, "scale", Vector2.ONE * 0.98, 0.11).set_trans(Tween.TRANS_SINE)
		tween.tween_property(button, "scale", Vector2.ONE, 0.11).set_trans(Tween.TRANS_SINE))


## 弹窗打开 / 关闭（ui_popup.tscn）：遮罩淡入 + 面板从 0.55 倍弹性放大；关闭缩小淡出。
## 用法：var fx := QFx.popup_shell(); host.add_child(fx); 把弹窗内容放进 QFx.popup_content(fx)；
## 自带的边框 / 绶带 / 标题隐藏（用我们自己的 Q 版弹窗框）。面板铺满全屏、缩放中心由 set_popup_pivot 指定，
## 内容节点照旧用画布坐标摆放。
static func popup_shell(dim_color: Color = Color(0.09, 0.06, 0.04, 0.55)) -> Control:
	var fx := make(POPUP) as Control
	if fx == null:
		return null
	for path in ["Panel/Frame", "Panel/Ribbon", "Panel/Title"]:
		(fx.get_node(path) as CanvasItem).visible = false
	(fx.get_node("Panel/Title") as Label).text = ""  # 示例标题「离线收益」不用（我们的绶带自己写）
	var panel := fx.get_node("Panel") as Control
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	(fx.get_node("Backdrop") as ColorRect).color = dim_color
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return fx


static func popup_content(fx: Control) -> Control:
	return fx.get_node("Panel/Content") as Control


static func set_popup_pivot(fx: Control, frame: Rect2) -> void:
	(fx.get_node("Panel") as Control).pivot_offset = frame.get_center()
	(fx.get_node("Panel/Content") as Control).pivot_offset = frame.get_center()
