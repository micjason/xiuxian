extends Node2D
## 通用怪物模板：任意一张 mon_*.png 都能用（不需要拆层）。
## 节点原点 = 怪物显示框的中心（与历练页原来 TextureRect 的框一致，图片等比缩放后居中）。
## 动作：spawn() 刷出 / idle 待机（自动）/ hit() 受击 / attack() 扑向主角 / die() 溶解消失。
## 所有动作都是在 _process 里按时间计算，不创建新节点、不用 Tween，没有每帧内存分配。
## tier（档次）：NORMAL 普通怪 / ELITE 精英（每关首领：放大 1.2 + 金描边金光 + 脚下金光圈 +「★精英」名牌）/
## CHIEF 章末大首领（原尺寸 + 红描边红光 + 火焰光圈 +「首领」红名牌 + 红冠角标）。参数见 SPEC_Q §14。
## 精英 / 首领换用 monster_tier.gdshader（美术描边 shader + 闪白 + 溶解合成一个），任意 mon_*.png 自动生效。

signal spawned
signal attack_impact
signal died

const P_FLASH := &"flash"
const P_DISSOLVE := &"dissolve"
enum { HIDDEN, SPAWNING, ALIVE, DYING }
enum Tier { NORMAL, ELITE, CHIEF }

const TIER_SHADER := preload("res://anim_q/battle_idle/monster_tier.gdshader")
const AURA_ELITE := preload("res://anim_q/battle_idle/art/boss_aura_elite.png")
const AURA_CHIEF := preload("res://anim_q/battle_idle/art/boss_aura_chief.png")
const AURA_ELITE_CHIYAN := preload("res://anim_q/battle_idle/art/boss_aura_elite_chiyan.png")
const AURA_CHIEF_CHIYAN := preload("res://anim_q/battle_idle/art/boss_aura_chief_chiyan.png")
const PLATE_ELITE := preload("res://anim_q/battle_idle/art/plate_elite.png")
const PLATE_CHIEF := preload("res://anim_q/battle_idle/art/plate_chief.png")
## SPEC_Q §14.2 / §14.4。px = 贴图按 1:1 显示时的像素，_fit() 里按实际缩放换算。
const TIER_SPEC := {
	Tier.ELITE: {"scale": 1.2, "outline_top": Color("#FFF6B8"), "outline_color": Color("#FFC93C"), "edge_color": Color("#B86E10"),
		"glow_color": Color(1.0, 0.878, 0.29, 0.9), "outline_px": 5.8, "edge_px": 1.7, "glow_px": 20.0, "pad_px": 40.0,
		"aura_w": 1.15, "plate_scale": 0.9},
	Tier.CHIEF: {"scale": 1.0, "outline_top": Color("#FFD08A"), "outline_color": Color("#FF4B3A"), "edge_color": Color("#8E2420"),
		"glow_color": Color(1.0, 0.29, 0.188, 0.95), "outline_px": 7.0, "edge_px": 2.0, "glow_px": 32.0, "pad_px": 56.0,
		"aura_w": 1.35, "plate_scale": 0.9},
}

## 按章节换的首领特效（服务端 chapters[].bossFx，SPEC_Q §14.7）：只改描边 / 外光参数和光圈贴图，shader 不变。
## chiyan = 赤炎火山（红黄背景）：金 / 红环外加深棕描边、大首领光改白金；预渲染图用 *_chiyan.png（没有就走实时 shader，不用默认配色的预渲染图）。
const FX_VARIANTS := {
	"default": {},
	"chiyan": {
		Tier.ELITE: {"outline_top": Color("#FFFFFF"), "outline_color": Color("#FFD23C"), "edge_color": Color("#3A1E14"),
			"glow_color": Color(1.0, 0.965, 0.784, 1.0), "outline_px": 5.8, "edge_px": 2.9, "glow_px": 18.3, "pad_px": 40.0},
		Tier.CHIEF: {"outline_top": Color("#FFFFFF"), "outline_color": Color("#FFE04A"), "edge_color": Color("#3A1E14"),
			"glow_color": Color(1.0, 0.984, 0.902, 1.0), "outline_px": 7.0, "edge_px": 4.0, "glow_px": 34.0, "pad_px": 56.0},
	},
}

