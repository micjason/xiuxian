extends Node2D
## 技能特效薄封装。四套场景在本目录；可扩展枚举缺独立资源时回落到这四套。
## spawn / play_once：技能事件到了直接 play，不要等按钮，也不要平移整个人。

const SCENE_DIR := "res://anim_q/skill_fx/"

## 已随包提供的场景。以后加 ice_fx.tscn 等，只要文件在，就会直接播，不再走 FALLBACK。
const SCENE := {
	"slash": SCENE_DIR + "slash_fx.tscn",
	"thunder": SCENE_DIR + "thunder_fx.tscn",
	"fire": SCENE_DIR + "fire_fx.tscn",
	"heal_circle": SCENE_DIR + "heal_circle_fx.tscn",
}

## 可以写进 content_skills.fx_type 的类型。未知字符串在 normalize_kind 里变成 slash。
const STORED := ["slash", "thunder", "fire", "heal_circle", "ice", "wind", "poison", "gold_light", "shield"]

## 客户端还没有独立场景时的播放回落。有同名 *_fx.tscn 之后 resolve_kind 不再使用这里。
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
}


## 存档 / 配置用的规范类型。中英别名收成英文；不认识的收成 slash。
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
		"冰", "ice":
			return "ice"
		"风", "wind":
			return "wind"
		"毒", "poison":
			return "poison"
		"金", "金光", "gold", "gold_light":
			return "gold_light"
		"盾", "护盾", "shield":
			return "shield"
		_:
			return key if key in STORED else "slash"


## 真正要实例化的类型。有独立场景就播自己，否则 FALLBACK，再不行用斩击。
static func resolve_kind(kind: String) -> String:
	var stored := normalize_kind(kind)
	if _has_scene(stored):
		return stored
	var fb := str(FALLBACK.get(stored, ""))
	if fb != "" and _has_scene(fb):
		return fb
	return "slash"


static func scene_path(kind: String) -> String:
	var playable := resolve_kind(kind)
	return str(SCENE.get(playable, SCENE_DIR + playable + "_fx.tscn"))


static func colors_for(kind: String) -> Array:
	var key := kind.strip_edges().to_lower()
	if key in ["攻击法阵", "attack_circle"]:
		return DEFAULTS["attack_circle"]
	var stored := normalize_kind(kind)
	if DEFAULTS.has(stored):
		return DEFAULTS[stored]
	var playable := resolve_kind(kind)
	if DEFAULTS.has(playable):
		return DEFAULTS[playable]
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
	var playable := resolve_kind(kind)
	var path := scene_path(kind)
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
	var colors: Array = colors_for(kind)
	if "primary_color" in n:
		n.primary_color = colors[0]
	if "secondary_color" in n:
		n.secondary_color = colors[1]
	if kind.strip_edges().to_lower() in ["攻击法阵", "attack_circle"] and "show_pillar" in n:
		n.show_pillar = true
	if playable == "fire" and "heavy" in n:
		n.heavy = true
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


static func _has_scene(stored: String) -> bool:
	if SCENE.has(stored):
		return true
	return ResourceLoader.exists(SCENE_DIR + stored + "_fx.tscn")
