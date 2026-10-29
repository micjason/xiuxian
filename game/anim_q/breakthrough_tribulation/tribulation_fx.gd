extends Node2D
class_name TribulationFx
## 天雷渡劫 · 突破成功（约 10 秒）
## 用法：实例化后放到主角脚下（建议位置约 (540, 892)），把主角放进 HeroSlot，再调 play()。
## 信号：phase_changed(phase)、strike(index)、finished
## phase: "gather" | "tribulation" | "silence" | "success" | "done"

signal phase_changed(phase: String)
signal strike(index: int)
signal finished

const DURATION := 10.0
const GATHER_END := 1.8
const TRIB_END := 7.55
const SILENCE_END := 8.05
const SUCCESS_END := 10.0

## 渡劫落雷时间点（相对 play 起点），越往后越密/越重
const STRIKE_TIMES := [1.95, 2.55, 3.15, 3.65, 4.25, 4.85, 5.45, 6.05, 6.65, 7.25]
const FINAL_STRIKE_T := 7.45

@export var autoplay := false
@export var banner_text := "突破成功"
## 震屏强度倍率（低端机可调小）
@export var shake_mul := 1.0
## 是否使用全屏压暗（修炼/突破弹层建议开）
@export var use_dim := true

var _playing := false
var _t := 0.0
var _phase := ""
var _strike_i := 0
var _shake := Vector2.ZERO
var _shake_amp := 0.0
var _rng := RandomNumberGenerator.new()

@onready var _world: Node2D = $World
@onready var _dim: ColorRect = $World/Back/Dim
@onready var _flash: ColorRect = $FxLayer/ScreenFlash
@onready var _clouds: Node2D = $World/Back/Clouds
@onready var _sky_glow: Sprite2D = $World/Back/SkyGlow
@onready var _circle: Sprite2D = $World/Back/MagicGround/Circle
@onready var _qi: CPUParticles2D = $World/Back/QiGather
@onready var _hero: Node2D = $World/HeroSlot
@onready var _bolts: Node2D = $World/Bolts
@onready var _impact: Sprite2D = $World/StrikeImpact
@onready var _strike_glow: Sprite2D = $World/StrikeGlow
@onready var _sparks: CPUParticles2D = $World/Sparks
@onready var _embers: CPUParticles2D = $World/Embers
@onready var _hero_aura: Sprite2D = $World/Front/HeroAura
@onready var _pillar_wide: Sprite2D = $World/Front/PillarWide
@onready var _pillar: Sprite2D = $World/Front/Pillar
@onready var _gold_bloom: Sprite2D = $World/Front/GoldBloom
@onready var _flash_spr: Sprite2D = $World/Front/Flash
@onready var _sunburst: Sprite2D = $World/Front/Sunburst
@onready var _gold: CPUParticles2D = $World/Front/GoldBurst
@onready var _rising: CPUParticles2D = $World/Front/RisingGold
@onready var _title: Node2D = $World/Front/Title
@onready var _banner_glow: Sprite2D = $World/Front/Title/BannerGlow
@onready var _title_label: Label = $World/Front/Title/Box/Text
@onready var _rings: Array[Sprite2D] = []

func _ready() -> void:
	_rng.randomize()
	for i in 4:
		_rings.append($World/Front.get_node("Ring%d" % (i + 1)) as Sprite2D)
	_title_label.text = banner_text
	_reset_visuals()
	if autoplay:
		play()

func play() -> void:
	if not is_node_ready():
		call_deferred("play")
		return
	_success_started = false
	if _playing:
		return
	_playing = true
	_t = 0.0
	_strike_i = 0
	_shake = Vector2.ZERO
	_shake_amp = 0.0
	_reset_visuals()
	if _title_label != null:
		_title_label.text = banner_text
	_set_phase("gather")
	set_process(true)

func stop() -> void:
	_playing = false
	set_process(false)
	_reset_visuals()

func is_playing() -> bool:
	return _playing

func duration() -> float:
	return DURATION

