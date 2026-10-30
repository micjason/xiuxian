extends Node2D
## 主角战斗姿势动画（单帧 player_fight.png，朝右），SPEC_Q §17.1 / §17.8。只用 Godot 自带节点，不拆层。
## 节点原点 = 主角脚底中心（图内约 x318、y600）。box = 显示框（设计稿 440×440），图片按框等比缩放。
## 动作（全部在 _process 里按时间算，不建节点、不用 Tween、每帧不分配内存）：
##   待机（自动）：呼吸挤压 + 轻微起伏 + 上身摆动 + 衣袖 / 衣摆 / 发梢飘动（hero_fight.gdshader）
##   play_attack()：前冲出剑 → 回位（飞剑由 boss_battle 发出，attack_release 时机）
##   set_ult_charge(v)：自动技能蓄力 0..1 → 脚下聚气环顺时针填满、身后青光变亮、灵气粒子变多、身体外光；≥0.9 环脉动、剑尖闪光
##   play_ult()：蓄满自动释放 → 后仰蓄势（WINDUP 秒）→ ult_released（这时 boss_battle 放剑扇）→ 前送 + 聚气环闪亮后清空
##   play_hit(heavy)：闪白 + 击退 + 小幅后坐
##   play_defeat()：变灰、后仰下沉；play_victory()：小跳 + 剑光；reset()：回到待机

signal attack_release        ## 前冲到最前（出剑的那一刻）
signal ult_released          ## 蓄势结束，大招真正放出
signal hit_finished

const WINDUP := 0.32         ## 大招蓄势时长（秒）
const ATTACK_TIME := 0.4
const HIT_TIME := 0.32
## 图内坐标（player_fight.png 636×635）
const SRC_FEET := Vector2(318, 600)
const SRC_SWORD_TIP := Vector2(628, 262)
const SRC_SWORD_MID := Vector2(520, 282)
const SRC_CHEST := Vector2(300, 360)

@export var box := Vector2(440, 440):
	set(v):
		box = v
		if is_node_ready():
			_fit()
## 1 = 面朝右（默认，朝首领）；-1 = 镜像
@export var face := 1.0
@export var breathe := 0.02
@export var bob_px := 3.0
@export var sway_amount := 0.006
## 聚气环宽度（相对显示框宽度）
@export var ring_width := 0.95
@export var charge_color := Color(0.59, 0.96, 1.0)
@export var full_color := Color(1.0, 0.86, 0.35)
## 脚底往下还有多少像素可画（战场会裁切）。聚气环的前半圈超出时整体往上挪，保证整圈看得见。boss_battle 会自动设。
@export var ground_room := 10000.0:
	set(v):
		ground_room = v
		if is_node_ready():
			_fit()
## 蓄力时身体外光（每个透明像素 24 次采样，只在蓄力 > 55% 时开）。特别低端的机器可以关掉，聚气环 / 身后光 / 粒子照常。
@export var body_glow := true

@onready var _body: Node2D = $Body
@onready var _spr: Sprite2D = $Body/Sprite
@onready var _glow: Sprite2D = $BackGlow
@onready var _shadow: Sprite2D = $Shadow
@onready var _ring: Sprite2D = $Ring
@onready var _ring_front: Sprite2D = $RingFront
@onready var _motes: CPUParticles2D = $Motes
@onready var _glint: Sprite2D = $Glint
@onready var _burst: Sprite2D = $Burst
@onready var _wind: CPUParticles2D = $Gather

var _mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _ring_mat_f: ShaderMaterial
var _s := 1.0                 # 图片缩放
var _t := 0.0
var _phase := 0.0
var _charge := 0.0            # 页面给的目标值
var _disp := 0.0              # 显示值（平滑）
var _learned := true
var _atk_t := -1.0
var _atk_fired := false
var _hit_t := -1.0
var _hit_heavy := false
var _wind_t := -1.0
var _rel_t := -1.0
var _vic_t := -1.0
var _gray := 0.0
var _gray_target := 0.0
var _defeat := 0.0
var _defeat_target := 0.0
var _glow_base := Vector2.ONE
var _ring_base := Vector2.ONE
var _shadow_base := Vector2.ONE
var _last := PackedFloat32Array([-1, -1, -1, -1, -1, -1, -1])


func _ready() -> void:
	_mat = _spr.material as ShaderMaterial
	_ring_mat = _ring.material as ShaderMaterial
	_ring_mat_f = _ring_front.material as ShaderMaterial
	_glint.visible = false
	_burst.visible = false
	_wind.emitting = false
	_phase = randf() * TAU
	_fit()


