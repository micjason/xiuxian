class_name BagFullPrompt
extends RefCounted
## 背包已满提示（设计稿 10 的样式，屏幕正中的小弹窗）。负责人决定（2026-10-16）：背包满不再拦挑战；
## 挑战结果里有装备因满包没掉落（bagFull）时弹出：「背包已满（20/20）」「新掉落的装备没能入包」。
## 另给一个「去背包」按钮直达分解（稿里没有，是为了少点一步，见改动说明）。


static func texts(used: int, capacity: int) -> Array[String]:
	# 首通固定奖励可以超出容量，显示时不超过上限（23/20 读起来像 bug）
	return ["背包已满（%d/%d）" % [mini(used, capacity), capacity], "新掉落的装备没能入包"]


static func show_prompt(popup: GamePopup, used: int, capacity: int, on_open_bag: Callable = Callable()) -> void:
	popup.clear_content()
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 150)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bag := UiKit.icon("res_bag", 120, UiTokens.GOLD_HOVER)
	bag.set_anchors_preset(Control.PRESET_CENTER)
	bag.offset_left = -60
	bag.offset_right = 60
	bag.offset_top = -60
	bag.offset_bottom = 60
	holder.add_child(bag)
	var dot := UiKit.reddot()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = 30
	dot.offset_right = 70
	dot.offset_top = -70
	dot.offset_bottom = -30
	holder.add_child(dot)
	popup.body.add_child(holder)
	var lines := texts(used, capacity)
	var first := UiKit.label(lines[0], UiTokens.FS_H2, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	first.name = "FullTitle"
	popup.body.add_child(first)
	var second := UiKit.label(lines[1], UiTokens.FS_BODY, UiTokens.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	second.name = "FullHint"
	popup.body.add_child(second)
	var buttons: Array = [{"text": "确定", "variation": MainTheme.VAR_PRIMARY}]
	if on_open_bag.is_valid():
		buttons.push_front({"text": "去背包", "variation": MainTheme.VAR_SECONDARY, "callback": on_open_bag})
	popup.set_actions(buttons)
	popup.open_popup("提示", true)