func _reset_visuals() -> void:
	if _sky_glow == null:
		return
	if _dim:
		_dim.color = Color(0.05, 0.02, 0.12, 0.0)
		_dim.visible = use_dim
	if _flash:
		_flash.color = Color(1, 1, 1, 0)
	_sky_glow.modulate = Color(0.45, 0.55, 1.0, 0.0)
	_circle.modulate = Color(0.55, 0.7, 1.0, 0.0)
	_circle.rotation = 0.0
	_qi.emitting = false
	_qi.modulate = Color(0.7, 0.85, 1.0, 1.0)
	_impact.modulate = Color(1, 1, 1, 0)
	_strike_glow.modulate = Color(0.7, 0.85, 1.0, 0)
	_sparks.emitting = false
	_embers.emitting = false
	_hero_aura.modulate = Color(1, 0.9, 0.55, 0)
	_hero_aura.scale = Vector2(1.6, 1.8)
	_pillar_wide.modulate = Color(1, 0.92, 0.55, 0)
	_pillar_wide.scale = Vector2(0.0, 1.15)
	_pillar.modulate = Color(1, 1, 1, 0)
	_pillar.scale = Vector2(0.0, 1.2)
	_gold_bloom.modulate = Color(1, 0.95, 0.7, 0)
	_gold_bloom.scale = Vector2(0.6, 0.6)
	_flash_spr.modulate = Color(1, 1, 0.92, 0)
	_flash_spr.scale = Vector2(1, 1)
	_sunburst.modulate = Color(1, 0.9, 0.55, 0)
	_sunburst.scale = Vector2(0.35, 0.35)
	_sunburst.rotation = 0.0
	_gold.emitting = false
	_rising.emitting = false
	_title.scale = Vector2.ZERO
	_title.modulate = Color.WHITE
	_banner_glow.modulate = Color(1, 0.9, 0.5, 0)
	_hero.position = Vector2.ZERO
	_hero.modulate = Color.WHITE
	for c in _clouds.get_children():
		(c as CanvasItem).modulate = Color(1, 1, 1, 0)
	for b in _bolts.get_children():
		(b as CanvasItem).modulate = Color(1, 1, 1, 0)
		(b as Node2D).scale = Vector2(0.8, 0.8)
	for r in _rings:
		r.modulate = Color(1.0, 0.88, 0.5, 0.0)
		r.scale = Vector2(0.15, 0.15)
	if _world:
		_world.position = Vector2.ZERO

func _set_phase(p: String) -> void:
	if _phase == p:
		return
	_phase = p
	phase_changed.emit(p)

func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	_update_shake(delta)
	if _t < GATHER_END:
		_set_phase("gather")
		_tick_gather(_t / GATHER_END)
	elif _t < TRIB_END:
		_set_phase("tribulation")
		_tick_tribulation()
	elif _t < SILENCE_END:
		_set_phase("silence")
		_tick_silence((_t - TRIB_END) / (SILENCE_END - TRIB_END))
	elif _t < SUCCESS_END:
		_set_phase("success")
		_tick_success((_t - SILENCE_END) / (SUCCESS_END - SILENCE_END))
	else:
		_set_phase("done")
		_playing = false
		set_process(false)
		finished.emit()

func _tick_gather(u: float) -> void:
	# u: 0..1
	var a := smoothstep(0.0, 1.0, u)
	if use_dim:
		_set_a(_dim, lerpf(0.0, 0.62, a))
	_sky_glow.modulate = Color(0.45, 0.55, 1.0, lerpf(0.0, 0.55, a))
	_sky_glow.scale = Vector2.ONE * lerpf(2.2, 3.4, a)
	_circle.modulate = Color(0.55, 0.75, 1.0, lerpf(0.0, 0.85, a))
	_circle.rotation = u * PI * 0.55
	_circle.scale = Vector2.ONE * lerpf(1.2, 1.55, a)
	# clouds drift in
	var clouds := _clouds.get_children()
	for i in clouds.size():
		var c: Sprite2D = clouds[i]
		var cu := clampf((u - i * 0.12) / 0.7, 0.0, 1.0)
		c.modulate = Color(0.4, 0.3, 0.7, lerpf(0.0, 0.92, cu))
		c.position.x = c.get_meta("home_x") + sin(_t * 0.7 + i) * 8.0
	if u > 0.15 and not _qi.emitting:
		_qi.emitting = true
	# hero anticipation: slight lift + cyan tint
	_hero.position = Vector2(0, lerpf(0, -10, a))
	_hero.modulate = Color(lerpf(1, 0.85, a), lerpf(1, 0.9, a), 1.0, 1.0)
	# distant sky flashes near end of gather
	if u > 0.7:
		var flicker := absf(sin(_t * 18.0)) * (u - 0.7) / 0.3
		_flash.color = Color(0.7, 0.8, 1.0, flicker * 0.08)

