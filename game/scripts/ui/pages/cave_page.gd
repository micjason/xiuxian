class_name CavePage
extends VBoxContainer
## 洞府 v1：总览三卡（药园 / 炼丹 / 强化）+ 药园/炼丹子页。
## 数据来自 CaveView.build(state, content)；写操作发 action_requested，由 PlayScreen 调接口。
## 强化第三卡只发 enhance_entry_requested（接线归独立开发超级大师 open_enhance_entry）。

signal back_requested
signal enhance_entry_requested
## kind: garden_plant / garden_claim / alchemy_start / alchemy_claim / toast
## payload: 对应接口字段；toast 时 payload.text 为文案。
signal action_requested(kind: String, payload: Dictionary)

const MODE_OVERVIEW := "overview"
const MODE_GARDEN := "garden"
const MODE_ALCHEMY := "alchemy"

var _mode := MODE_OVERVIEW
var _view: Dictionary = {}
var _plant_slot := -1  ## >=0 时药园子页显示选种条
var _bind_sig := 0
var _title: Label
var _back: Button
var _body: VBoxContainer
var _sheet: PanelContainer

func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_chrome()
	_sheet = QKit.panel(UiTokens.Q_CREAM, 34, 22, 18).panel
	_sheet.name = "CaveSheet"
	_sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_sheet)
	var scroll := ScrollContainer.new()
	scroll.name = "CaveScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheet.add_child(scroll)
	_body = UiKit.vbox(16)
	_body.name = "CaveBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var orb := Control.new()
	orb.custom_minimum_size = Vector2(0, 96)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(orb)
	_render()


func _build_chrome() -> void:
	var head := UiKit.hbox(12)
	head.name = "CaveHeader"
	add_child(head)
	_back = QKit.button("返回", "m", 72, 36)
	_back.name = "BackButton"
	_back.custom_minimum_size = Vector2(160, 72)
	_back.pressed.connect(_on_back)
	head.add_child(_back)
	_title = QKit.title("洞府", 46, UiTokens.TEXT)
	_title.name = "CaveTitle"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)


func sheet_anchor() -> Control:
	return _sheet


func sheet_pad() -> float:
	return 8.0


func mode() -> String:
	return _mode


func view() -> Dictionary:
	return _view


func bind(state: Dictionary, content: Dictionary) -> void:
	_view = CaveView.build(state, content)
	var sig := hash([_view, _mode, _plant_slot])
	if sig == _bind_sig:
		return
	_render()


func _on_back() -> void:
	if _mode == MODE_OVERVIEW:
		back_requested.emit()
		return
	_plant_slot = -1
	_mode = MODE_OVERVIEW
	_render()


func _render() -> void:
	_bind_sig = hash([_view, _mode, _plant_slot])
	match _mode:
		MODE_GARDEN:
			_title.text = "药园"
		MODE_ALCHEMY:
			_title.text = "炼丹"
		_:
			_title.text = "洞府"
	UiKit.clear(_body)
	if _mode == MODE_GARDEN:
		_render_garden()
	elif _mode == MODE_ALCHEMY:
		_render_alchemy()
	else:
		_render_overview()


