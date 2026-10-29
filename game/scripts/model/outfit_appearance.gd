class_name OutfitAppearance
extends RefCounted
## 换装 v1：按品质换整张图。没下发 appearance，或图还没导入时，调用方继续用现默认立绘 / 头像。

const _FIELDS := {
	"preview": "previewKey",
	"meditate": "meditateKey",
	"avatar": "avatarKey",
	"avatar_round": "avatarRoundKey",
}
const _SNAKE := {
	"previewKey": "preview_key",
	"meditateKey": "meditate_key",
	"avatarKey": "avatar_key",
	"avatarRoundKey": "avatar_round_key",
}
const _FOLDERS := {
	"preview": "outfit/",
	"meditate": "outfit/meditate/",
	"avatar": "outfit/avatar/",
	"avatar_round": "outfit/avatar/",
}


static func key_of(appearance: Variant, slot: String) -> String:
	if typeof(appearance) != TYPE_DICTIONARY:
		return ""
	var field := str(_FIELDS.get(slot, ""))
	if field.is_empty():
		return ""
	var data := appearance as Dictionary
	return str(data.get(field, data.get(str(_SNAKE.get(field, "")), ""))).strip_edges()


static func texture(appearance: Variant, slot: String) -> Texture2D:
	var key := key_of(appearance, slot)
	if key.is_empty():
		return null
	var relative := str(_FOLDERS.get(slot, "")) + key
	if not ArtLib.has_q(relative + ".png"):
		return null
	return ArtLib.q(relative)