func _tick_tribulation() -> void:
	var u := (_t - GATHER_END) / (TRIB_END - GATHER_END)
	if use_dim:
		_set_a(_dim, lerpf(0.62, 0.78, u))
	_sky_glow.modulate = Color(0.35, 0.4, 0.95, lerpf(0.55, 0.35, u))
	_circle.rotation = GATHER_END * 0.3 + _t * 0.55
	_circle.modulate = Color(0.6, 0.7, 1.0, lerpf(0.85, 0.4, u))
	# keep qi during tribulation but slower
	if not _qi.emitting:
		_qi.emitting = true
	# hero shiver intensifies
	var shiver := sin(_t * 42.0) * (4.0 + u * 6.0)
	_hero.position = Vector2(shiver * 0.35, -10 + sin(_t * 28.0) * 2.0)
	_hero.modulate = Color(0.85, 0.88, 1.0, 1.0)
	# fire scheduled strikes
	while _strike_i < STRIKE_TIMES.size() and _t >= STRIKE_TIMES[_strike_i]:
		var heavy := _strike_i >= STRIKE_TIMES.size() - 3
		_do_strike(_strike_i, false, heavy)
		_strike_i += 1
	if _t >= FINAL_STRIKE_T and _strike_i == STRIKE_TIMES.size():
		_do_strike(_strike_i, true, true)
		_strike_i += 1
	# ambient cloud pulse
	for i in _clouds.get_child_count():
		var c: Sprite2D = _clouds.get_child(i)
		var pulse := 0.7 + 0.25 * absf(sin(_t * 3.0 + i))
		c.modulate.a = pulse

func _tick_silence(u: float) -> void:
	# brief dark hold after final strike
	_qi.emitting = false
	if use_dim:
		_set_a(_dim, lerpf(0.75, 0.35, u))
	_set_a(_flash, maxf(_flash.color.a - 0.04, 0.0))
	_hero.position = Vector2(0, lerpf(-8, -14, u))
	_hero.modulate = Color(lerpf(0.7, 1.0, u), lerpf(0.75, 1.0, u), lerpf(0.9, 1.0, u), 1.0)
	_circle.modulate.a = lerpf(0.3, 0.0, u)
	for c in _clouds.get_children():
		(c as CanvasItem).modulate.a = lerpf((c as CanvasItem).modulate.a, 0.0, u * 0.3)