func _render_overview() -> void:
	if not bool(_view.get("available", false)):
		var hint := UiKit.label(str(_view.get("hint", "洞府配置尚未发布")), UiTokens.FS_BODY, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(hint)
	else:
		_body.add_child(_allocation_panel())
		_body.add_child(_upgrade_row("garden"))
		_body.add_child(_upgrade_row("alchemy"))
	_body.add_child(UiKit.label("经营设施", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	for card in _view.get("cards", []):
		_body.add_child(_facility_card(card as Dictionary))


func _allocation_panel() -> Control:
	var box := UiKit.vbox(8)
	box.name = "ServantAllocation"
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	var garden := int(alloc.get("garden", 0))
	var alchemy := int(alloc.get("alchemy", 0))
	var total := int(_view.get("servantTotal", 0))
	var idle := maxi(0, total - garden - alchemy)
	var scale: Dictionary = _view.get("timeScale", {}) if typeof(_view.get("timeScale", {})) == TYPE_DICTIONARY else {}
	var garden_pct := int(round(float(scale.get("garden", 1.0)) * 100.0))
	var alchemy_pct := int(round(float(scale.get("alchemy", 1.0)) * 100.0))
	box.add_child(QKit.title("灵仆", 36, UiTokens.TEXT))
	box.add_child(UiKit.label("共 %d · 闲置 %d · %s ×%d" % [total, idle, str(_view.get("woodName", "灵木")), int(_view.get("woodCount", 0))], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	box.add_child(UiKit.label("成熟时长 %d%% · 炼制时长 %d%%" % [garden_pct, alchemy_pct], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	box.add_child(_alloc_row("药园", "garden", garden, idle))
	box.add_child(_alloc_row("炼丹", "alchemy", alchemy, idle))
	return box


func _alloc_row(title: String, key: String, value: int, idle: int) -> Control:
	var row := UiKit.hbox(10)
	var label := UiKit.label("%s %d" % [title, value], UiTokens.FS_BODY, UiTokens.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var minus := QKit.button("-", "m", 48, 32)
	minus.name = "AllocMinus_%s" % key
	minus.custom_minimum_size = Vector2(88, 72)
	minus.disabled = value <= 0
	minus.pressed.connect(func() -> void: _shift_allocation(key, -1))
	row.add_child(minus)
	var plus := QKit.button("+", "o", 48, 32)
	plus.name = "AllocPlus_%s" % key
	plus.custom_minimum_size = Vector2(88, 72)
	plus.disabled = idle <= 0
	plus.pressed.connect(func() -> void: _shift_allocation(key, 1))
	row.add_child(plus)
	return row


func _shift_allocation(key: String, delta: int) -> void:
	var alloc: Dictionary = _view.get("allocation", {}) if typeof(_view.get("allocation", {})) == TYPE_DICTIONARY else {}
	var garden := int(alloc.get("garden", 0))
	var alchemy := int(alloc.get("alchemy", 0))
	if key == "garden":
		garden += delta
	else:
		alchemy += delta
	action_requested.emit("dongfu_allocate", {"garden": garden, "alchemy": alchemy})


func _upgrade_row(facility: String) -> Control:
	var upgrades: Dictionary = _view.get("upgrades", {}) if typeof(_view.get("upgrades", {})) == TYPE_DICTIONARY else {}
	var row_data: Dictionary = upgrades.get(facility, {}) if typeof(upgrades.get(facility, {})) == TYPE_DICTIONARY else {}
	var wrap := UiKit.hbox(10)
	wrap.name = "UpgradeRow_%s" % facility
	var level := int(row_data.get("level", 1))
	var next: Variant = row_data.get("next", null)
	var title := "药园" if facility == "garden" else "炼丹"
	var effect_name := "地块" if facility == "garden" else "队列"
	var text := "%s %d 级" % [title, level]
	if typeof(next) == TYPE_DICTIONARY:
		var nxt := next as Dictionary
		var cost := "%s ×%d" % [str(_view.get("woodName", "灵木")), int(nxt.get("wood", 0))]
		if int(nxt.get("spiritStones", 0)) > 0:
			cost = "%s · 灵石 ×%d" % [cost, int(nxt.get("spiritStones", 0))]
		text = "%s · 下一级 %s +%d（%s）" % [text, effect_name, int(nxt.get("bonus", 1)), cost]
	else:
		text = "%s · 已满级" % text
	var reason := str(row_data.get("reason", ""))
	if not bool(row_data.get("canUpgrade", false)) and reason != "" and typeof(next) == TYPE_DICTIONARY:
		text = "%s · %s" % [text, reason]
	var label := UiKit.label(text, UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wrap.add_child(label)
	var button := QKit.button("升级", "o", 72, 32)
	button.name = "Upgrade_%s" % facility
	button.custom_minimum_size = Vector2(160, 72)
	button.disabled = not bool(row_data.get("canUpgrade", false))
	button.pressed.connect(func() -> void: action_requested.emit("dongfu_upgrade", {"facility": facility}))
	wrap.add_child(button)
	return wrap


func _facility_card(card: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.name = "Facility_%s" % str(card.get("id", ""))
	wrap.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CARD, UiTokens.Q_COCOA, 3, 28, 4, 18, 4))
	var row := UiKit.hbox(16)
	wrap.add_child(row)
	var sprite := str(card.get("sprite", ""))
	var tex: Texture2D = ArtLib.q("sprites/" + sprite) if not sprite.is_empty() and ArtLib.has_q("sprites/%s.png" % sprite) else null
	if tex == null and str(card.get("id", "")) == "enhance":
		tex = ArtLib.qui("icon_enhance_exp")
	row.add_child(QKit.slot(tex, 2 if tex != null else -1, 132))
	var info := UiKit.vbox(8)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(10)
	info.add_child(head)
	head.add_child(QKit.title(str(card.get("name", "")), 40, UiTokens.TEXT))
	if int(card.get("claimable", 0)) > 0 or bool(card.get("can_upgrade", false)):
		var dot := QKit.reddot(34)
		dot.name = "ClaimDot"
		head.add_child(dot)
	info.add_child(UiKit.label(str(card.get("subtitle", "")), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var go := QKit.button("进入", "o", 88, 34)
	go.name = "Enter_%s" % str(card.get("id", ""))
	go.custom_minimum_size = Vector2(160, 88)
	var id := str(card.get("id", ""))
	go.pressed.connect(func() -> void: _enter_facility(id))
	row.add_child(go)
	return wrap


func _enter_facility(id: String) -> void:
	match id:
		"garden":
			if not bool(_view.get("available", false)):
				action_requested.emit("toast", {"text": str(_view.get("hint", "洞府尚未开放"))})
				return
			_plant_slot = -1
			_mode = MODE_GARDEN
			_render()
		"alchemy":
			if not bool(_view.get("available", false)):
				action_requested.emit("toast", {"text": str(_view.get("hint", "洞府尚未开放"))})
				return
			_mode = MODE_ALCHEMY
			_render()
		"enhance":
			enhance_entry_requested.emit()
		_:
			pass


func _render_garden() -> void:
	var claimable := int((_view.get("claimable", {}) as Dictionary).get("plots", 0))
	var top := UiKit.hbox(12)
	_body.add_child(top)
	var garden_pct := int(round(float((_view.get("timeScale", {}) as Dictionary).get("garden", 1.0)) * 100.0))
	var note := UiKit.label("地块 %d · 成熟时长 %d%%" % [int(_view.get("plotCount", 0)), garden_pct], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(note)
	var claim_all := QKit.button("一键领取", "o", 72, 32)
	claim_all.name = "GardenClaimAll"
	claim_all.custom_minimum_size = Vector2(220, 72)
	claim_all.disabled = claimable <= 0
	claim_all.pressed.connect(func() -> void: action_requested.emit("garden_claim", {}))
	top.add_child(claim_all)
	_body.add_child(_upgrade_row("garden"))

	for plot in _view.get("plots", []):
		_body.add_child(_plot_row(plot as Dictionary))

	if _plant_slot >= 0:
		_body.add_child(_seed_picker(_plant_slot))


func _plot_row(plot: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.name = "Plot_%d" % int(plot.get("slot", 0))
	wrap.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CARD, UiTokens.Q_COCOA, 3, 24, 3, 16, 3))
	var row := UiKit.hbox(12)
	wrap.add_child(row)
	var info := UiKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(10)
	info.add_child(head)
	head.add_child(QKit.title(str(plot.get("title", "")), 34, UiTokens.TEXT))
	var status := str(plot.get("status", "empty"))
	if status == "ready":
		head.add_child(QKit.reddot(28))
	info.add_child(UiKit.label(str(plot.get("line", "")), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var slot := int(plot.get("slot", 0))
	match status:
		"empty":
			var plant := QKit.button("种植", "m", 72, 32)
			plant.name = "Plant_%d" % slot
			plant.custom_minimum_size = Vector2(160, 72)
			plant.pressed.connect(func() -> void:
				_plant_slot = slot
				_render())
			row.add_child(plant)
		"ready":
			var claim := QKit.button("领取", "o", 72, 32)
			claim.name = "ClaimPlot_%d" % slot
			claim.custom_minimum_size = Vector2(160, 72)
			claim.pressed.connect(func() -> void: action_requested.emit("garden_claim", {"slot": slot}))
			row.add_child(claim)
		_:
			var wait := UiKit.label("生长中", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			wait.custom_minimum_size = Vector2(120, 0)
			row.add_child(wait)
	return wrap


func _seed_picker(slot: int) -> Control:
	var box := UiKit.vbox(10)
	box.name = "SeedPicker"
	box.add_child(QKit.title("选择种子 · 地块 %d" % (slot + 1), 34, UiTokens.TEXT))
	var seeds: Array = _view.get("seeds", [])
	if seeds.is_empty():
		box.add_child(UiKit.label("暂无种子配置", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
		return box
	var any := false
	for seed in seeds:
		var s := seed as Dictionary
		var have := int(s.get("have", 0))
		var row := UiKit.hbox(12)
		var label := UiKit.label("%s ×%d（约 %d 秒）" % [str(s.get("name", "")), have, int(s.get("growSeconds", 0))], UiTokens.FS_BODY, UiTokens.TEXT if have > 0 else UiTokens.TEXT_MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var btn := QKit.button("种下", "o", 64, 30)
		btn.disabled = have <= 0
		var slug := str(s.get("seedSlug", ""))
		btn.pressed.connect(func() -> void:
			_plant_slot = -1
			action_requested.emit("garden_plant", {"slot": slot, "seedSlug": slug}))
		row.add_child(btn)
		box.add_child(row)
		if have > 0:
			any = true
	if not any:
		box.add_child(UiKit.label("行囊里没有种子，先去历练获取", UiTokens.FS_MICRO, UiTokens.WARNING))
	var cancel := QKit.button("取消", "m", 64, 30)
	cancel.pressed.connect(func() -> void:
		_plant_slot = -1
		_render())
	box.add_child(cancel)
	return box


func _render_alchemy() -> void:
	var queue_len := int(_view.get("alchemyQueueLength", 2))
	var jobs: Array = _view.get("alchemy", [])
	var claimable := int((_view.get("claimable", {}) as Dictionary).get("alchemy", 0))
	var top := UiKit.hbox(12)
	_body.add_child(top)
	var alchemy_pct := int(round(float((_view.get("timeScale", {}) as Dictionary).get("alchemy", 1.0)) * 100.0))
	var note := UiKit.label("队列 %d/%d · 炼制时长 %d%%" % [jobs.size(), queue_len, alchemy_pct], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(note)
	var claim_all := QKit.button("一键领取", "o", 72, 32)
	claim_all.name = "AlchemyClaimAll"
	claim_all.custom_minimum_size = Vector2(220, 72)
	claim_all.disabled = claimable <= 0
	claim_all.pressed.connect(func() -> void: action_requested.emit("alchemy_claim", {}))
	top.add_child(claim_all)
	_body.add_child(_upgrade_row("alchemy"))

	_body.add_child(QKit.title("炼制中", 34, UiTokens.TEXT))
	if jobs.is_empty():
		_body.add_child(UiKit.label("队列空闲", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	for job in jobs:
		_body.add_child(_alchemy_job_row(job as Dictionary))

	_body.add_child(QKit.title("配方", 34, UiTokens.TEXT))
	var recipes: Array = _view.get("recipes", [])
	if recipes.is_empty():
		_body.add_child(UiKit.label("暂无配方配置", UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	for recipe in recipes:
		_body.add_child(_recipe_row(recipe as Dictionary, jobs.size() >= queue_len))


func _alchemy_job_row(job: Dictionary) -> Control:
	var wrap := PanelContainer.new()
	wrap.name = "AlchemyJob_%s" % str(job.get("id", ""))
	wrap.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CARD, UiTokens.Q_COCOA, 3, 24, 3, 16, 3))
	var row := UiKit.hbox(12)
	wrap.add_child(row)
	var info := UiKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var head := UiKit.hbox(10)
	info.add_child(head)
	head.add_child(QKit.title(str(job.get("outputName", "")), 34, UiTokens.TEXT))
	if str(job.get("status", "")) == "ready":
		head.add_child(QKit.reddot(28))
	info.add_child(UiKit.label(str(job.get("line", "")), UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	if str(job.get("status", "")) == "ready":
		var claim := QKit.button("领取", "o", 72, 32)
		claim.custom_minimum_size = Vector2(160, 72)
		var job_id := str(job.get("id", ""))
		claim.pressed.connect(func() -> void: action_requested.emit("alchemy_claim", {"jobId": job_id}))
		row.add_child(claim)
	return wrap


func _recipe_row(recipe: Dictionary, queue_full: bool) -> Control:
	var wrap := PanelContainer.new()
	wrap.name = "Recipe_%s" % str(recipe.get("recipeSlug", ""))
	wrap.add_theme_stylebox_override("panel", QSkin.custom(UiTokens.Q_CARD, UiTokens.Q_COCOA, 3, 24, 3, 16, 3))
	var row := UiKit.hbox(12)
	wrap.add_child(row)
	var info := UiKit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var heading := str(recipe.get("title", ""))
	if heading.is_empty():
		var output_name := str(recipe.get("outputName", ""))
		if output_name.is_empty():
			output_name = CaveView.UNKNOWN_ITEM_NAME
		heading = "%s ×%d" % [output_name, int(recipe.get("outputQty", 1))]
	info.add_child(QKit.title(heading, 34, UiTokens.TEXT))
	info.add_child(UiKit.label("%s · %d 秒" % [str(recipe.get("costLine", "")), int(recipe.get("craftSeconds", 0))], UiTokens.FS_MICRO, UiTokens.TEXT_MUTED))
	var start := QKit.button("炼制", "o", 72, 32)
	start.custom_minimum_size = Vector2(160, 72)
	var can := bool(recipe.get("canCraft", false)) and not queue_full
	start.disabled = not can
	if queue_full:
		start.tooltip_text = "炼丹队列已满"
	elif not bool(recipe.get("canCraft", false)):
		start.tooltip_text = "材料不足"
	var slug := str(recipe.get("recipeSlug", ""))
	start.pressed.connect(func() -> void: action_requested.emit("alchemy_start", {"recipeSlug": slug}))
	row.add_child(start)
	return wrap
