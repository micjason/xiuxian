extends Node2D
## 通用怪物模板：任意一张 mon_*.png 都能用（不需要拆层）。
## 节点原点 = 怪物显示框的中心（与历练页原来 TextureRect 的框一致，图片等比缩放后居中）。
## 动作：spawn() 刷出 / idle 待机（自动）/ hit() 受击 / attack() 扑向主角 / die() 溶解消失。
## 所有动作都是在 _process 里按时间计算，不创建新节点、不用 Tween，没有每帧内存分配。

signal spawned
signal attack_impact
signal died

const P_FLASH := &"flash"
const P_DISSOLVE := &"dissolve"
enum { HIDDEN, SPAWNING, ALIVE, DYING }

## 显示框大小（像素）。历练页目标怪 = 340×370。
@export var box := Vector2(340, 370)
## 朝向：主角在左边，怪物要面朝左。
@export var face_left_flip := true
@export var bob_height := 5.0
## 击退方向（+x = 往右，远离左边的主角）
@export var knock_dir := 1.0

@onready var _body: Node2D = $Body
@onready var _spr: Sprite2D = $Body/Sprite
@onready var _shadow: Sprite2D = $Shadow
var _mat: ShaderMaterial

var state := HIDDEN
var _t := 0.0
var _st := 0.0          # 当前状态已经过的时间
var _flash := 0.0
var _knock := 0.0
var _squash := 0.0
var _lunge := -1.0
var _lunge_hit := false
var _disp_h := 0.0
var _shadow_base := Vector2.ONE
var _last_flash := -1.0
var _last_dis := -1.0


func _ready() -> void:
	_mat = _spr.material as ShaderMaterial
	_shadow_base = _shadow.scale
	if _spr.texture != null:
		_fit()
	visible = false


## 换怪物图。flip = 是否水平翻转（历练页用 ArtLib.monster_needs_flip）。
func texture() -> Texture2D:
	return _spr.texture if _spr != null else null


func set_texture(tex: Texture2D, flip: bool) -> void:
	_spr.texture = tex
	_spr.flip_h = flip
	_fit()


func _fit() -> void:
	var tex := _spr.texture
	if tex == null:
		return
	var sz := tex.get_size()
	var s := minf(box.x / sz.x, box.y / sz.y)
	_disp_h = sz.y * s
	_spr.scale = Vector2(s, s)
	_spr.position = Vector2(0, -_disp_h * 0.5)
	_body.position = Vector2(0, _disp_h * 0.5)
	_shadow.position = Vector2(0, _disp_h * 0.5 - 4)
	_shadow_base = Vector2(sz.x * s / 128.0 * 0.95, 1.0)


func spawn() -> void:
	state = SPAWNING
	_st = 0.0
	_flash = 1.0
	_lunge = -1.0
	_knock = 0.0
	visible = true


## strength 1 = 普通一刀；大一点更明显（最后一刀用 1.4）。
func hit(strength: float = 1.0) -> void:
	if state != ALIVE:
		return
	_flash = 1.0
	_knock = 22.0 * strength
	_squash = 0.07 * strength


func attack() -> void:
	if state != ALIVE or _lunge >= 0.0:
		return
	_lunge = 0.0
	_lunge_hit = false


func die() -> void:
	if state == HIDDEN or state == DYING:
		return
	state = DYING
	_st = 0.0
	_lunge = -1.0


func is_alive() -> bool:
	return state == ALIVE


func is_busy() -> bool:
	return state == SPAWNING or state == DYING or _lunge >= 0.0


func _set_params(fl: float, dis: float) -> void:
	if absf(fl - _last_flash) > 0.002:
		_last_flash = fl
		_mat.set_shader_parameter(P_FLASH, fl)
	if absf(dis - _last_dis) > 0.002:
		_last_dis = dis
		_mat.set_shader_parameter(P_DISSOLVE, dis)


func _process(delta: float) -> void:
	if state == HIDDEN or not is_visible_in_tree():
		return
	_t += delta
	_st += delta
	var bob := sin(_t * 2.6) * bob_height
	var breathe := sin(_t * 2.6 + 0.6) * 0.018
	var sx := 1.0 + breathe
	var sy := 1.0 - breathe
	var ox := 0.0
	var oy := bob - bob_height
	var dis := 0.0
	var alpha := 1.0
	match state:
		SPAWNING:
			var p := clampf(_st / 0.45, 0.0, 1.0)
			var s := _back_out(p) * 0.4 + 0.6
			sx *= s
			sy *= s
			alpha = clampf(p * 2.5, 0.0, 1.0)
			_flash = 1.0 - p
			if p >= 1.0:
				state = ALIVE
				_flash = 0.0
				spawned.emit()
		ALIVE:
			_flash = maxf(0.0, _flash - delta / 0.16)
		DYING:
			# 0~0.1 秒闪白，之后 0.65 秒溶解、缩小、上浮
			if _st < 0.1:
				_flash = 0.8
			else:
				var p := clampf((_st - 0.1) / 0.65, 0.0, 1.0)
				_flash = 0.8 * (1.0 - p) * (1.0 - p)
				dis = p
				sx *= 1.0 - p * 0.12
				sy *= 1.0 - p * 0.12
				oy -= p * 22.0
				if p >= 1.0:
					state = HIDDEN
					visible = false
					_set_params(0.0, 0.0)
					died.emit()
					return
	if _knock > 0.01:
		ox += _knock * knock_dir
		_knock = move_toward(_knock, 0.0, delta * 120.0)
	if _squash > 0.001:
		sx *= 1.0 + _squash
		sy *= 1.0 - _squash
		_squash = move_toward(_squash, 0.0, delta * 0.5)
	if _lunge >= 0.0:
		_lunge += delta / 0.38
		var k := sin(PI * clampf(_lunge, 0.0, 1.0))
		ox -= 46.0 * k * knock_dir
		sx *= 1.0 + 0.05 * k
		if not _lunge_hit and _lunge >= 0.5:
			_lunge_hit = true
			attack_impact.emit()
		if _lunge >= 1.0:
			_lunge = -1.0
	_body.position = Vector2(ox, _disp_h * 0.5 + oy)
	_body.scale = Vector2(sx, sy)
	_spr.modulate.a = alpha
	_shadow.scale = _shadow_base * (1.0 - (bob + bob_height) * 0.012) * (1.0 - dis * 0.6)
	_shadow.modulate.a = alpha * (1.0 - dis)
	_set_params(_flash, dis)


static func _back_out(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
