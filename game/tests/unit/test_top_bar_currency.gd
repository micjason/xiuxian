extends GutTest
## 顶栏货币：灵石是真实货币（服务器 state.spiritStones，玩家表 spirit_stones），显示真实余额；
## 葫芦（血瓶）还没有这个货币 → 图标 + 「--」；state 里没有灵石字段时也显示「--」，不编数字。


func before_each() -> void:
	gut.error_tracker.treat_engine_errors_as = GutUtils.TREAT_AS.NOTHING


func _bar() -> TopBar:
	var bar := TopBar.new()
	add_child_autofree(bar)
	return bar


func test_spirit_stones_show_real_balance() -> void:
	var bar := _bar()
	bar.bind({"realmName": "炼气三层", "power": 950, "spiritStones": 12580})
	assert_eq(bar._stones.text, "12,580")
	bar.bind({"realmName": "炼气三层", "power": 950, "spiritStones": 0})
	assert_eq(bar._stones.text, "0", "余额 0 就显示 0（服务器真实值）")


func test_missing_currency_shows_double_dash() -> void:
	var bar := _bar()
	bar.bind({"realmName": "炼气三层", "power": 950})
	assert_eq(bar._stones.text, "--", "没有灵石字段 → --")
	assert_eq(bar._gourd.text, "--", "葫芦（血瓶）货币还不存在 → --")
	bar.bind({"realmName": "炼气三层", "power": 950, "spiritStones": 5})
	assert_eq(bar._gourd.text, "--", "有灵石时葫芦仍是 --")
