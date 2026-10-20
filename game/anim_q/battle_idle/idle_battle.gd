extends Node2D
## 历练页 挂机打小怪特效（第一部分：小怪；首领战另做）。
## 坐标 = 设计稿 1080×2340 像素坐标。放进 StagePage._scene 时把本节点 position 设为 -StagePage.ORIGIN 即可对齐。
##
## 用法（每帧）：sync(怪物血量比例, 本波已击杀数)。其余全部自动：
##   血条每掉一段 → 主角御剑出手 → 命中火花 + 怪物闪白击退 + 伤害数字；
##   击杀 → 最后一刀(剩余血量) → 怪物闪白溶解成灵气 → 灵气飞向主角 +「+N 修为」→ 掉落物弹出飞进背包 → 下一只刷出。
## 伤害数字：每只怪显示的所有数字加起来 = 这只怪的配置气血（最后一刀补齐余数）。
## 不显示暴击、不用大号数字（大号样式留给首领战大招）。
## 所有节点都在场景里预先建好（对象池），运行时不创建/删除节点，不用 Tween，_process 里没有内存分配。

signal hit_landed(damage: int)      ## 一刀命中（数字已飘出）
signal monster_died                 ## 怪物溶解完毕
signal spirit_arrived(gain: float)  ## 灵气飞到主角（此时飘「+N 修为」）
signal drop_arrived                 ## 一件掉落物飞到背包（可让背包图标跳一下）

## 目标怪显示框（设计稿坐标），与 StagePage 里 TargetMonster 的 Rect2 一致。
@export var monster_rect := Rect2(560, 510, 340, 370)
## 主角胸口（灵气飞去的位置、受击火花位置）
@export var hero_chest := Vector2(204, 660)
## 飞剑待机位置
@export var sword_home := Vector2(400, 610)
## 两刀之间最短间隔（秒）
@export var hit_interval := 0.9
## 每几刀怪物反击一次（0 = 不反击）。挂机没有主角血量，所以反击只有闪白，不飘数字。
@export var counter_every := 4
## 伤害数字最高只能飘到这个 y（设计稿坐标）。怪物名牌 / 血条在 y 432–484，数字永远在它下面。
@export var number_top_limit := 500.0
## 背包图标的「全局」坐标（掉落物飞去的位置）。默认 = 1080×2340 画布底栏背包中心。
@export var bag_target_global := Vector2(972, 2190)
## 击杀修为（>0 时灵气到达主角时飘「+N 修为」；=0 不飘，由页面自己飘）。
@export var kill_gain := 0.0

const NUM_POOL := 4
const ORB_COUNT := 12
const DROP_POOL := 3
enum { S_HOME, S_OUT, S_BACK }

const MonsterRig := preload("monster_rig.gd")
@onready var monster: MonsterRig = $Monster
@onready var _sword: Node2D = $Sword
@onready var _sword_trail: CPUParticles2D = $Sword/Trail
@onready var _hit: Node2D = $Hit
@onready var _slash_a: Sprite2D = $Hit/SlashA
@onready var _slash_b: Sprite2D = $Hit/SlashB
@onready var _hit_star: Sprite2D = $Hit/Star
@onready var _hit_ring: Sprite2D = $Hit/Ring
@onready var _sparks: CPUParticles2D = $Hit/Sparks
@onready var _hero_hit: Sprite2D = $HeroHit
@onready var _burst: CPUParticles2D = $DeathBurst
@onready var _ground_ring: Sprite2D = $GroundRing
@onready var _gain: Node2D = $Gain
@onready var _gain_label: Label = $Gain/Number

var hero: CanvasItem = null         ## 主角节点（QHero），用于出手前倾 / 受击闪白。可不设。
var max_hp := 0
var _hero_base_pos := Vector2.ZERO
var _hero_base_rot := 0.0

var _last_ratio := -1.0
var _last_kills := -1
var _target := 0       # 按血条算出来「应该已经打掉」的血量
var _committed := 0    # 已经出手（含飞行中）的伤害合计
var _kill_pending := false
var _queued_kills := 0
var _cool := 0.0
var _swings := 0

var _sw_state := S_HOME
var _sw_t := 0.0
var _sw_dmg := 0
var _sw_final := false
var _sw_from := Vector2.ZERO
var _t := 0.0
var _hit_t := 9.0
var _hero_hit_t := 9.0
var _hero_kick := 0.0
var _hero_flash := 0.0