func _tick_success(u: float) -> void:
	# u 0..1 over ~2s — peak early, then settle so UI stays readable
	if u < 0.02:
		_start_success_burst()
	if use_dim:
		_set_a(_dim, lerpf(0.35, 0.0, clampf(u * 1.6, 0.0, 1.0)))

	# 1) Radial flash (short, punchy)
	var flash_u := clampf(u / 0.22, 0.0, 1.0)
	_flash_spr.scale = Vector2.ONE * lerpf(1.2, 7.0, flash_u)
	_flash_spr.modulate = Color(1.0, 0.95, 0.75, lerpf(1.0, 0.0, smoothstep(0.0, 1.0, flash_u)))

	# 2) Gold bloom expands then softens
	var bu := clampf(u / 0.45, 0.0, 1.0)
	_gold_bloom.scale = Vector2.ONE * lerpf(0.5, 3.2, smoothstep(0.0, 1.0, bu))
	var bloom_a := 1.0
	if u < 0.25:
		bloom_a = lerpf(0.0, 1.0, u / 0.25)
	else:
		bloom_a = lerpf(1.0, 0.0, smoothstep(0.25, 0.85, u))
	_gold_bloom.modulate = Color(1.0, 0.88, 0.4, bloom_a)

	# 3) Sunburst: hold bright longer, then fade
	_sunburst.rotation = u * PI * 0.55
	var ss := 1.0
	if u < 0.35:
		ss = lerpf(0.4, 2.8, smoothstep(0.0, 1.0, u / 0.35))
	else:
		ss = lerpf(2.8, 3.2, (u - 0.35) / 0.65)
	_sunburst.scale = Vector2.ONE * ss
	var sa := 1.0
	if u < 0.4:
		sa = lerpf(0.0, 1.0, u / 0.2)
		if u >= 0.2:
			sa = 1.0
	else:
		sa = lerpf(1.0, 0.0, smoothstep(0.4, 1.0, u))
	_sunburst.modulate = Color(1.0, 0.85, 0.35, sa)

	# 4) Twin light pillars (wide soft + bright core)
	var ps := 0.0
	if u < 0.12:
		ps = lerpf(0.0, 1.0, u / 0.12)
	elif u < 0.55:
		ps = 1.0
	else:
		ps = lerpf(1.0, 0.0, (u - 0.55) / 0.45)
	_pillar.scale = Vector2(lerpf(0.0, 3.2, ps), 1.3)
	_pillar.modulate = Color(1.0, 0.92, 0.55, ps)
	_pillar_wide.scale = Vector2(lerpf(0.0, 5.0, ps), 1.25)
	_pillar_wide.modulate = Color(1.0, 0.85, 0.35, ps * 0.85)

	# 5) Expanding rings (4 staggered, brighter gold)
	for i in _rings.size():
		var t0 := i * 0.09
		var ru := clampf((u - t0) / 0.5, 0.0, 1.0)
		_rings[i].scale = Vector2.ONE * lerpf(0.15, 3.1, ru)
		_rings[i].modulate = Color(1.0, 0.85, 0.35, lerpf(1.0, 0.0, ru))

	# 6) Hero gold aura / rim
	var ha := 0.0
	if u < 0.15:
		ha = lerpf(0.0, 0.95, u / 0.15)
	elif u < 0.65:
		ha = lerpf(0.95, 0.55, (u - 0.15) / 0.5)
	else:
		ha = lerpf(0.55, 0.0, (u - 0.65) / 0.35)
	_hero_aura.modulate = Color(1.0, 0.85, 0.35, ha)
	_hero_aura.scale = Vector2(1.6, 1.8) * (1.0 + 0.08 * sin(u * PI * 6.0))
	_hero.position = Vector2(0, lerpf(-16, -4, u))
	# warm gold tint that settles back to white
	var tint := 1.0 if u > 0.7 else lerpf(1.0, 0.0, u / 0.7)
	_hero.modulate = Color(1.0, lerpf(0.92, 1.0, tint), lerpf(0.65, 1.0, tint), 1.0)

	# 7) Banner pop with glow punch
	var tu := clampf((u - 0.12) / 0.28, 0.0, 1.0)
	if tu > 0.0:
		var s := _elastic(tu) * 1.0
		_title.scale = Vector2(s, s)
		_title.modulate = Color.WHITE
		# glow peaks with pop then softens
		var ga := 0.0
		if tu < 0.4:
			ga = lerpf(0.0, 1.0, tu / 0.4)
		else:
			ga = lerpf(1.0, 0.35, (tu - 0.4) / 0.6)
		if u > 0.75:
			ga = lerpf(ga, 0.0, (u - 0.75) / 0.25)
		_banner_glow.modulate = Color(1.0, 0.88, 0.4, ga)
		_banner_glow.scale = Vector2(1.7, 1.4) * lerpf(0.8, 1.15, ga)

	# particles: keep rising longer, stop burst mid-way
	if u > 0.45 and _gold.emitting:
		_gold.emitting = false
	if u > 0.92 and _rising.emitting:
		_rising.emitting = false
	# clear leftover storm
	for c in _clouds.get_children():
		(c as CanvasItem).modulate.a = lerpf((c as CanvasItem).modulate.a, 0.0, 0.2)
	_sky_glow.modulate.a = lerpf(_sky_glow.modulate.a, 0.0, 0.15)

var _success_started := false
func _start_success_burst() -> void:
	if _success_started:
		return
	_success_started = true
	# Stronger gold screen flash
	_flash.color = Color(1.0, 0.92, 0.55, 0.78)
	_flash_spr.modulate = Color(1.0, 0.95, 0.7, 1.0)
	_flash_spr.scale = Vector2(1.2, 1.2)
	_gold_bloom.modulate = Color(1.0, 0.92, 0.55, 0.9)
	_gold_bloom.scale = Vector2(0.5, 0.5)
	_sunburst.modulate = Color(1.0, 0.88, 0.45, 0.0)
	_pillar.modulate = Color(1.0, 0.95, 0.7, 0.0)
	_pillar.scale = Vector2(0.0, 1.2)
	_pillar_wide.modulate = Color(1.0, 0.88, 0.45, 0.0)
	_pillar_wide.scale = Vector2(0.0, 1.15)
	_hero_aura.modulate = Color(1.0, 0.88, 0.45, 0.0)
	_gold.restart()
	_gold.emitting = true
	_rising.restart()
	_rising.emitting = true
	_sparks.position = Vector2(0, -200)
	_sparks.restart()
	_sparks.emitting = true
	_add_shake(18.0)