## 换主角图（例如以后换皮）。图要朝右、脚底在 SRC_FEET 附近。
func set_texture(tex: Texture2D) -> void:
	if tex == null:
		return
	_spr.texture = tex
	_fit()


func _fit() -> void:
	if _spr == null or _spr.texture == null:
		return
	var sz := Vector2(_spr.texture.get_size())
	_s = minf(box.x / sz.x, box.y / sz.y)
	_spr.scale = Vector2(_s * face, _s)
	# 精灵居中显示（shader 往四周扩边要求居中）：把脚底挪到节点原点
	_spr.position = Vector2((sz.x * 0.5 - SRC_FEET.x) * _s * face, (sz.y * 0.5 - SRC_FEET.y) * _s)
	_mat.set_shader_parameter(&"pad_px", 24.0)
	_mat.set_shader_parameter(&"glow_px", 14.0)
	var w := box.x
	# 接触影（fx_contact_shadow 320×80）：宽≈框宽×0.62，高≈宽×0.25
	var sw := w * 0.62
	var sh := sw * 0.25
	_shadow_base = Vector2(sw / 320.0, sh / 80.0)
	_shadow.scale = _shadow_base
	_shadow.position = Vector2(-6 * _s, 4)
	_shadow.modulate.a = 1.0
	_glow_base = Vector2(w * 1.05, box.y * 0.95) / Vector2(_glow.texture.get_size())
	_glow.position = Vector2(-10 * _s, -box.y * 0.42)
	_ring_base = Vector2(w * ring_width, w * ring_width * 0.26) / Vector2(_ring.texture.get_size())
	_ring.scale = _ring_base
	# 环心比脚底略高；脚下空间不够（战场下沿裁切）时再往上挪，前半圈不被裁掉
	var half_h := w * ring_width * 0.26 * 0.5 * 1.1
	_ring.position = Vector2(-8 * _s, minf(-box.y * 0.05, ground_room - half_h - 4.0))
	_ring_front.scale = _ring_base
	_ring_front.position = _ring.position
	_motes.position = _ring.position
	_motes.emission_rect_extents = Vector2(w * ring_width * 0.42, 10)
	_wind.position = sword_tip_local() * 0.6
	_burst.position = _ring.position
	_glint.position = sword_tip_local()


## 剑尖 / 剑身中间 / 胸口（本节点坐标，不含动作位移）。boss_battle 用剑身中间当飞剑起点。
func sword_tip_local() -> Vector2:
	return Vector2((SRC_SWORD_TIP.x - SRC_FEET.x) * face, SRC_SWORD_TIP.y - SRC_FEET.y) * _s


func sword_home_local() -> Vector2:
	return Vector2((SRC_SWORD_MID.x - SRC_FEET.x) * face, SRC_SWORD_MID.y - SRC_FEET.y) * _s


func chest_local() -> Vector2:
	return Vector2((SRC_CHEST.x - SRC_FEET.x) * face, SRC_CHEST.y - SRC_FEET.y) * _s


# ================================================================ 对外
## 大招蓄力 0..1（页面每帧 / 每次刷新时给 BossFight.ult_charge()）。learned=false：本境界没有大招，聚气环不显示。
func set_ult_charge(v: float, learned: bool = true) -> void:
	_charge = clampf(v, 0.0, 1.0) if learned else 0.0
	_learned = learned


func play_attack() -> void:
	if _defeat_target > 0.0:
		return
	_atk_t = 0.0
	_atk_fired = false


## 大招：后仰蓄势 WINDUP 秒后发 ult_released。返回蓄势时长（调用方据此推迟剑扇）。
func play_ult() -> float:
	if _defeat_target > 0.0:
		return 0.0
	_wind_t = 0.0
	_rel_t = -1.0
	_atk_t = -1.0
	_wind.emitting = true
	return WINDUP


## 自动技能释放（推荐名）。play_ult 为遗留名。仅由战斗事件触发，**不要**挂玩家按钮。
func play_skill() -> float:
	return play_ult()



func play_hit(heavy: bool = false) -> void:
	_hit_t = 0.0
	_hit_heavy = heavy


func play_defeat() -> void:
	_gray_target = 1.0
	_defeat_target = 1.0
	_wind_t = -1.0
	_wind.emitting = false


func play_victory() -> void:
	if _defeat_target > 0.0:
		return
	_vic_t = 0.0


