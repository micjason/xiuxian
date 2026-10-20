extends Node2D
## 首领战特效（战斗特效第二部分），挂在 BattlePage 的战场 _arena 里。坐标 = 战场 _arena 的本地坐标。
## 主角、首领的位置每次都从页面原来的节点（BattleHero / _boss_art）读取，战场大小变了也能对齐。
##
## 接法（详见 README）：
##   attach(_arena, 主角节点, _boss_art)    —— 一次；首领改由通用怪物模板来画（_boss_art 隐藏，只取贴图）
##   play_intro()  → 等 intro_finished      —— 点「开始挑战」后先播登场，再开始计时
##   on_event(event)                         —— BossFight 的每个事件（我方普攻 / 我方大招 / 首领攻击）
##   play_result(win, reason) → 等 result_finished —— 战斗结束
## 伤害数字 = 事件里的 damage 四舍五入（和战报一致）。只有大招用大号数字和强震屏；数字旁不加任何文字。
## 所有节点预先建好、循环复用；运行时不创建节点、不用 Tween；_process 没有内存分配。

signal intro_finished
signal result_finished
signal number_shown(side: String, damage: int)   ## side: "boss"（打在首领身上）/ "hero"（打在主角身上）

const ULT_LAUNCH := 0.48    ## 大招：剑扇停留到第一把剑射出的时间
const ULT_STAGGER := 0.05
const MonsterRig := preload("res://anim_q/battle_idle/monster_rig.gd")

@export var shake_light := 5.0      ## 普攻、首领攻击
@export var shake_medium := 9.0     ## 首领落地
@export var shake_strong := 16.0    ## 只有大招
@export var telegraph_every := 3    ## 每几次首领攻击做一次红圈预警（纯表现，0 = 关闭）
@export var number_top := 40.0      ## 数字最高到战场顶部往下这么多（血条、名字在战场外面上方）

@onready var _back: Node2D = $Back
@onready var _front: Node2D = $Front
@onready var _dim: ColorRect = $Back/Dim
@onready var _vignette: TextureRect = $Back/Vignette
@onready var _land: Sprite2D = $Back/LandCircle
@onready var _tele: Sprite2D = $Back/Telegraph
@onready var _magic: Node2D = $Back/MagicCircle
@onready var _magic_disc: Sprite2D = $Back/MagicCircle/Disc
@onready var boss: MonsterRig = $Back/Boss
@onready var _boss_spr: Sprite2D = $Back/Boss/Body/Sprite
@onready var _sword: Node2D = $Front/Sword
@onready var _sword_trail: CPUParticles2D = $Front/Sword/Trail
@onready var _crescent: Sprite2D = $Front/Crescent
@onready var _hit: Node2D = $Front/Hit
@onready var _slash_a: Sprite2D = $Front/Hit/SlashA
@onready var _slash_b: Sprite2D = $Front/Hit/SlashB
@onready var _hit_star: Sprite2D = $Front/Hit/Star
@onready var _hit_ring: Sprite2D = $Front/Hit/Ring
@onready var _sparks: CPUParticles2D = $Front/Hit/Sparks
@onready var _hero_hit: Sprite2D = $Front/HeroHit
@onready var _burst: CPUParticles2D = $Front/Burst
@onready var _dust: Sprite2D = $Front/Dust
@onready var _big: Node2D = $Front/BigNumber
@onready var _big_label: Label = $Front/BigNumber/Label
@onready var _alert: Sprite2D = $Front/Alert
@onready var _banner: Node2D = $Front/Banner
@onready var _band: Sprite2D = $Front/Banner/Band

var hero: CanvasItem
var boss_art: Control
var arena: Control
var _attach_pending := false
var _hero_base := Vector2.ZERO
var _hero_rect := Rect2(20, 280, 260, 254)
var _boss_rect := Rect2(552, 210, 460, 380)
var _size := Vector2(1032, 799)

var _t := 0.0
var _shake := 0.0
var _shake_amp := 0.0
var _hero_flash := 0.0
var _hero_knock := 0.0
var _hero_lean := 0.0
var _hero_gray := 0.0
var _hero_gray_target := 0.0
var _hero_sink := 0.0
var _dim_a := 0.0
var _dim_target := 0.0
var _vig_a := 0.0
var _vig_target := 0.0