## 显示框大小（像素）。历练页目标怪 = 340×370。
@export var box := Vector2(340, 370)
## 朝向：主角在左边，怪物要面朝左。
@export var face_left_flip := true
@export var bob_height := 5.0
## 击退方向（+x = 往右，远离左边的主角）
@export var knock_dir := 1.0
## 档次：普通 / 精英 / 章末首领。运行中改也可以（换材质、光圈、名牌）。
@export var tier: Tier = Tier.NORMAL:
	set(v):
		tier = v
		if is_node_ready():
			_apply_tier()
## 章节首领特效 key（default / chiyan）。不认识的 key 报错并按 default 显示（服务端发布校验只允许这两个）。
@export var fx_variant := "default":
	set(v):
		if not FX_VARIANTS.has(v):
			push_error("未知的首领特效 bossFx：%s" % v)
		fx_variant = v
		if is_node_ready():
			_apply_tier()
## 名牌底边离怪物头顶（不透明部分的最高处）的距离；页面在怪物头顶画血条时，改成血条上方 8px 的位置。
@export var plate_gap := 10.0
## 不要名牌（例如列表里的小图）
@export var show_plate := true
## 精英 / 首领描边的来源：true = 同目录下有美术预渲染图（mon_X.png 旁边的 elite_X.png / chief_X.png，SPEC §14.3）
## 就用预渲染图（最省：普通着色器，没有 16 方向采样），没有才用实时描边 shader；false = 一律实时 shader（SPEC §14.2 首选）。
@export var use_baked_outline := true:
	set(v):
		use_baked_outline = v
		if is_node_ready():
			_apply_tier()

@onready var _body: Node2D = $Body
@onready var _spr: Sprite2D = $Body/Sprite
@onready var _shadow: Sprite2D = $Shadow
@onready var _aura: Sprite2D = $Aura
@onready var _plate: Node2D = $Plate
@onready var _plate_spr: Sprite2D = $Plate/Tag
@onready var _badge: Sprite2D = $Plate/Badge
var _mat: ShaderMaterial
var _mat_normal: ShaderMaterial
var _mat_tier: ShaderMaterial
var _tier_scale := 1.0
var _aura_base := 1.0
var _aura_y := 0.0
var _plate_y := 0.0
## 每张贴图不透明部分的范围（只算一次）
static var _used_cache := {}
var _used := Rect2()
var _src_tex: Texture2D        # 原图 mon_*.png（页面给的）
var _baked: Texture2D          # 正在用的预渲染图（没有 = null）
var _baked_pad := 0.0          # 预渲染图四周留白（精英 44 / 首领 56）
var _baked_k := 1.0            # 预渲染图相对原图的放大（精英 1.2 / 首领 1.0）
var _baked_unified := false    # 用的是 boss_*.png（统一首领图）

var state := HIDDEN
var _t := 0.0
var _st := 0.0          # 当前状态已经过的时间
var _flash := 0.0
var _knock := 0.0
var _squash := 0.0
var _lunge := -1.0
var _lunge_hit := false
var _disp_h := 0.0
var _feet_y := 0.0
var _shadow_base := Vector2.ONE
var _last_flash := -1.0
var _last_dis := -1.0


func _ready() -> void:
	_mat_normal = _spr.material as ShaderMaterial
	_mat = _mat_normal
	_shadow_base = _shadow.scale
	_apply_tier()
	visible = false


## 换怪物图。flip = 是否水平翻转（历练页用 ArtLib.monster_needs_flip）。
func texture() -> Texture2D:
	return _src_tex


## 正在用预渲染描边图（true）还是实时 shader / 普通怪（false）
func is_baked() -> bool:
	return _baked != null


func set_texture(tex: Texture2D, flip: bool) -> void:
	_src_tex = tex
	_spr.flip_h = flip
	_apply_tier()