func reset() -> void:
	_atk_t = -1.0
	_hit_t = -1.0
	_wind_t = -1.0
	_rel_t = -1.0
	_vic_t = -1.0
	_gray = 0.0
	_gray_target = 0.0
	_defeat = 0.0
	_defeat_target = 0.0
	_charge = 0.0
	_disp = 0.0
	_wind.emitting = false
	_burst.visible = false
	_glint.visible = false
	modulate = Color.WHITE


func is_winding_up() -> bool:
	return _wind_t >= 0.0


func displayed_charge() -> float:
	return _disp


# ================================================================ 每帧
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var ph := _t * TAU / 2.4 + _phase
	var br := sin(ph)
	var off := Vector2(0, -bob_px * (0.5 + 0.5 * sin(ph * 2.0 + 0.6)) * 0.6)
	var rot := 0.0
	var sx := 1.0 - br * breathe * 0.6
	var sy := 1.0 + br * breathe
	var flash := 0.0
	var sway := sin(_t * 1.7 + _phase) * sway_amount

	# 普攻：0.09 秒冲到最前（出剑），之后回位
	if _atk_t >= 0.0:
		_atk_t += delta
		var a := _atk_t
		var k := 0.0
		if a < 0.09:
			k = a / 0.09
			k = 1.0 - (1.0 - k) * (1.0 - k)
		elif a < 0.2:
			k = 1.0     # 停在最前，等飞剑命中
		else:
			k = maxf(0.0, 1.0 - (a - 0.2) / (ATTACK_TIME - 0.2))
			k = k * k * (3.0 - 2.0 * k)
		if not _atk_fired and a >= 0.07:
			_atk_fired = true
			attack_release.emit()
		off.x += 30.0 * _s / 0.69 * k * face
		off.y += -6.0 * k
		rot += 0.07 * k * face
		sx *= 1.0 + 0.05 * k
		sy *= 1.0 - 0.03 * k
		if a >= ATTACK_TIME:
			_atk_t = -1.0

	# 受击：闪白 + 击退 + 后坐（先压扁再弹回）
	if _hit_t >= 0.0:
		_hit_t += delta
		var q := _hit_t / HIT_TIME
		var e := exp(-q * 4.0) * sin(minf(q * 9.0, PI) + 0.4) if q < 1.0 else 0.0
		flash = maxf(flash, maxf(0.0, 1.0 - q * 2.2))
		var kb := (26.0 if _hit_heavy else 18.0) * (1.0 - q) * (1.0 - q)
		off.x -= kb * face
		rot -= (0.09 if _hit_heavy else 0.06) * maxf(0.0, e) * face
		sy *= 1.0 - 0.06 * maxf(0.0, e)
		sx *= 1.0 + 0.04 * maxf(0.0, e)
		if q >= 1.0:
			_hit_t = -1.0
			hit_finished.emit()

	# 大招蓄势：后仰、压低、剑尖闪光、气往剑上收
	var wind_k := 0.0
	if _wind_t >= 0.0:
		_wind_t += delta
		wind_k = minf(1.0, _wind_t / (WINDUP * 0.8))
		wind_k = wind_k * wind_k * (3.0 - 2.0 * wind_k)
		off.x -= 14.0 * wind_k * face
		off.y += 6.0 * wind_k
		rot -= 0.1 * wind_k * face
		sy *= 1.0 - 0.05 * wind_k
		sx *= 1.0 + 0.04 * wind_k
		flash = maxf(flash, 0.25 * wind_k * (0.5 + 0.5 * sin(_t * 40.0)))
		if _wind_t >= WINDUP:
			_wind_t = -1.0
			_rel_t = 0.0
			_wind.emitting = false
			_burst.visible = true
			ult_released.emit()
	# 释放：猛地前送，然后回位
	var rel_k := 0.0
	if _rel_t >= 0.0:
		_rel_t += delta
		var r := _rel_t
		rel_k = minf(1.0, r / 0.06) * maxf(0.0, 1.0 - (r - 0.06) / 0.34)
		off.x += 24.0 * rel_k * face
		rot += 0.09 * rel_k * face
		sx *= 1.0 + 0.05 * rel_k
		var bp := r / 0.42
		# 地面冲击环（压扁成椭圆，从脚下往外扩）
		_burst.scale = Vector2(1.0, 0.3) * (0.8 + bp * 3.2) * box.x / 440.0
		_burst.modulate.a = maxf(0.0, 1.0 - bp)
		if bp >= 1.0:
			_burst.visible = false
		if r >= 0.5:
			_rel_t = -1.0

	# 胜利：小跳一下 + 剑光
	if _vic_t >= 0.0:
		_vic_t += delta
		var v := _vic_t
		if v < 0.42:
			off.y -= 26.0 * sin(PI * v / 0.42)
			sy *= 1.0 + 0.05 * sin(PI * v / 0.42)
		elif v < 0.52:
			sy *= 1.0 - 0.06 * sin(PI * (v - 0.42) / 0.1)
		if v > 1.4:
			_vic_t = -1.0

	# 失败：变灰、后仰下沉
	_gray = move_toward(_gray, _gray_target, delta / 0.45)
	_defeat = move_toward(_defeat, _defeat_target, delta / 0.5)
	if _defeat > 0.0:
		var d := _defeat * _defeat * (3.0 - 2.0 * _defeat)
		off.y += 12.0 * d
		rot -= 0.13 * d * face
		sy *= 1.0 - 0.05 * d
		sway *= 1.0 - d
	_body.position = off
	_body.rotation = rot
	_body.scale = Vector2(sx, sy)

	# 蓄力显示：蓄势 / 释放期间先保持满，释放后快速清空，其余时间跟着页面的值
	if _wind_t >= 0.0:
		_disp = 1.0
	elif _rel_t >= 0.0:
		_disp = move_toward(_disp, 0.0, delta / 0.35)
	else:
		_disp = move_toward(_disp, _charge, delta * (3.0 if _charge > _disp else 1.5))
	var c := _disp * (1.0 - _defeat)
	var ready := smoothstep(0.88, 1.0, c) if _rel_t < 0.0 else 0.0
	var flare := maxf(wind_k, rel_k)
	var pulse := 0.5 + 0.5 * sin(_t * 12.0)
	if _set_p(0, &"fill", c, _ring_mat):
		_ring_mat_f.set_shader_parameter(&"fill", c)
	if _set_p(1, &"ready", ready, _ring_mat):
		_ring_mat_f.set_shader_parameter(&"ready", ready)
	if _set_p(2, &"flare", flare, _ring_mat):
		_ring_mat_f.set_shader_parameter(&"flare", flare)
	_ring.visible = _learned and (c > 0.002 or flare > 0.0 or _defeat < 0.5)
	_ring_front.visible = _ring.visible
	_ring.scale = _ring_base * (1.0 + ready * 0.03 * pulse + flare * 0.08)
	_ring_front.scale = _ring.scale
	_glow.scale = _glow_base * (0.9 + 0.12 * c + 0.05 * ready * pulse + 0.12 * flare)
	_glow.modulate.a = (0.32 + 0.38 * c + 0.2 * ready * pulse + 0.3 * flare) * (1.0 - _defeat * 0.9)
	_motes.emitting = _learned and c > 0.04 and _defeat <= 0.0
	# 粒子数固定（改 amount 会重启粒子）：用透明度 + 速度表现“越蓄越多”
	_motes.modulate.a = 0.3 + 0.7 * c
	_motes.speed_scale = 0.6 + 0.6 * c
	# 高度↑ → 接触影缩小变淡
	var air := clampf(-off.y / 40.0, 0.0, 0.3)
	_shadow.scale = _shadow_base * (1.0 - air)
	_shadow.modulate.a = 1.0 - air * 0.85
	# 剑尖闪光：快蓄满 / 蓄势时闪；胜利时再闪一下
	var gl := maxf(ready * (0.55 + 0.45 * sin(_t * 9.0)), wind_k)
	if _vic_t >= 0.3 and _vic_t < 0.9:
		gl = maxf(gl, sin(PI * (_vic_t - 0.3) / 0.6))
	_glint.visible = gl > 0.02
	if _glint.visible:
		_glint.position = _body.position + sword_tip_local().rotated(rot)
		_glint.rotation = _t * 2.5
		_glint.scale = Vector2.ONE * (0.35 + 0.35 * gl) * box.x / 440.0
		_glint.modulate.a = gl
	# 身体：摆动、闪白、灰、外光
	_set_p(3, &"sway", sway, _mat)
	_set_p(4, &"flash", flash, _mat)
	_set_p(5, &"gray", _gray, _mat)
	_set_p(6, &"charge_glow", maxf(smoothstep(0.55, 1.0, c) * (0.6 + 0.25 * ready * pulse), flare * 0.9) if body_glow else 0.0, _mat)


func _set_p(i: int, n: StringName, v: float, m: ShaderMaterial) -> bool:
	if absf(_last[i] - v) > 0.0005:
		_last[i] = v
		m.set_shader_parameter(n, v)
		return true
	return false