# 普攻飞剑
var _sw_t := -1.0
var _sw_dmg := 0
var _sw_queue := PackedInt32Array()
var _hit_t := 9.0
# 首领攻击：等首领扑过来再飘数字
var _hero_pending := PackedInt32Array()
var _boss_events := 0
var _last_boss_time := -1.0
var _boss_gap := 0.0
var _tele_at := -1.0
var _tele_t := 9.0
var _tele_hit := false
var _hero_hit_t := 9.0
# 大招
var _ult_t := -1.0
var _ult_dmg := 0
var _ult_done := false
var _ult_swords: Array[Node2D] = []
var _ult_from := PackedVector2Array()
var _ult_dir := PackedFloat32Array()
var _lines: Array[Sprite2D] = []
var _big_t := 9.0
# 数字池
var _boss_nums: Array[Node2D] = []
var _hero_nums: Array[Node2D] = []
var _bn_t := PackedFloat32Array()
var _hn_t := PackedFloat32Array()
var _bn_base := PackedVector2Array()
var _hn_base := PackedVector2Array()
var _bn_next := 0
var _hn_next := 0
# 登场 / 结算
var _intro_t := -1.0
var _intro_landed := false
var _intro_leap := false
var _result_t := -1.0
var _result_win := false
var _result_dead := false
var _banner_t := -1.0
var _banner_hold := 0.8
var _dust_t := 9.0
var _magic_t := 9.0

var _tex_warn: Texture2D = preload("res://anim_q/battle_boss/art/banner_warning.png")
var _tex_win: Texture2D = preload("res://anim_q/battle_boss/art/banner_win.png")
var _tex_lose: Texture2D = preload("res://anim_q/battle_boss/art/banner_lose.png")


func _ready() -> void:
	for n in $Front/BossNumbers.get_children():
		_boss_nums.append(n as Node2D)
		(n as Node2D).visible = false
	for n in $Front/HeroNumbers.get_children():
		_hero_nums.append(n as Node2D)
		(n as Node2D).visible = false
	_bn_t.resize(_boss_nums.size())
	_bn_base.resize(_boss_nums.size())
	_hn_t.resize(_hero_nums.size())
	_hn_base.resize(_hero_nums.size())
	_bn_t.fill(9.0)
	_hn_t.fill(9.0)
	for s in $Front/UltSwords.get_children():
		_ult_swords.append(s as Node2D)
		(s as Node2D).visible = false
	_ult_from.resize(_ult_swords.size())
	_ult_dir.resize(_ult_swords.size())
	for l in $Front/SpeedLines.get_children():
		_lines.append(l as Sprite2D)
	$Front/SpeedLines.visible = false
	boss.attack_impact.connect(_on_boss_impact)
	for n in [_hit, _hero_hit, _crescent, _dust, _big, _alert, _banner, _land, _tele, _magic]:
		(n as CanvasItem).visible = false
	_sword.visible = false
	_dim.color.a = 0.0
	_vignette.modulate.a = 0.0
	if _attach_pending:
		_do_attach.call_deferred()


func _notification(what: int) -> void:
	# Back 被挪到了战场底层；本节点被释放时一起释放
	if what == NOTIFICATION_PREDELETE and _back != null and is_instance_valid(_back) and _back.get_parent() != self:
		_back.queue_free()


## 接到战场上。hero_node = 主角（BattleHero 或退回的头像图），boss_node = 页面原来的首领 TextureRect。
## 可以在页面 _init 里调用（还没进场景树）：会等到 _ready 再真正挂上。
func attach(arena_node: Control, hero_node: CanvasItem, boss_node: Control) -> void:
	arena = arena_node
	hero = hero_node
	boss_art = boss_node
	if get_parent() == null:
		arena.add_child(self)
	if not is_node_ready():
		_attach_pending = true
		return
	_do_attach()


func _do_attach() -> void:
	_attach_pending = false
	# 背景层（压暗、落点圈、首领本体）放到战场最底下，主角画在它上面；前景层（剑、火花、数字、横幅）留在最上面
	if _back.get_parent() == self:
		remove_child(_back)
		arena.add_child(_back)
	arena.move_child(_back, 0)
	if not arena.resized.is_connected(_layout):
		arena.resized.connect(_layout, CONNECT_DEFERRED)
	_layout()
	if boss_art is TextureRect and (boss_art as TextureRect).texture != null:
		set_boss_from_art()