func _do_strike(idx: int, is_final: bool, heavy: bool) -> void:
	strike.emit(idx)
	var bolts := _bolts.get_children()
	if bolts.is_empty():
		return
	var bolt: Sprite2D = bolts[idx % bolts.size()]
	# position around / near hero
	var side := -1.0 if (idx % 2 == 0) else 1.0
	var ox := side * _rng.randf_range(40.0, 160.0 if not is_final else 30.0)
	var oy := _rng.randf_range(-320.0, -160.0)
	if is_final:
		ox = _rng.randf_range(-20.0, 20.0)
		oy = -280.0
	bolt.position = Vector2(ox, oy)
	var sc := 1.85 if heavy else 1.45
	if is_final:
		sc = 2.4
	bolt.scale = Vector2(sc * (1.0 if side > 0 else -1.0) * _rng.randf_range(0.95, 1.2), sc * _rng.randf_range(1.0, 1.25))
	bolt.rotation = deg_to_rad(_rng.randf_range(-12, 12))
	bolt.modulate = Color(1, 1, 1, 1)
	# impact at foot of bolt
	var impact_pos := Vector2(ox * 0.55, -40.0 + _rng.randf_range(-20, 20))
	_impact.position = impact_pos
	_impact.scale = Vector2.ONE * (1.4 if is_final else (1.0 if heavy else 0.7))
	_impact.modulate = Color(1, 1, 1, 1)
	_strike_glow.position = impact_pos + Vector2(0, -40)
	_strike_glow.scale = Vector2.ONE * (2.8 if is_final else 1.8)
	_strike_glow.modulate = Color(0.75, 0.85, 1.0, 0.95)
	# particles
	_sparks.position = impact_pos
	_sparks.restart()
	_sparks.emitting = true
	if heavy or is_final:
		_embers.position = impact_pos
		_embers.restart()
		_embers.emitting = true
	# screen flash
	var fa := 0.7 if is_final else (0.45 if heavy else 0.28)
	_flash.color = Color(0.85, 0.9, 1.0, fa)
	_add_shake(14.0 if is_final else (9.0 if heavy else 5.0))
	# schedule fade via meta timestamp
	bolt.set_meta("fade_t", _t)
	_impact.set_meta("fade_t", _t)
	_strike_glow.set_meta("fade_t", _t)
	# hero flinch
	_hero.position = Vector2(-side * (8 if heavy else 4), -6)

func _update_shake(delta: float) -> void:
	# fade screen flash
	if _flash.color.a > 0.0:
		_set_a(_flash, maxf(0.0, _flash.color.a - delta * 2.8))
	# fade bolts / impact
	for b in _bolts.get_children():
		var spr: Sprite2D = b
		if spr.modulate.a <= 0.0:
			continue
		var age := _t - float(spr.get_meta("fade_t", _t))
		var life := 0.55
		spr.modulate.a = clampf(1.0 - age / life, 0.0, 1.0)
	if _impact.modulate.a > 0.0:
		var age2 := _t - float(_impact.get_meta("fade_t", _t))
		_impact.modulate.a = clampf(1.0 - age2 / 0.5, 0.0, 1.0)
		_impact.scale = Vector2.ONE * lerpf(_impact.scale.x, _impact.scale.x * 1.4, delta * 4.0)
	if _strike_glow.modulate.a > 0.0:
		var age3 := _t - float(_strike_glow.get_meta("fade_t", _t))
		_strike_glow.modulate.a = clampf(0.95 - age3 / 0.55, 0.0, 1.0)
	# shake decay
	if _shake_amp > 0.05:
		_shake_amp = lerpf(_shake_amp, 0.0, 1.0 - exp(-delta * 8.0))
		_shake = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake_amp * shake_mul
		_world.position = _shake
	elif _world.position != Vector2.ZERO:
		_world.position = Vector2.ZERO
		_shake_amp = 0.0

func _set_a(rect: ColorRect, a: float) -> void:
	if rect == null:
		return
	var c := rect.color
	c.a = a
	rect.color = c

func _add_shake(amp: float) -> void:
	_shake_amp = maxf(_shake_amp, amp)

func _elastic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t >= 1.0:
		return 1.0
	return 1.0 + exp(-5.5 * t) * sin((t * 5.5 - 0.75) * PI * 2.0) * 0.35

func smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
