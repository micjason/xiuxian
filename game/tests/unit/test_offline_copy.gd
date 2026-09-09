extends GutTest


func _result(gained: float, applied_seconds: int, hit_cap: bool, clock_rewound: bool = false) -> SettlementResult:
	var result := SettlementResult.new()
	result.gained = gained
	result.applied_seconds = applied_seconds
	result.hit_cap = hit_cap
	result.clock_rewound = clock_rewound
	return result


func test_banner_and_dialog_explain_gain_and_cap() -> void:
	var result := _result(246.0, 120, false)
	assert_eq(OfflineCopy.banner(result), "闭关归来 +246 · 2 分钟")
	var text := OfflineCopy.dialog(result, 28800)
	assert_true(text.contains("获得修为：246"))
	assert_true(text.contains("结算时长：2 分钟"))
	assert_true(text.contains("未顶到 8 小时 上限"))


func test_dialog_says_when_offline_cap_is_hit() -> void:
	var result := _result(80.0, 45, true)
	var text := OfflineCopy.dialog(result, 45)
	assert_true(text.contains("已顶到离线上限 45 秒"))
	assert_true(text.contains("超出部分未计算"))


func test_clock_rewind_does_not_claim_a_gain() -> void:
	var result := _result(10.0, 30, false, true)
	assert_eq(OfflineCopy.banner(result), "检测到时间回拨，未扣除修为。")
	assert_eq(OfflineCopy.dialog(result, 28800), "检测到时间回拨，未扣除修为。")