## 换首领图（open_stage 之后调用；会从 _boss_art 取贴图、翻转、颜色）。首领站在原来立绘的位置待机，点开始后 play_intro 跳起再落下。
func set_boss_from_art() -> void:
	if boss_art == null or not is_node_ready():
		return
	boss.set_texture(boss_art.texture if boss_art is TextureRect else null, (boss_art as TextureRect).flip_h if boss_art is TextureRect else false)
	_boss_spr.self_modulate = boss_art.modulate
	boss_art.visible = false
	reset()


## 回到开战前的状态（再来一次时也调用）。
func reset() -> void:
	# 开战前首领照常站着（和原来的立绘一样的位置），点开始后播登场
	boss.position = _boss_rect.get_center()
	boss.state = MonsterRig.ALIVE
	boss.visible = true
	boss._flash = 0.0
	boss._lunge = -1.0
	boss._set_params(0.0, 0.0)
	boss._process(0.0)
	_hero_gray = 0.0
	_hero_gray_target = 0.0
	_hero_sink = 0.0
	_intro_t = -1.0
	_result_t = -1.0
	_ult_t = -1.0
	_sw_t = -1.0
	_sw_queue.clear()
	_hero_pending.clear()
	_boss_events = 0
	_last_boss_time = -1.0
	_tele_at = -1.0
	_dim_target = 0.0
	_vig_target = 0.0
	_banner.visible = false
	_banner_t = -1.0
	for n in _boss_nums:
		n.visible = false
	for n in _hero_nums:
		n.visible = false
	_bn_t.fill(9.0)
	_hn_t.fill(9.0)
	_big.visible = false




func _layout() -> void:
	if arena == null:
		return
	_size = arena.size
	if hero is Control:
		var c := hero as Control
		_hero_rect = c.get_rect()
		_hero_base = c.position
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
	elif hero is Node2D:
		_hero_base = (hero as Node2D).position
	if boss_art != null:
		_boss_rect = boss_art.get_rect()
	boss.box = _boss_rect.size
	boss._fit()
	boss.position = _boss_rect.get_center()
	_dim.size = _size
	_vignette.size = _size
	var feet := Vector2(_boss_rect.get_center().x, _boss_rect.end.y - 12)
	_land.position = feet
	_tele.position = Vector2(_hero_rect.get_center().x, _hero_rect.end.y - 10)
	_magic.position = _tele.position
	_alert.position = Vector2(_hero_rect.get_center().x + 70, _hero_rect.position.y + 10)
	_sword.position = _sword_home()


func _hero_center() -> Vector2:
	return _hero_rect.get_center() + Vector2(0, 10)


func _boss_center() -> Vector2:
	return _boss_rect.get_center() + Vector2(0, -10)


func _sword_home() -> Vector2:
	return Vector2(_hero_rect.end.x + 20, _hero_rect.get_center().y - 20)


# ================================================================ 对外：事件
## BossFight 的一个事件：{"side": "player"/"boss", "damage": 数值, "kind": "ult"(可选)}。
func on_event(event: Dictionary) -> void:
	var dmg := int(round(float(event.get("damage", 0))))
	var side := str(event.get("side", ""))
	if side == "boss":
		_on_boss_attack(dmg)
	elif str(event.get("kind", "")) == "ult":
		_start_ult(dmg)
	else:
		_player_attack(dmg)


func _player_attack(dmg: int) -> void:
	if _sw_t >= 0.0:
		# 上一剑还在飞（2 倍速时可能连着来）：排队，数字一个都不会少
		_sw_queue.append(dmg)
		return
	_sw_dmg = dmg
	_sw_t = 0.0
	_sword.visible = true
	_sword_trail.emitting = true
	_hero_lean = 1.0


