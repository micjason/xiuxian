class_name LockedFeature
extends RefCounted
## 「功能暂未开放」：设计稿里画了、但这一期还没有的功能（邮件、广告双倍、炼丹、还没有的货币、洞府建筑……）
## 照设计显示，点了统一弹这一句提示（成鹏 10-20 的要求：显示，不隐藏）。
## 用法：LockedFeature.wire(button, "mail")；或者在任意节点里 LockedFeature.notify(self, "mail")。
## 提示由加入 GROUP 组的 Toast 显示；没有 Toast（比如单独测试一个页面）时只记录，不报错。

const TEXT := "功能暂未开放"
const GROUP := &"locked_feature_toast"
const META := &"locked_feature"

## 最近一次被点的功能 id 和累计次数（测试用）。
static var last_feature := ""
static var count := 0


static func notify(from: Node, feature: String = "") -> void:
	last_feature = feature
	count += 1
	if from != null and from.is_inside_tree():
		from.get_tree().call_group(GROUP, "say_locked", feature)


## 把按钮标记为“暂未开放”：点了只弹提示，不做别的。返回同一个按钮方便链式写。
static func wire(button: BaseButton, feature: String) -> BaseButton:
	button.set_meta(META, feature)
	button.pressed.connect(func() -> void: notify(button, feature))
	return button


static func is_locked(node: Node) -> bool:
	return node != null and node.has_meta(META)


## 页面里所有“暂未开放”的按钮（测试和截图核对用）。
static func locked_buttons(root: Node, out: Array[BaseButton] = []) -> Array[BaseButton]:
	if root is BaseButton and is_locked(root):
		out.append(root as BaseButton)
	for child in root.get_children():
		locked_buttons(child, out)
	return out
