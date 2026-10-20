extends SceneTree
## v13 截图（开发用，不进游戏）：Q 版 7 屏 + 动画特效关键帧。数据来自 ProtoMock（与服务器同结构的演示数据）。
## 用法：XIUXIAN_UI_MOCK=1 XIUXIAN_SAFE_AREA=0,90,0,0 godot --path game --rendering-driver opengl3 --resolution 1080x2340 \
##   --script res://scripts/dev/capture_v13.gd -- <输出目录>
## 动画在真实时间里播（xvfb 下帧率不稳），关键帧按时间点截，前后可能差一两帧。

var _out := ""
var _scene: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp/ui_v13"
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	for i in 10:
		await process_frame
	# 离线收益：宝箱关着 → 开盖金光 → 打开后（数字滚到真实值）
	await _wait(0.45)
	_shot("fx_offline_1_closed")
	await _wait(1.25)
	_shot("fx_offline_2_burst")
	await _wait(2.6)
	_shot("q_offline_popup")
	(_scene.get("_offline_popup") as OfflinePopup).claim_button().pressed.emit()
	await _wait(0.6)
	# 修炼页：动画主角、底栏突破圆钮呼吸光；一次心跳结算（演示数据算出来的修为 / 击杀 / 掉落）→ 飘字 + 掉落飞进背包
	_scene.call("_show_page", "cultivate")
	await _wait(1.0)
	_shot("q_cultivate")
	var state: Dictionary = _scene.get("_state")
	_scene.set("_state", ProtoMock.tick(state, ProtoMock.content() if _scene.get("_content") == null else _scene.get("_content"), 25.0))
	_scene.call("_render", true)
	await _wait(0.45)
	_shot("fx_cultivate_1_gain_float")
	await _wait(0.45)
	_shot("fx_cultivate_2_drop_fly")
	await _wait(0.45)
	_shot("fx_cultivate_3_bag_pulse")
	await _wait(1.2)
	# 「功能暂未开放」提示条（点邮件）
	var mail := (_scene.get("_top_bar") as Node).find_child("MailButton", true, false) as BaseButton
	mail.pressed.emit()
	await _wait(0.4)
	_shot("fx_toast_locked")
	var toast := _scene.get("_toast") as Control
	print("toast ", toast.get_global_rect(), " ", toast.get_parent().name, " vp ", toast.get_viewport_rect(), " mode ", toast.call("mode"))
	await _wait(2.2)
	for entry in [["adventure", "q_adventure"], ["bag", "q_bag"], ["skill", "q_techniques"], ["cave", "q_cave"]]:
		_scene.call("_show_page", entry[0])
		await _wait(0.8)
		_shot(entry[1])
	# 突破：弹窗 idle → 充能 → 成功（横幅在主角脚下，不压境界行）→ 突破成功结算
	_scene.call("_show_page", "cultivate")
	await _wait(0.3)
	_scene.call("_open_breakthrough")
	await _wait(0.12)
	_shot("fx_break_0_popup_open")
	await _wait(1.0)
	_shot("q_breakthrough_popup")
	_scene.call("_on_breakthrough")
	await _wait(1.2)
	_shot("fx_break_1_charge")
	await _wait(1.0)
	_shot("fx_break_2_flash")
	await _wait(0.6)
	_shot("fx_break_3_banner")
	var page := _scene.get("_breakthrough_page") as BreakthroughPage
	print("banner rect ", page.success_title_rect())
	await _wait(0.6)
	_shot("fx_break_4_banner_settled")
	await _wait(2.0)
	_shot("fx_break_5_success_popup")
	(_scene.get("_success_popup") as BreakthroughSuccess).close_popup()
	await _wait(0.6)
	# 突破后解锁的新地图（幽冥古道）：新怪物立绘
	_scene.call("_show_page", "adventure")
	await _wait(0.8)
	_shot("q_adventure_after_break")
	quit()


func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("shot ", name)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