func _on_boss_attack(dmg: int) -> void:
	_boss_events += 1
	if _last_boss_time >= 0.0:
		var gap := _t - _last_boss_time
		_boss_gap = gap if _boss_gap <= 0.0 else lerpf(_boss_gap, gap, 0.5)
	_last_boss_time = _t
	_hero_pending.append(dmg)
	_tele_hit = _tele.visible
	_tele.visible = false
	if boss.is_alive() and not boss.is_busy():
		boss.attack()
	else:
		_on_boss_impact()
	# 预测下一次首领攻击，按需显示红圈预警（只是表现）
	_tele_at = -1.0
	if telegraph_every > 0 and _boss_gap > 0.9 and (_boss_events + 1) % telegraph_every == 0:
		_tele_at = _t + _boss_gap - 0.6


func _on_boss_impact() -> void:
	var heavy := _tele_hit
	_tele_hit = false
	for d in _hero_pending:
		_show_hero_number(d)
	_hero_pending.clear()
	_hero_hit.position = _hero_center()
	_hero_hit.modulate = Color(1, 0.6, 0.6) if heavy else Color(1, 0.85, 0.85)
	_hero_hit_t = 0.0
	_hero_hit.visible = true
	_hero_flash = 1.0
	_hero_knock = 1.0
	_kick_shake(shake_light * (1.4 if heavy else 1.0), 0.16)


# ================================================================ 对外：登场 / 结算
func play_intro() -> void:
	_layout()
	_intro_t = 0.0
	_intro_landed = false
	_dim_target = 0.32
	_vig_target = 0.5
	_show_banner(_tex_warn, 0.85)
	_alert.visible = true
	_alert.scale = Vector2.ZERO
	_land.visible = true
	_intro_leap = boss.is_alive()
	if not _intro_leap:
		boss.state = MonsterRig.HIDDEN
		boss.visible = false


func is_intro_playing() -> bool:
	return _intro_t >= 0.0


func is_result_playing() -> bool:
	return _result_t >= 0.0


func play_result(win: bool, reason: String = "") -> void:
	_result_t = 0.0
	_result_win = win
	_result_dead = not win and reason != "timeout"
	_tele.visible = false
	_tele_at = -1.0


func _show_banner(tex: Texture2D, hold: float) -> void:
	_band.texture = tex
	_banner.visible = true
	_banner.position = Vector2(_size.x * 0.5, _size.y * 0.17)
	_banner_t = 0.0
	_banner_hold = hold


func _kick_shake(amp: float, dur: float) -> void:
	if _shake <= 0.0 or amp >= _shake_amp:
		_shake_amp = amp
	_shake = maxf(_shake, dur)


# ================================================================ 大招
func _start_ult(dmg: int) -> void:
	_ult_t = 0.0
	_ult_dmg = dmg
	_ult_done = false
	_dim_target = 0.24
	_magic_t = 0.0
	_magic.visible = true
	# 六把剑在主角头顶排成扇形（剑尖朝外），停一下再依次转向首领射出
	var pivot := Vector2(_hero_rect.get_center().x + 30.0, _hero_rect.position.y + 40.0)
	var n := _ult_swords.size()
	for i in n:
		var ang := deg_to_rad(lerpf(-160.0, -20.0, float(i) / float(maxi(n - 1, 1))))
		_ult_from[i] = pivot + Vector2(cos(ang), sin(ang)) * 135.0
		_ult_dir[i] = ang + PI * 0.25
		_ult_swords[i].position = pivot
		_ult_swords[i].rotation = _ult_dir[i]
		_ult_swords[i].visible = true
		_ult_swords[i].scale = Vector2.ZERO
	$Front/SpeedLines.visible = true
	_hero_lean = 1.0