## mon_fox.png → 同目录的预渲染图；没有返回 null。
## 首领：优先 boss_fox.png（SPEC_Q §17.10 统一首领图，已按章节配色烘焙；第 1、2 关 = 小怪 ×1.2，第 3 关 = ×1.0，四周留白 56），
## 没有再找旧的 chief_fox(_chiyan).png。精英（已不再使用）：elite_fox(_chiyan).png。
func _find_baked(tex: Texture2D) -> Texture2D:
	_baked_unified = false
	if tex == null or tier == Tier.NORMAL or not use_baked_outline:
		return null
	var path := tex.resource_path
	var file := path.get_file()
	# 页面直接给统一首领立绘 boss_<怪>.png（本身就是预渲染好的首领描边图，SPEC_Q §17.10）：直接用
	if file.begins_with("boss_"):
		return tex
	if not file.begins_with("mon_"):
		return null
	if tier == Tier.CHIEF:
		var unified := path.get_base_dir().path_join("boss_" + file.trim_prefix("mon_"))
		if ResourceLoader.exists(unified):
			_baked_unified = true
			return load(unified) as Texture2D
	var base := ("elite_" if tier == Tier.ELITE else "chief_") + file.trim_prefix("mon_").get_basename()
	if fx_variant != "default":
		base += "_" + fx_variant
	var alt := path.get_base_dir().path_join(base + ".png")
	return load(alt) as Texture2D if ResourceLoader.exists(alt) else null


## 当前档次 + 章节特效的参数（TIER_SPEC 上叠 FX_VARIANTS）。普通怪返回空字典。
func _spec() -> Dictionary:
	var base: Dictionary = TIER_SPEC.get(tier, {})
	if base.is_empty():
		return base
	var over: Dictionary = (FX_VARIANTS.get(fx_variant, {}) as Dictionary).get(tier, {})
	if over.is_empty():
		return base
	var merged := base.duplicate()
	merged.merge(over, true)
	return merged


## 精英 / 首领：换材质、开光圈和名牌。普通怪恢复原来的 monster_fx 材质。
func _apply_tier() -> void:
	var spec := _spec()
	_tier_scale = float(spec.get("scale", 1.0))
	if spec.is_empty():
		_mat = _mat_normal
		_shadow.visible = true
		_aura.visible = false
		_plate.visible = false
	else:
		if _mat_tier == null:
			_mat_tier = ShaderMaterial.new()
			_mat_tier.shader = TIER_SHADER
			_mat_tier.set_shader_parameter(&"noise_tex", _mat_normal.get_shader_parameter(&"noise_tex"))
		for k in ["outline_top", "outline_color", "edge_color", "glow_color"]:
			_mat_tier.set_shader_parameter(k, spec[k])
		_mat = _mat_tier
		_shadow.visible = false
		_aura.visible = true
		var chiyan := fx_variant == "chiyan"
		if tier == Tier.ELITE:
			_aura.texture = AURA_ELITE_CHIYAN if chiyan else AURA_ELITE
		else:
			_aura.texture = AURA_CHIEF_CHIYAN if chiyan else AURA_CHIEF
		_plate.visible = show_plate
		_plate_spr.texture = PLATE_ELITE if tier == Tier.ELITE else PLATE_CHIEF
		_badge.visible = tier == Tier.CHIEF
		_plate.scale = Vector2.ONE * float(spec.plate_scale)
	_baked = _find_baked(_src_tex)
	_baked_pad = 0.0
	_baked_k = 1.0
	if _baked != null:
		# 预渲染图已经带描边和外光：用普通的闪白 / 溶解着色器
		_mat = _mat_normal
		_baked_pad = 44.0 if tier == Tier.ELITE else 56.0
		_baked_k = _tier_scale
		if _baked_unified and _src_tex != null and _src_tex.get_height() > 0:
			# boss_*.png 的放大倍数按尺寸反推（1.2 或 1.0）
			_baked_k = (float(_baked.get_height()) - _baked_pad * 2.0) / float(_src_tex.get_height())
	_spr.texture = _baked if _baked != null else _src_tex
	_spr.material = _mat
	_last_flash = -1.0
	_last_dis = -1.0
	if _spr.texture != null:
		_fit()


func is_elite() -> bool:
	return tier == Tier.ELITE