var _nums: Array[Node2D] = []
var _num_labels: Array[Label] = []
var _num_t := PackedFloat32Array()
var _num_base := PackedVector2Array()
var _num_next := 0

var _orbs: Array[Sprite2D] = []
var _orb_t := -1.0
var _orb_from := Vector2.ZERO
var _orb_paid := false
var _gain_t := 9.0
var _ring_t := 9.0

var _drops: Array[Sprite2D] = []
var _drop_trails: Array[CPUParticles2D] = []
var _drop_t := PackedFloat32Array()
var _drop_start := PackedVector2Array()
var _drop_land := PackedVector2Array()
var _drop_from_g := PackedVector2Array()
var _drop_arrived := PackedByteArray()
var _drop_scale := PackedFloat32Array()
var _queued_icons: Array[Texture2D] = []
var _after_death := -1.0
var _pending_monster: Array = []


func _ready() -> void:
	monster.position = monster_rect.get_center()
	monster.box = monster_rect.size
	monster.died.connect(_on_monster_died)
	monster.spawned.connect(func() -> void: _cool = hit_interval * 0.6)
	monster.attack_impact.connect(_on_counter_impact)
	for i in NUM_POOL:
		var n := $Numbers.get_child(i) as Node2D
		_nums.append(n)
		_num_labels.append(n.get_child(0) as Label)
		n.visible = false
	_num_t.resize(NUM_POOL)
	_num_base.resize(NUM_POOL)
	for i in NUM_POOL:
		_num_t[i] = 9.0
	for o in $Orbs.get_children():
		_orbs.append(o as Sprite2D)
		(o as Sprite2D).visible = false
	_drop_t.resize(DROP_POOL)
	_drop_start.resize(DROP_POOL)
	_drop_land.resize(DROP_POOL)
	_drop_from_g.resize(DROP_POOL)
	_drop_arrived.resize(DROP_POOL)
	_drop_scale.resize(DROP_POOL)
	for i in DROP_POOL:
		var d := $Drops.get_child(i) as Sprite2D
		d.visible = false
		_drops.append(d)
		_drop_trails.append(d.get_node("Trail") as CPUParticles2D)
		_drop_t[i] = -1.0
	_hit.visible = false
	_hero_hit.visible = false
	_gain.visible = false
	_ground_ring.visible = false
	_sword.position = sword_home
	if not _pending_monster.is_empty():
		set_monster(_pending_monster[0], _pending_monster[1], _pending_monster[2], _pending_monster[3])
		_pending_monster.clear()


## 设置 / 换怪物。tex = 怪物图，flip = 是否水平翻转，hp = 配置气血（wave.monster.hp），gain = 每只击杀修为。
func set_monster(tex: Texture2D, flip: bool, hp: int, gain: float = -1.0) -> void:
	if not is_node_ready():
		_pending_monster = [tex, flip, hp, gain]
		return
	var changed: bool = tex != monster.texture() or hp != max_hp
	max_hp = maxi(hp, 1)
	if gain >= 0.0:
		kill_gain = gain
	monster.set_texture(tex, flip)
	if changed:
		_committed = 0
		_target = 0
		_kill_pending = false
		_queued_kills = 0
		monster.spawn()


## 绑定主角节点（QHero）。出手时前倾，被怪物反击时闪白、后仰。
func bind_hero(node: CanvasItem) -> void:
	hero = node
	if node is Control:
		var c := node as Control
		_hero_base_pos = c.position
		_hero_base_rot = c.rotation
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
	elif node is Node2D:
		_hero_base_pos = (node as Node2D).position
		_hero_base_rot = (node as Node2D).rotation


## 本次击杀要弹出的掉落物图标（只传真实掉落，例如 lastSettle.drops 对应的物品图标）；下一只怪死亡时弹出。
func queue_drops(icons: Array[Texture2D]) -> void:
	for t in icons:
		if _queued_icons.size() < DROP_POOL:
			_queued_icons.append(t)