func _update_ult(delta: float) -> void:
	if _ult_t < 0.0:
		return
	_ult_t += delta
	var t := _ult_t
	var target := _boss_center()
	var n := _ult_swords.size()
	for i in n:
		var s := _ult_swords[i]
		var appear := clampf((t - float(i) * 0.03) / 0.18, 0.0, 1.0)
		var launch := ULT_LAUNCH + float(i) * ULT_STAGGER
		var aim := (target - _ult_from[i]).angle() + PI * 0.25
		if t < launch:
			var pivot := _ult_from[i].lerp(Vector2(_hero_rect.get_center().x + 30.0, _hero_rect.position.y + 40.0), 1.0 - _back_out(appear))
			s.position = pivot + Vector2(0, sin(t * 18.0 + float(i)) * 3.0)
			s.scale = Vector2.ONE * 0.6 * appear
			var turn := clampf((t - launch + 0.12) / 0.12, 0.0, 1.0)
			s.rotation = lerp_angle(_ult_dir[i], aim, turn)
			s.modulate.a = 1.0
		else:
			var p := clampf((t - launch) / 0.16, 0.0, 1.0)
			s.position = _ult_from[i].lerp(target + Vector2(float(i) * 8.0 - 20.0, float(i % 3) * 16.0 - 16.0), p * p)
			s.rotation = aim
			s.scale = Vector2.ONE * 0.6
			s.modulate.a = 1.0 - maxf(0.0, p - 0.85) / 0.15
			if p >= 1.0:
				s.visible = false
	# 速度线：从首领四周往中心收
	var lt := clampf((t - 0.1) / 0.95, 0.0, 1.0)
	var la := sin(PI * lt) * 0.55
	for i in _lines.size():
		var l := _lines[i]
		var ang := float(i) / float(_lines.size()) * TAU + 0.3
		var r := 330.0 - fposmod(t * 900.0 + float(i) * 47.0, 160.0)
		l.position = target + Vector2(cos(ang), sin(ang)) * r
		l.rotation = ang + PI
		l.modulate.a = la
	# 月牙剑气横扫
	var cs := ULT_LAUNCH + 0.1
	if t >= cs and t < cs + 0.3:
		var p := (t - cs) / 0.3
		_crescent.visible = true
		_crescent.position = target + Vector2(lerpf(-160.0, 120.0, p), 0)
		_crescent.scale = Vector2(1.0 + p * 0.4, 1.2 + p * 0.3)
		_crescent.modulate.a = sin(PI * p)
	else:
		_crescent.visible = false
	var impact := ULT_LAUNCH + float(n - 1) * ULT_STAGGER + 0.16
	if not _ult_done and t >= impact:
		_ult_done = true
		boss.hit(1.9)
		_spark_at(target, 1.6)
		_burst.position = target
		_burst.restart()
		_kick_shake(shake_strong, 0.36)
		_big_label.text = "-%d" % _ult_dmg
		_big.position = Vector2(_boss_rect.position.x + 70.0, maxf(target.y - _boss_rect.size.y * 0.24, number_top + 70.0))
		_big_t = 0.0
		_big.visible = true
		number_shown.emit("boss", _ult_dmg)
	if t > impact + 0.25:
		_dim_target = 0.0
	if t > impact + 0.6:
		_ult_t = -1.0
		$Front/SpeedLines.visible = false
		_magic.visible = false


# ================================================================ 每帧
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_update_sword(delta)
	_update_ult(delta)
	_update_fx(delta)
	_update_numbers(delta)
	_update_intro(delta)
	_update_result(delta)
	_update_banner(delta)
	_update_tele(delta)
	_update_hero_and_shake(delta)


func _update_sword(delta: float) -> void:
	if _sw_t < 0.0:
		return
	_sw_t += delta
	var home := _sword_home()
	var target := _boss_center() + Vector2(-_boss_rect.size.x * 0.22, 0)
	var ang := (target - home).angle() + PI * 0.25
	if _sw_t < 0.18:
		var p := _sw_t / 0.18
		_sword.position = home.lerp(target, p * p)
		_sword.rotation = ang
		_sword.scale = Vector2.ONE * 0.5 * minf(1.0, p * 4.0)
	elif _sw_dmg >= 0:
		boss.hit(1.0)
		_spark_at(target, 1.0)
		_show_boss_number(_sw_dmg)
		_kick_shake(shake_light, 0.12)
		_sw_dmg = -1
	else:
		var p := clampf((_sw_t - 0.18) / 0.2, 0.0, 1.0)
		_sword.position = target + Vector2(-60.0 * p, -40.0 * sin(PI * p))
		_sword.modulate.a = 1.0 - p
		if p >= 1.0:
			_sword_trail.emitting = false
			_sword.visible = false
			_sword.modulate.a = 1.0
			_sw_t = -1.0
			if not _sw_queue.is_empty():
				var d := _sw_queue[0]
				_sw_queue.remove_at(0)
				_player_attack(d)