func _used_rect(tex: Texture2D) -> Rect2:
	var key := tex.get_rid()
	if _used_cache.has(key):
		return _used_cache[key]
	var r := Rect2(Vector2.ZERO, tex.get_size())
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var u := img.get_used_rect()
		if u.size.x > 0:
			r = Rect2(u)
	_used_cache[key] = r
	return r


func _fit() -> void:
	var tex := _spr.texture
	if tex == null:
		return
	var sz := tex.get_size()
	# 按原图（mon_*.png）大小贴合显示框；预渲染图 = 原图 × k + 四周留白 pad
	var src_sz := sz if _baked == null else (sz - Vector2.ONE * _baked_pad * 2.0) / _baked_k
	var fit := minf(box.x / src_sz.x, box.y / src_sz.y)
	var s := fit * _tier_scale if _baked == null else fit
	_used = _used_rect(tex) if tier != Tier.NORMAL else Rect2(Vector2.ZERO, sz)
	_disp_h = sz.y * s
	# 脚底 = 按原框贴合时的原图底边；放大后脚底不动，整只往上长
	_feet_y = src_sz.y * fit * 0.5
	_spr.scale = Vector2(s, s)
	# 预渲染图：脚底 = 图底往上 pad（SPEC §14.3）
	_spr.position = Vector2(0, -_disp_h * 0.5 + _baked_pad * s * (1.0 if _baked != null else 0.0))
	_body.position = Vector2(0, _feet_y)
	_shadow.position = Vector2(0, _feet_y - 4)
	_shadow_base = Vector2(sz.x * s / 128.0 * 0.95, 1.0)
	var spec := _spec()
	if not spec.is_empty():
		# 屏幕上的描边粗细 = SPEC 数值 × 档次缩放（贴图 1:1 时的效果），所以除以贴合缩放
		var vis_w := _used.size.x * s
		var feet := _feet_y - (sz.y - _used.end.y) * s
		var top := _feet_y - _disp_h + _used.position.y * s
		if _baked == null:
			for k in ["outline_px", "edge_px", "glow_px", "pad_px"]:
				_mat_tier.set_shader_parameter(k, float(spec[k]) / fit)
		else:
			# 预渲染图的不透明范围含外光：宽度扣掉留白，脚底按 SPEC 的「图底往上 pad」
			vis_w = (_used.size.x - _baked_pad * 2.0 * 0.6) * s
			feet = _feet_y
			top = _feet_y - (sz.y - _baked_pad - _used.position.y) * s + _baked_pad * 0.4 * s
		_aura_y = feet + 10.0
		_aura_base = vis_w * float(spec.aura_w) / float(_aura.texture.get_width())
		_aura.position = Vector2(0, _aura_y)
		_aura.scale = Vector2.ONE * _aura_base
		var ph := float(_plate_spr.texture.get_height()) * _plate.scale.y
		_plate_y = top - plate_gap - ph * 0.5
		_plate.position = Vector2(0, _plate_y)
		var pw := float(_plate_spr.texture.get_width())
		var tph := float(_plate_spr.texture.get_height())
		# 红冠：左上角 = 名牌右上角 + (34-72, -40)（SPEC §14.4，显示 72×63）
		_badge.position = Vector2(pw * 0.5 - 38.0 + 36.0, -tph * 0.5 - 40.0 + 31.5)


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
	_body.position = Vector2(ox, _feet_y + oy)
	_body.scale = Vector2(sx, sy)
	_spr.modulate.a = alpha
	_shadow.scale = _shadow_base * (1.0 - (bob + bob_height) * 0.012) * (1.0 - dis * 0.6)
	_shadow.modulate.a = alpha * (1.0 - dis)
	if tier != Tier.NORMAL:
		# 光圈留在地上（只跟着左右动、1.6 秒呼吸），名牌跟着身体
		var br := 1.0 + 0.04 * sin(_t * TAU / 1.6)
		_aura.position = Vector2(ox, _aura_y)
		_aura.scale = Vector2.ONE * _aura_base * br * (1.0 - dis * 0.3)
		_aura.modulate.a = alpha * (1.0 - dis)
		_plate.position = Vector2(ox, _plate_y + oy)
		_plate.modulate.a = alpha * (1.0 - dis)
	_set_params(_flash, dis)


static func _back_out(x: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)