## 每帧调用：hp_ratio = 当前这只怪剩余血量比例（1 = 满血，即 StagePage 设给血条的值）；kills = 本波已击杀数。
func sync(hp_ratio: float, kills: int) -> void:
	if max_hp <= 0:
		return
	var killed := (_last_kills >= 0 and kills != _last_kills) or (_last_ratio >= 0.0 and hp_ratio > _last_ratio + 0.5)
	_last_ratio = hp_ratio
	_last_kills = kills
	if killed:
		if _kill_pending or not monster.is_alive():
			_queued_kills = mini(_queued_kills + 1, 2)
		else:
			_kill_pending = true
		return
	if not _kill_pending and monster.is_alive():
		_target = clampi(floori((1.0 - clampf(hp_ratio, 0.0, 1.0)) * float(max_hp)), _target, max_hp - 1)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_cool -= delta
	_update_sword(delta)
	_update_hit(delta)
	_update_numbers(delta)
	_update_orbs(delta)
	_update_drops(delta)
	_update_hero(delta)
	if _after_death >= 0.0:
		_after_death -= delta
		if _after_death < 0.0:
			monster.spawn()
	if _sw_state == S_HOME and monster.is_alive() and not monster.is_busy():
		if _kill_pending:
			_launch(max_hp - _committed, true)
		else:
			# 攒够一段再出手（≥ 气血 5%），避免飘「-3」这种碎数字；等太久（2 个间隔）就有多少打多少
			var pend := _target - _committed
			var chunk := maxi(1, ceili(float(max_hp) * 0.05))
			if pend >= 1 and ((_cool <= 0.0 and pend >= chunk) or _cool <= -hit_interval):
				_launch(pend, false)
	# 怪物刚刷出来、而这段时间里又被「打死」了（击杀很快时）：直接补一刀满血
	if monster.is_alive() and not _kill_pending and _queued_kills > 0 and _sw_state == S_HOME:
		_queued_kills -= 1
		_kill_pending = true


func _launch(dmg: int, final: bool) -> void:
	if dmg <= 0:
		return
	_committed += dmg
	_sw_dmg = dmg
	_sw_final = final
	_sw_state = S_OUT
	_sw_t = 0.0
	_sw_from = _sword.position
	_sword_trail.emitting = true
	_cool = hit_interval
	_hero_kick = 1.0


func _impact_point() -> Vector2:
	return monster_rect.get_center() + Vector2(-monster_rect.size.x * 0.24, -10)


func _update_sword(delta: float) -> void:
	var idle := sword_home + Vector2(0, sin(_t * 3.0) * 8.0)
	match _sw_state:
		S_HOME:
			_sword.position = _sword.position.lerp(idle, minf(1.0, delta * 10.0))
			_sword.rotation = lerp_angle(_sword.rotation, deg_to_rad(45.0) + sin(_t * 2.0) * 0.06, minf(1.0, delta * 8.0))
		S_OUT:
			_sw_t += delta / 0.2
			var p := minf(_sw_t, 1.0)
			_sword.position = _sw_from.lerp(_impact_point(), p * p)
			_sword.rotation = deg_to_rad(45.0)
			if _sw_t >= 1.0:
				_on_sword_impact()
				_sw_state = S_BACK
				_sw_t = 0.0
		S_BACK:
			_sw_t += delta / 0.32
			var p := minf(_sw_t, 1.0)
			var e := 1.0 - (1.0 - p) * (1.0 - p)
			var a := _impact_point()
			_sword.position = a.lerp(idle, e) + Vector2(0, -sin(PI * p) * 50.0)
			_sword.rotation = deg_to_rad(45.0) - sin(PI * p) * 0.5
			if _sw_t >= 0.6:
				_sword_trail.emitting = false
			if _sw_t >= 1.0:
				_sw_state = S_HOME
				_maybe_counter()


func _on_sword_impact() -> void:
	var final := _sw_final
	monster.hit(1.4 if final else 1.0)
	_hit.position = _impact_point()
	_hit_t = 0.0
	_hit.visible = true
	_hit.rotation = randf_range(-0.3, 0.3)
	_sparks.restart()
	_show_number(_sw_dmg, _impact_point() + Vector2(randf_range(30, 90), -30))
	hit_landed.emit(_sw_dmg)
	_swings += 1
	if final:
		_kill_pending = false
		_cool = hit_interval
		monster.die()
		_start_death_fx()


func _maybe_counter() -> void:
	if counter_every > 0 and _swings > 0 and _swings % counter_every == 0 and monster.is_alive() and not _kill_pending:
		monster.attack()


func _on_counter_impact() -> void:
	_hero_hit.position = hero_chest
	_hero_hit_t = 0.0
	_hero_hit.visible = true
	_hero_flash = 1.0