func _spark_at(pos: Vector2, s: float) -> void:
	_hit.position = pos
	_hit.scale = Vector2(s, s)
	_hit.rotation = randf_range(-0.3, 0.3)
	_hit_t = 0.0
	_hit.visible = true
	_sparks.restart()


func _update_fx(delta: float) -> void:
	if _hit.visible:
		_hit_t += delta
		var p := _hit_t / 0.28
		if p >= 1.0:
			_hit.visible = false
		else:
			var e := 1.0 - (1.0 - p) * (1.0 - p)
			_slash_a.scale = Vector2(0.5 + e * 1.15, 1.2 - p * 0.7)
			_slash_b.scale = Vector2(0.4 + e * 0.95, 1.2 - p * 0.7)
			_slash_a.modulate.a = 1.0 - p
			_slash_b.modulate.a = 1.0 - p
			_hit_star.scale = Vector2.ONE * (0.6 + e * 0.9)
			_hit_star.modulate.a = 1.0 - p * p
			_hit_ring.scale = Vector2.ONE * (0.3 + e * 1.1)
			_hit_ring.modulate.a = (1.0 - p) * 0.9
	if _hero_hit.visible:
		_hero_hit_t += delta
		var q := _hero_hit_t / 0.25
		if q >= 1.0:
			_hero_hit.visible = false
		else:
			_hero_hit.scale = Vector2.ONE * (0.5 + q * 0.9)
			_hero_hit.modulate.a = 1.0 - q
	if _dust.visible:
		_dust_t += delta / 0.5
		if _dust_t >= 1.0:
			_dust.visible = false
		else:
			var e := 1.0 - pow(1.0 - _dust_t, 2.0)
			_dust.scale = Vector2(1.5 + e * 3.0, (1.5 + e * 3.0) * 0.28)
			_dust.modulate.a = 1.0 - _dust_t
	if _magic.visible:
		_magic_t += delta
		var a := minf(1.0, _magic_t / 0.2)
		_magic.scale = Vector2(0.9 * a, 0.27 * a)
		_magic_disc.rotation = _magic_t * 1.5
		_magic.modulate.a = a
	_dim_a = move_toward(_dim_a, _dim_target, delta * 2.5)
	_vig_a = move_toward(_vig_a, _vig_target, delta * 3.0)
	_dim.color.a = _dim_a
	_vignette.modulate.a = _vig_a
	_dim.visible = _dim_a > 0.001
	_vignette.visible = _vig_a > 0.001
	if _big.visible:
		_big_t += delta / 1.2
		var p := minf(_big_t, 1.0)
		var s := 1.0
		if p < 0.1:
			s = 0.3 + p / 0.1 * 1.1
		elif p < 0.2:
			s = 1.4 - (p - 0.1) / 0.1 * 0.4
		_big.scale = Vector2(s, s) * 1.2
		_big.modulate.a = 1.0 if p < 0.7 else 1.0 - (p - 0.7) / 0.3
		if p >= 1.0:
			_big.visible = false


# ---------------------------------------------------------------- 数字（首领身上 4 个、主角身上 3 个，循环复用）
func _show_boss_number(v: int) -> void:
	var i := _bn_next
	_bn_next = (_bn_next + 1) % _boss_nums.size()
	(_boss_nums[i].get_child(0) as Label).text = "-%d" % v
	var lane := i % 3
	_bn_base[i] = _boss_center() + Vector2(float(lane - 1) * 70.0, -_boss_rect.size.y * 0.18 - float(lane) * 26.0)
	_bn_t[i] = 0.0
	_boss_nums[i].visible = true
	number_shown.emit("boss", v)


func _show_hero_number(v: int) -> void:
	var i := _hn_next
	_hn_next = (_hn_next + 1) % _hero_nums.size()
	(_hero_nums[i].get_child(0) as Label).text = "-%d" % v
	_hn_base[i] = _hero_center() + Vector2(float(i - 1) * 50.0, -_hero_rect.size.y * 0.3 - float(i) * 20.0)
	_hn_t[i] = 0.0
	_hero_nums[i].visible = true
	number_shown.emit("hero", v)


