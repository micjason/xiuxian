extends GutTest
func adapter() -> FogPendingStore:
	var store:=FogPendingStore.new()
	assert_true(store.has_method("_android_fsync"),"Android must use checked public Os API, not an optional toybox applet")
	return store
func test_android_public_os_sync_closes_descriptor_in_order() -> void:
	var store:=adapter()
	if not store.has_method("_android_fsync"): return
	var bridge=load("res://tests/helpers/fog_java_sync_fake.gd").new()
	assert_true(store.call("_android_fsync","/data/user/0/test/files/pending.tmp",bridge))
	assert_eq(bridge.events,["wrap",["open","/data/user/0/test/files/pending.tmp",0,0],"fsync","close"])
func test_android_fsync_exception_cannot_be_erased_by_successful_close() -> void:
	var store:=adapter()
	if not store.has_method("_android_fsync"): return
	var bridge=load("res://tests/helpers/fog_java_sync_fake.gd").new();bridge.fail_at="fsync"
	assert_false(store.call("_android_fsync","/data/test",bridge))
	assert_eq(bridge.events.back(),"close","always close the descriptor after failed fsync")
	assert_null(bridge.exception,"close succeeded and cleared last exception, but fsync result must remain failure")
func test_android_open_exception_never_attempts_sync_or_close() -> void:
	var store:=adapter()
	if not store.has_method("_android_fsync"): return
	var bridge=load("res://tests/helpers/fog_java_sync_fake.gd").new();bridge.fail_at="open"
	assert_false(store.call("_android_fsync","/data/test",bridge))
	assert_eq(bridge.events.size(),2)
func test_android_close_exception_is_a_checked_failure() -> void:
	var store:=adapter()
	if not store.has_method("_android_fsync"): return
	var bridge=load("res://tests/helpers/fog_java_sync_fake.gd").new();bridge.fail_at="close"
	assert_false(store.call("_android_fsync","/data/test",bridge))
	assert_eq(bridge.events.back(),"close")