# ---------------------------------------------------------------- 命中火花
func _update_hit(delta: float) -> void:
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
			_hit_star.rotation = p * 0.8
			_hit_star.modulate.a = 1.0 - p * p
			_hit_ring.scale = Vector2.ONE * (0.3 + e * 1.1)
			_hit_ring.modulate.a = (1.0 - p) * 0.9
	if _hero_hit.visible:
		_hero_hit_t += delta
		var q := _hero_hit_t / 0.25
		if q >= 1.0:
			_hero_hit.visible = false
		else:
			_hero_hit.scale = Vector2.ONE * (0.4 + q * 0.8)
			_hero_hit.modulate.a = 1.0 - q


# ---------------------------------------------------------------- 伤害数字（4 个循环复用）
func _show_number(v: int, at: Vector2) -> void:
	var i := _num_next
	_num_next = (_num_next + 1) % NUM_POOL
	_num_labels[i].text = "-%d" % v
	_num_base[i] = at
	_num_t[i] = 0.0
	_nums[i].visible = true


func _update_numbers(delta: float) -> void:
	for i in NUM_POOL:
		if _num_t[i] > 1.0:
			continue
		_num_t[i] += delta / 0.85
		var p := minf(_num_t[i], 1.0)
		var n := _nums[i]
		var s := 0.74
		if p < 0.12:
			s *= 0.5 + p / 0.12 * 0.7
		elif p < 0.22:
			s *= 1.2 - (p - 0.12) / 0.1 * 0.2
		var y := _num_base[i].y - 70.0 * (1.0 - pow(1.0 - p, 2.0))
		# 数字上沿不能高过 number_top_limit（怪物名牌 / 血条在上面）
		y = maxf(y, number_top_limit + 46.0 * s)
		n.position = Vector2(_num_base[i].x, y)
		n.scale = Vector2(s, s)
		n.modulate.a = 1.0 if p < 0.55 else 1.0 - (p - 0.55) / 0.45
		if p >= 1.0:
			n.visible = false


# ---------------------------------------------------------------- 死亡：灵气流向主角
func _start_death_fx() -> void:
	_burst.position = monster_rect.get_center() + Vector2(0, 10)
	_burst.restart()
	_ground_ring.position = Vector2(monster_rect.get_center().x, monster_rect.end.y - 20)
	_ground_ring.visible = true
	_ring_t = 0.0
	_orb_from = monster_rect.get_center() + Vector2(-10, -30)
	_orb_t = 0.0
	_orb_paid = false
	_pop_drops()