func _update_numbers(delta: float) -> void:
	for i in _boss_nums.size():
		if _bn_t[i] <= 1.0:
			_bn_t[i] = _anim_num(_boss_nums[i], _bn_base[i], _bn_t[i], delta, 0.72)
	for i in _hero_nums.size():
		if _hn_t[i] <= 1.0:
			_hn_t[i] = _anim_num(_hero_nums[i], _hn_base[i], _hn_t[i], delta, 0.62)


func _anim_num(n: Node2D, base: Vector2, t: float, delta: float, sc: float) -> float:
	t += delta / 0.9
	var p := minf(t, 1.0)
	var s := sc
	if p < 0.12:
		s *= 0.5 + p / 0.12 * 0.7
	elif p < 0.22:
		s *= 1.2 - (p - 0.12) / 0.1 * 0.2
	n.position = Vector2(base.x, maxf(base.y - 60.0 * (1.0 - pow(1.0 - p, 2.0)), number_top + 46.0 * s))
	n.scale = Vector2(s, s)
	n.modulate.a = 1.0 if p < 0.55 else 1.0 - (p - 0.55) / 0.45
	if p >= 1.0:
		n.visible = false
	return t


# ---------------------------------------------------------------- 登场
func _update_intro(delta: float) -> void:
	if _intro_t < 0.0:
		return
	_intro_t += delta
	var t := _intro_t
	# 「!」气泡
	var ap := clampf((t - 0.15) / 0.25, 0.0, 1.0)
	_alert.scale = Vector2.ONE * 0.9 * _back_out(ap)
	_alert.position.y = _hero_rect.position.y + 10.0 + sin(t * 10.0) * 3.0
	if t > 1.45:
		_alert.modulate.a = maxf(0.0, 1.0 - (t - 1.45) / 0.2)
	# 落点红圈：脉动
	if not _intro_landed:
		var pulse := 1.0 + sin(t * 14.0) * 0.06
		_land.scale = Vector2(0.95 * pulse, 0.26 * pulse) * minf(1.0, t / 0.2)
		_land.modulate.a = minf(1.0, t / 0.2)
	# 首领从上方落下
	var drop0 := 0.45
	var drop1 := 0.8
	var c := _boss_rect.get_center()
	var high := -(_boss_rect.end.y + 40.0)
	if _intro_leap and t < 0.32:
		# 开战前首领已经站着：先蓄力下蹲，再跳出画面
		var p := t / 0.32
		boss.position = c + Vector2(0, high * maxf(0.0, (p - 0.3) / 0.7) ** 2.0)
		if p < 0.3:
			boss._squash = 0.12 * sin(PI * p / 0.3)
	elif t < drop0:
		boss.position = c + Vector2(0, high)
	if t >= drop0 - 0.05 and boss.state == MonsterRig.HIDDEN:
		boss.position = c + Vector2(0, high)
		boss.spawn()
	if t >= drop0 and t < drop1:
		var p := (t - drop0) / (drop1 - drop0)
		boss.position = c + Vector2(0, -(_boss_rect.end.y + 40.0) * (1.0 - p * p))
	elif t >= drop1 and not _intro_landed:
		_intro_landed = true
		boss.position = c
		boss._squash = 0.16
		_land.visible = false
		_dust.position = Vector2(c.x, _boss_rect.end.y - 12)
		_dust_t = 0.0
		_dust.visible = true
		_burst.position = Vector2(c.x, _boss_rect.end.y - 30)
		_burst.restart()
		_kick_shake(shake_medium, 0.25)
	if t > 1.3:
		_dim_target = 0.0
		_vig_target = 0.0
	if t > 1.75:
		_intro_t = -1.0
		_alert.visible = false
		_alert.modulate.a = 1.0
		intro_finished.emit()


