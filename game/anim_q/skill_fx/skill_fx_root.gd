extends Node2D
## 技能特效薄封装。九套场景都在本目录，真名直接播自己的场景。
## spawn / play_once：技能事件到了直接 play，不要等按钮，也不要平移整个人。
## gold / 金 / 金光 都收成 gold_light。缺场景时才走 FALLBACK。

const SCENE_DIR := "res://anim_q/skill_fx/"
const STORED := ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]

## 只有对应 *_fx.tscn 不存在时才用。九套齐全时 resolve_kind 不会走到这里。
const FALLBACK := {
	"ice": "thunder",
	"wind": "slash",
	"poison": "fire",
	"gold_light": "slash",
	"shield": "heal_circle",
}

const DEFAULTS := {
	"slash": [Color("F5FBFF"), Color("A8E8E0")],
	"thunder": [Color("E8D6FF"), Color("7B4DFF")],
	"fire": [Color("FF9F43"), Color("FF5A5F")],
	"heal_circle": [Color("5EE1C5"), Color("FFE27A")],
	"attack_circle": [Color("FFD45C"), Color("5AAEFF")],
	"ice": [Color("D6F3FF"), Color("7EC8FF")],
	"wind": [Color("C8FFE8"), Color("3DDC97")],
	"poison": [Color("B8FF6A"), Color("7A4DFF")],
	"gold_light": [Color("FFF2C8"), Color("FFD45C")],
	"shield": [Color("A8E8E0"), Color("FFD45C")],
}


## 存档 / 配置用的规范类型。不认识的收成 slash。
static func normalize_kind(kind: String) -> String:
	var key := kind.strip_edges().to_lower()
	match key:
		"斩击", "刀光", "slash":
			return "slash"
		"雷", "闪电", "thunder", "lightning":
			return "thunder"
		"火", "fire":
			return "fire"
		"治疗", "治疗法阵", "heal", "heal_circle", "法阵":
			return "heal_circle"
		"攻击法阵", "attack_circle":
			return "heal_circle"
		"冰", "ice", "frost":
			return "ice"
		"风", "wind":
			return "wind"
		"毒", "poison":
			return "poison"
		"金", "金光", "gold", "gold_light", "holy":
			return "gold_light"
		"盾", "护盾", "shield", "barrier":
			return "shield"
		_:
			return key if key in STORED else "slash"


## 缺文件时的兜底名。九套都在时，播放不要用这个结果。
static func fallback_kind(stored: String) -> String:
	return str(FALLBACK.get(stored, "slash"))


static func scene_file(stored: String) -> String:
	return SCENE_DIR + stored + "_fx.tscn"


static func has_scene(stored: String) -> bool:
	return ResourceLoader.exists(scene_file(stored))


## 真正要实例化的类型。有独立场景就播自己，否则才 fallback。
static func resolve_kind(kind: String) -> String:
	var stored := normalize_kind(kind)
	if has_scene(stored):
		return stored
	var fb := fallback_kind(stored)
	if fb != stored and has_scene(fb):
		return fb
	if has_scene("slash"):
		return "slash"
	return stored


static func scene_path(kind: String) -> String:
	return scene_file(resolve_kind(kind))


static func colors_for(kind: String) -> Array:
	var key := kind.strip_edges().to_lower()
	if key in ["攻击法阵", "attack_circle"]:
		return DEFAULTS["attack_circle"]
	var stored := normalize_kind(kind)
	var playable := resolve_kind(kind)
	var color_key := stored if playable == stored and DEFAULTS.has(stored) else playable
	if DEFAULTS.has(color_key):
		return DEFAULTS[color_key]
	return DEFAULTS["slash"]


static func color_from(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value).strip_edges()
	if text.is_empty():
		return fallback
	if not text.begins_with("#"):
		text = "#" + text
	return Color.html(text) if text.is_valid_html_color() else fallback


static func spawn(kind: String, parent: Node, at: Vector2 = Vector2.ZERO, scale_mul: float = 1.0) -> Node2D:
	if parent == null:
		push_warning("skill_fx_root: missing parent")
		return null
	var stored := normalize_kind(kind)
	var playable := resolve_kind(kind)
	var path := scene_file(playable)
	if not ResourceLoader.exists(path):
		push_warning("skill_fx_root: missing %s" % path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("skill_fx_root: missing %s" % path)
		return null
	var n := packed.instantiate() as Node2D
	parent.add_child(n)
	n.position = at
	if "fx_scale" in n:
		n.fx_scale = scale_mul if scale_mul > 0.0 else 1.0
	var token := kind.strip_edges().to_lower()
	var colors: Array = colors_for(kind)
	if "primary_color" in n:
		n.primary_color = colors[0]
	if "secondary_color" in n:
		n.secondary_color = colors[1]
	if token in ["攻击法阵", "attack_circle"] and "show_pillar" in n:
		n.show_pillar = true
	if playable == "fire" and "heavy" in n:
		n.heavy = true
	if stored != playable:
		n.set_meta("fx_fallback_from", stored)
	return n


static func play_once(kind: String, parent: Node, at: Vector2 = Vector2.ZERO, scale_mul: float = 1.0) -> Node2D:
	var n := spawn(kind, parent, at, scale_mul)
	if n == null:
		return null
	if n.has_signal("finished"):
		n.finished.connect(n.queue_free, CONNECT_ONE_SHOT)
	if n.has_method("play"):
		n.play()
	return n