func _bez(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


func _update_orbs(delta: float) -> void:
	if _ground_ring.visible:
		_ring_t += delta / 0.6
		if _ring_t >= 1.0:
			_ground_ring.visible = false
		else:
			var e := 1.0 - pow(1.0 - _ring_t, 2.0)
			_ground_ring.scale = Vector2(1.2 + e * 2.2, (1.2 + e * 2.2) * 0.3)
			_ground_ring.modulate.a = 1.0 - _ring_t
	if _orb_t >= 0.0:
		_orb_t += delta
		var ctrl := (_orb_from + hero_chest) * 0.5 + Vector2(0, -150)
		var all_done := true
		for i in ORB_COUNT:
			var o := _orbs[i]
			var lt := (_orb_t - 0.25 - float(i) * 0.04) / 0.6
			if lt < 0.0:
				o.visible = false
				all_done = false
				continue
			if lt >= 1.0:
				o.visible = false
				continue
			all_done = false
			o.visible = true
			var e := lt * lt * (3.0 - 2.0 * lt)
			var side := sin(float(i) * 2.3 + lt * 6.0) * 22.0 * (1.0 - lt)
			o.position = _bez(_orb_from + Vector2(0, float(i % 3) * 14.0 - 14.0), ctrl, hero_chest, e) + Vector2(0, side)
			var s := (1.0 + float(i % 3) * 0.35) * (1.0 - lt * 0.4)
			o.scale = Vector2(s, s)
			o.modulate.a = minf(1.0, lt * 5.0)
		if not _orb_paid and _orb_t > 0.85:
			_orb_paid = true
			_hero_flash = maxf(_hero_flash, 0.6)
			spirit_arrived.emit(kill_gain)
			if kill_gain > 0.0:
				_gain_label.text = "+%d" % roundi(kill_gain)
				_gain_t = 0.0
				_gain.visible = true
		if all_done and _orb_t > 1.0:
			_orb_t = -1.0
	if _gain.visible:
		_gain_t += delta / 1.1
		var p := minf(_gain_t, 1.0)
		var s := 1.0
		if p < 0.1:
			s = 0.6 + p / 0.1 * 0.55
		elif p < 0.18:
			s = 1.15 - (p - 0.1) / 0.08 * 0.15
		_gain.scale = Vector2(s, s) * 0.62
		_gain.position = hero_chest + Vector2(-40, -200 - 60.0 * p)
		_gain.modulate.a = 1.0 if p < 0.6 else 1.0 - (p - 0.6) / 0.4
		if p >= 1.0:
			_gain.visible = false


# ---------------------------------------------------------------- 掉落物：弹出 → 飞进背包
func _pop_drops() -> void:
	var n := _queued_icons.size()
	for i in n:
		var d := _drops[i]
		d.texture = _queued_icons[i]
		var sz := d.texture.get_size()
		var s := 84.0 / maxf(sz.x, sz.y)
		_drop_scale[i] = s
		_drop_start[i] = to_global(monster_rect.get_center())
		var off := (float(i) - float(n - 1) * 0.5) * 120.0
		_drop_land[i] = to_global(Vector2(monster_rect.get_center().x + off - 20.0, monster_rect.end.y - 70.0))
		_drop_t[i] = -float(i) * 0.08
		_drop_arrived[i] = 0
		d.visible = false
	_queued_icons.clear()


func _update_drops(delta: float) -> void:
	for i in DROP_POOL:
		if _drop_t[i] < -0.5:
			continue
		var d := _drops[i]
		var tr := _drop_trails[i]
		_drop_t[i] += delta
		var t := _drop_t[i]
		if t < 0.0:
			continue
		d.visible = true
		var bs := _drop_scale[i]
		if t < 0.45:
			# 弹出：抛物线落地
			var p := t / 0.45
			var pos := _drop_start[i].lerp(_drop_land[i], p) + Vector2(0, -sin(PI * p) * 150.0)
			d.global_position = pos
			d.scale = Vector2.ONE * bs * (0.5 + 0.5 * minf(1.0, p * 2.0))
			d.rotation = (1.0 - p) * 0.8
		elif t < 0.85:
			var p := (t - 0.45) / 0.4
			d.global_position = _drop_land[i] + Vector2(0, -absf(sin(p * PI * 1.5)) * 18.0 * (1.0 - p))
			d.scale = Vector2.ONE * bs
			d.rotation = 0.0
			_drop_from_g[i] = d.global_position
		elif t < 1.5:
			if not tr.emitting:
				tr.emitting = true
			var p := (t - 0.85) / 0.65
			var e := p * p
			var a := _drop_from_g[i]
			var b := bag_target_global
			var c := Vector2(maxf(a.x, b.x) + 60.0, minf(a.y, b.y) - 120.0)
			d.global_position = _bez(a, c, b, e)
			d.scale = Vector2.ONE * bs * (1.0 - 0.45 * e)
		else:
			if _drop_arrived[i] == 0:
				_drop_arrived[i] = 1
				drop_arrived.emit()
			d.visible = false
			tr.emitting = false
			_drop_t[i] = -1.0


# ---------------------------------------------------------------- 主角：出手前倾 / 受击闪白
func _update_hero(delta: float) -> void:
	_hero_kick = move_toward(_hero_kick, 0.0, delta / 0.3)
	_hero_flash = move_toward(_hero_flash, 0.0, delta / 0.25)
	if hero == null:
		return
	var k := sin(_hero_kick * PI) if _hero_kick > 0.0 else 0.0
	var off := Vector2(10.0 * k, 0)
	var rot := 0.06 * k
	if _hero_hit.visible:
		var q := _hero_hit_t / 0.25
		off += Vector2(-12.0 * sin(PI * minf(q, 1.0)), 0)
		rot -= 0.05 * sin(PI * minf(q, 1.0))
	var f := 1.0 + _hero_flash * 0.45
	if hero is Control:
		(hero as Control).position = _hero_base_pos + off
		(hero as Control).rotation = _hero_base_rot + rot
	elif hero is Node2D:
		(hero as Node2D).position = _hero_base_pos + off
		(hero as Node2D).rotation = _hero_base_rot + rot
	hero.modulate = Color(f, f * 0.96, f * 0.96, 1.0)


func _on_monster_died() -> void:
	monster_died.emit()
	_after_death = 0.35
	_committed = 0
	_target = 0


## 目标怪当前是否显示着（死亡溶解后到下一只刷出前为 false）。页面可以用它决定血条是否显示。
func monster_showing() -> bool:
	return monster.visible