# ---------------------------------------------------------------- 结算
func _update_result(delta: float) -> void:
	if _result_t < 0.0:
		return
	# 赢的最后一击还在飞（飞剑 / 大招）：等它打中再开始溶解
	if _result_win and _result_t == 0.0 and ((_ult_t >= 0.0 and not _ult_done) or (_sw_t >= 0.0 and _sw_dmg >= 0) or not _sw_queue.is_empty()):
		return
	var prev := _result_t
	_result_t += delta
	var t := _result_t
	if _result_win:
		# 首领连闪三下 → 溶解
		for k in 3:
			var at := 0.05 + float(k) * 0.14
			if prev < at and t >= at:
				boss._flash = 1.0
				boss._knock = 10.0
		if prev < 0.5 and t >= 0.5:
			boss.die()
			_burst.position = _boss_center()
			_burst.restart()
			_kick_shake(shake_light, 0.15)
		if prev < 0.75 and t >= 0.75:
			_show_banner(_tex_win, 0.9)
	else:
		if prev < 0.05 and t >= 0.05:
			_hero_gray_target = 1.0
		if prev < 0.4 and t >= 0.4:
			_show_banner(_tex_lose, 0.9)
	if t > 1.9:
		_result_t = -1.0
		result_finished.emit()


func _update_banner(delta: float) -> void:
	if _banner_t < 0.0:
		return
	_banner_t += delta
	var t := _banner_t
	var w := _size.x
	var y := _size.y * 0.17
	if t < 0.28:
		var p := t / 0.28
		_banner.position = Vector2(lerpf(-w * 0.8, w * 0.5, _back_out(p)), y)
		_banner.modulate.a = minf(1.0, p * 3.0)
	elif t < 0.28 + _banner_hold:
		_banner.position = Vector2(w * 0.5, y)
	else:
		var p := (t - 0.28 - _banner_hold) / 0.25
		_banner.position = Vector2(lerpf(w * 0.5, w * 1.6, p * p), y)
		_banner.modulate.a = 1.0 - p
		if p >= 1.0:
			_banner.visible = false
			_banner_t = -1.0


func _update_tele(delta: float) -> void:
	if _tele_at >= 0.0 and _t >= _tele_at and not _tele.visible:
		_tele.visible = true
		_tele_t = 0.0
	if _tele.visible:
		_tele_t += delta
		var pulse := 1.0 + sin(_tele_t * 16.0) * 0.05
		var a := minf(1.0, _tele_t / 0.15)
		_tele.scale = Vector2(0.62, 0.18) * pulse * a
		_tele.modulate.a = a
		_boss_spr.self_modulate = boss_art.modulate.lerp(Color(1, 0.62, 0.62), 0.5 + sin(_tele_t * 16.0) * 0.3) if boss_art != null else Color(1, 0.7, 0.7)
		if _tele_t > 1.2:
			_tele.visible = false
	elif boss_art != null and _boss_spr.self_modulate != boss_art.modulate:
		_boss_spr.self_modulate = boss_art.modulate


func _update_hero_and_shake(delta: float) -> void:
	_hero_flash = move_toward(_hero_flash, 0.0, delta / 0.22)
	_hero_knock = move_toward(_hero_knock, 0.0, delta / 0.25)
	_hero_lean = move_toward(_hero_lean, 0.0, delta / 0.3)
	_hero_gray = move_toward(_hero_gray, _hero_gray_target, delta / 0.45)
	var off := Vector2.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		var k := _shake_amp * minf(1.0, _shake / 0.12)
		off = Vector2(sin(_t * 97.0) + sin(_t * 41.0) * 0.5, cos(_t * 83.0) * 0.7) * k * 0.7
	else:
		_shake_amp = 0.0
	_front.position = off
	_back.position = off
	if hero == null:
		return
	var hk := Vector2(10.0 * sin(PI * _hero_lean) - 16.0 * sin(PI * _hero_knock), 14.0 * _hero_gray * (1.0 if _result_dead else 0.0))
	var rot := 0.05 * sin(PI * _hero_lean) - 0.06 * sin(PI * _hero_knock)
	var f := 1.0 + _hero_flash * 0.5
	var g := 1.0 - _hero_gray * 0.32
	var col := Color(f * g * (1.0 - _hero_gray * 0.08), f * g * (1.0 - _hero_gray * 0.04), f * g, 1.0)
	if hero is Control:
		(hero as Control).position = _hero_base + off + hk
		(hero as Control).rotation = rot
	elif hero is Node2D:
		(hero as Node2D).position = _hero_base + off + hk
		(hero as Node2D).rotation = rot
	hero.modulate = col


static func _back_out(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
