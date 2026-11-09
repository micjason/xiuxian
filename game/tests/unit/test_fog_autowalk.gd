extends GutTest
var old_token: String
var old_account: Dictionary
var old_account_exists: bool
var old_account_raw: String
var journal_path: String
var page: Control
var state: Dictionary
var calls: Array
var active_requests := 0
var max_requests := 0
var lose_response := false
var delay := 0.04
var reveal_shortcut := false
var wrong_position := false
var spawn_blocker := false
var fail_terminal_save := false
var fail_directory_only := false
var journal_seen_at_dispatch := false
func before_each() -> void:
	old_token=PlayerApi.token();old_account=PlayerApi.account()
	old_account_exists=FileAccess.file_exists(PlayerApi.ACCOUNT_PATH)
	old_account_raw=FileAccess.get_file_as_string(PlayerApi.ACCOUNT_PATH) if old_account_exists else ""
	PlayerApi.save_token("local-test-account-a");PlayerApi.save_account("fixture","fog-unit-a")
	journal_path="user://fog-unit-%d-%d.json"%[Time.get_ticks_usec(),randi()]
	state={"mapId":"test","protocol":"fog-step-v1","revision":"a".repeat(64),"rows":4,"cols":6,"pos":{"x":0,"y":1},"revealed":[],"blocks":[],"objects":[],"travelPoints":20}
	for y in range(4):
		for x in range(6): state.revealed.append("%d,%d"%[x,y])
	fail_terminal_save=false;fail_directory_only=false;journal_seen_at_dispatch=false
	calls=[];active_requests=0;max_requests=0;lose_response=false;delay=0.04;reveal_shortcut=false;wrong_position=false;spawn_blocker=false
	page=load("res://tests/helpers/fog_authenticated_page.gd").new();page.pending_store.path=journal_path;page.size=Vector2(1080,1920);add_child_autofree(page)
	page.set("transport",Callable(self,"request"))
	page.bind_fog({"fog":state.duplicate(true)})
func request(path: String, body: Dictionary) -> Dictionary:
	calls.append({"path":path,"body":body.duplicate(true)})
	active_requests+=1;max_requests=maxi(max_requests,active_requests)
	await get_tree().create_timer(delay).timeout
	active_requests-=1
	if path.ends_with("reconcile"):
		return {"code":200,"fog":state.duplicate(true),"step":{"id":body.stepId,"status":"committed"}}
	if path.ends_with("move"):
		var journal: Dictionary=page.pending_store.read_all()
		for record in journal.get("slots",{}).values():
			if record.pending and record.body.stepId==body.stepId: journal_seen_at_dispatch=true
		if state.travelPoints <= 0:
			return {"code":200,"fog":state.duplicate(true),"step":{"id":body.stepId,"status":"rejected","error":"游历点不足"}}
		state.pos={"x":body.x,"y":body.y};state.travelPoints-=1
		if reveal_shortcut and not "2,1" in state.revealed: state.revealed.append("2,1")
		if wrong_position: state.pos={"x":2,"y":2}
		if spawn_blocker: state.objects=[{"id":"new-event","kind":"event","x":2,"y":1}]
		state.revision=str(state.travelPoints).sha256_text()
		if fail_terminal_save: page.pending_store.synchronize=Callable(self,"failed_sync")
		if lose_response:
			lose_response=false
			return {"code":0}
		return {"code":200,"fog":state.duplicate(true),"step":{"id":body.stepId,"status":"committed"}}
	return {"code":500}
func wait_done(seconds: float=1.5) -> void:
	await get_tree().create_timer(seconds).timeout
func test_far_walk_and_twenty_repeated_clicks_are_one_serial_route() -> void:
	for i in range(20): page.call("_on_cell",4,1)
	await wait_done()
	assert_eq(calls.size(),4);assert_eq(max_requests,1)
	assert_eq(state.pos,{"x":4,"y":1});assert_eq(state.travelPoints,16)
func test_new_target_waits_for_inflight_and_replans_from_authority() -> void:
	page.call("_on_cell",4,1)
	page.call("_on_cell",0,3)
	await wait_done()
	assert_eq(max_requests,1);assert_eq(state.pos,{"x":0,"y":3})
	assert_eq(calls[0].body.x,1)
func test_hide_during_request_allows_only_that_step_no_continuation() -> void:
	page.call("_on_cell",4,1);page.hide()
	await wait_done(0.6)
	assert_eq(calls.size(),1);assert_eq(state.travelPoints,19)
func test_cancel_during_animation_does_not_show_object_or_continue() -> void:
	state.objects=[{"id":"c","kind":"chest","x":2,"y":1}];page.bind_fog({"fog":state})
	page.call("_on_cell",2,1)
	await get_tree().create_timer(0.09).timeout
	page.call("stop_route")
	await wait_done(0.6)
	assert_eq(calls.size(),1);assert_false(page.get("_confirm").visible)
func test_lost_committed_response_requires_terminal_reconcile_before_new_move() -> void:
	lose_response=true
	page.call("_on_cell",4,1)
	await wait_done(0.3)
	assert_eq(calls.size(),1);assert_eq(state.pos,{"x":1,"y":1})
	page.call("_on_cell",0,1)
	await wait_done()
	assert_eq(calls[1].path.get_file(),"reconcile")
	assert_eq(calls[0].body.stepId,calls[1].body.stepId)
	assert_eq(max_requests,1);assert_eq(state.pos,{"x":0,"y":1});assert_eq(state.travelPoints,18)
func test_legacy_backend_and_unknown_refuse_without_request() -> void:
	state.erase("protocol");page.bind_fog({"fog":state});page.call("_on_cell",4,1)
	await wait_done(0.1);assert_eq(calls.size(),0)
	state.protocol="fog-step-v1";state.revealed=["0,1"];page.bind_fog({"fog":state});page.call("_on_cell",1,1)
	await wait_done(0.1);assert_eq(calls.size(),0)
func test_object_arrival_has_confirmation_but_no_automatic_interaction() -> void:
	state.objects=[{"id":"c","kind":"chest","x":3,"y":1}];page.bind_fog({"fog":state})
	page.call("_on_cell",3,1);await wait_done()
	assert_eq(state.pos,{"x":2,"y":1});assert_eq(calls.size(),2)
	assert_true(page.get("_confirm").visible)
func test_budget_stops_without_extra_successful_charge() -> void:
	state.travelPoints=1;page.bind_fog({"fog":state});page.call("_on_cell",4,1)
	await wait_done();assert_eq(state.travelPoints,0);assert_eq(calls.size(),1)

func test_late_entrance_get_does_not_pull_user_back_from_another_page() -> void:
	var screen: Control=load("res://tests/helpers/fog_delayed_screen.gd").new()
	add_child_autofree(screen)
	screen.call("_show_page","cave")
	screen.call("_open_fog")
	screen.call("_show_page","cultivate")
	await wait_done(0.3)
	assert_eq(screen.get("_page"),"cultivate")

func test_new_reveal_does_not_shorten_route_through_out_of_snapshot_cell() -> void:
	state.revealed.erase("2,1");page.bind_fog({"fog":state.duplicate(true)});reveal_shortcut=true
	page.call("_on_cell",4,1);await wait_done(2.1)
	assert_eq(state.pos,{"x":4,"y":1});assert_eq(calls.size(),6)
	for c in calls: assert_false(int(c.body.x)==2 and int(c.body.y)==1,"original snapshot excludes shortcut")
func test_wrong_authority_position_is_applied_but_never_animates_to_requested_target() -> void:
	wrong_position=true;page.call("_on_cell",4,1);await wait_done(0.4)
	assert_eq(calls.size(),1);assert_eq(page.get("_view").pos,{"x":2,"y":2})
	assert_false(page.get("_walk_playing"));assert_eq(page.get("_route_target"),Vector2i(-1,-1))
func test_hidden_unknown_step_does_not_retry_until_explicit_reentry() -> void:
	lose_response=true;page.call("_on_cell",4,1);page.hide();await wait_done(0.3)
	assert_eq(calls.size(),1)
	page.show();assert_true(await page.call("prepare_open"));assert_eq(calls.size(),2)
	assert_true(calls[1].path.ends_with("reconcile"));assert_eq(page.get("_route_target"),Vector2i(-1,-1))
func test_new_target_during_animation_waits_and_never_resumes_old_queue() -> void:
	page.call("_on_cell",4,1);await get_tree().create_timer(0.09).timeout
	page.call("_on_cell",0,1);await wait_done(0.8)
	assert_eq(calls.size(),2);assert_eq(max_requests,1);assert_eq(state.pos,{"x":0,"y":1})
func test_account_change_discards_old_response_and_never_continues() -> void:
	var previous := PlayerApi.token()
	PlayerApi.save_token("local-test-account-a")
	page.call("_on_cell",4,1)
	PlayerApi.save_token("local-test-account-b")
	await wait_done(0.3)
	assert_eq(calls.size(),1);assert_eq(page.get("_view").pos,{"x":0,"y":1})
	if previous.is_empty(): PlayerApi.clear_token()
	else: PlayerApi.save_token(previous)

func test_visible_stop_button_cancels_the_active_route() -> void:
	var stop: Button=page.find_child("FogStop",true,false) as Button
	assert_not_null(stop)
	if stop == null: return
	page.call("_on_cell",4,1);stop.pressed.emit();await wait_done(0.4)
	assert_eq(calls.size(),1);assert_eq(page.get("_route_target"),Vector2i(-1,-1))

func battle_response(_path: String,_body: Dictionary) -> Dictionary:
	calls.append({"path":"combat/start"})
	await get_tree().create_timer(0.06).timeout
	return {"code":200,"fog":state.duplicate(true),"session":{"id":"local-session"}}
func test_explicit_battle_late_response_after_leaving_does_not_reopen_battle() -> void:
	page.set("transport",Callable(self,"battle_response"));watch_signals(page)
	page.call("_do_battle","m_test");page.hide();await wait_done(0.3)
	assert_eq(calls.size(),1);assert_signal_not_emitted(page,"battle_requested")

func test_new_authoritative_blocker_stops_without_bypassing_or_selecting_event() -> void:
	spawn_blocker=true;page.call("_on_cell",4,1);await wait_done(0.7)
	assert_eq(calls.size(),1);assert_eq(state.pos,{"x":1,"y":1})
	assert_false(page.get("_event_panel").visible)
func test_monster_and_event_targets_only_prompt_after_arrival_never_auto_interact() -> void:
	for kind in ["monster","event"]:
		state.pos={"x":0,"y":1};state.objects=[{"id":"o","kind":kind,"x":3,"y":1}]
		page.stop_route();page.bind_fog({"fog":state.duplicate(true)});calls=[]
		page.call("_on_cell",3,1);await wait_done(0.8)
		assert_eq(calls.size(),2,kind+" no automatic interaction")
		assert_eq(state.pos,{"x":2,"y":1})
		if kind=="monster": assert_true(page.get("_confirm").visible)
		else: assert_true(page.get("_event_panel").visible)

func mark_prepared(flag: Dictionary) -> void:
	await page.call("prepare_open")
	flag.done=true
signal interaction_release
func held_interaction_response(_path: String,_body: Dictionary) -> Dictionary:
	calls.append({"path":"interact"})
	await interaction_release
	return {"code":200,"fog":state.duplicate(true)}
func test_reentry_waits_for_explicit_interaction_before_loading_state() -> void:
	page.set("transport",Callable(self,"held_interaction_response"))
	page.call("_do_interact","c_test")
	page.hide()
	var flag := {"done":false}
	mark_prepared(flag)
	assert_false(flag.done,"entrance GET must not race outstanding interaction")
	interaction_release.emit()
	await get_tree().process_frame
	assert_true(flag.done)

func test_repeated_reentry_coalesces_uncertain_step_reconciliation() -> void:
	lose_response=true;page.call("_on_cell",4,1)
	var flags: Array=[{"done":false},{"done":false},{"done":false}]
	for flag in flags: mark_prepared(flag)
	await wait_done(0.3)
	assert_eq(calls.size(),2,"one lost move plus exactly one terminal reconciliation")
	assert_eq(max_requests,1)
	for flag in flags: assert_true(flag.done)

func test_destroyed_page_restores_committed_unknown_step_before_new_route() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	assert_eq(calls.size(),1)
	page.free()
	page=load("res://tests/helpers/fog_authenticated_page.gd").new();page.pending_store.path=journal_path;page.size=Vector2(1080,1920);add_child_autofree(page)
	page.set("transport",Callable(self,"request"));page.bind_fog({"fog":state.duplicate(true)})
	assert_true(await page.call("prepare_open"))
	assert_eq(calls.size(),2,"new page must restore durable pending and reconcile, not treat GET as terminal")
	if calls.size()>1: assert_true(calls[1].path.ends_with("reconcile"))

func after_each() -> void:
	if old_token.is_empty(): PlayerApi.clear_token()
	else: PlayerApi.save_token(old_token)
	if old_account_exists:
		var account_file:=FileAccess.open(PlayerApi.ACCOUNT_PATH,FileAccess.WRITE);account_file.store_string(old_account_raw);account_file.close()
	elif FileAccess.file_exists(PlayerApi.ACCOUNT_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(PlayerApi.ACCOUNT_PATH))
	for suffix in ["",".tmp"]:
		if FileAccess.file_exists(journal_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(journal_path+suffix))

func failed_sync(file_path: String) -> bool:
	return fail_directory_only and file_path.ends_with(".tmp")
func test_pending_is_durable_before_transport_dispatch() -> void:
	page.call("_on_cell",1,1);await wait_done(0.4)
	assert_true(journal_seen_at_dispatch)
	var journal: Dictionary=page.pending_store.read_all()
	assert_true(journal.ok)
	for record in journal.slots.values():
		assert_false(record.pending)
		assert_eq(record.terminal.fog.pos,{"x":1.0,"y":1.0})
		assert_false(JSON.stringify(record).contains(PlayerApi.token()),"no token in journal")
func test_failed_pre_dispatch_sync_never_sends_move() -> void:
	page.pending_store.synchronize=Callable(self,"failed_sync")
	page.call("_on_cell",4,1);await wait_done(0.1)
	assert_eq(calls.size(),0);assert_eq(state.travelPoints,20)
	assert_false(await page.prepare_open(),"interrupted first save freezes, not absent pending")
func test_corrupted_file_is_not_treated_as_no_pending() -> void:
	var file:=FileAccess.open(journal_path,FileAccess.WRITE);file.store_string("{half-written");file.close()
	assert_false(await page.prepare_open())
	page.call("_on_cell",4,1);await wait_done(0.1)
	assert_eq(calls.size(),0);assert_eq(FileAccess.get_file_as_string(journal_path),"{half-written")
func test_orphan_temporary_file_without_main_freezes() -> void:
	var file:=FileAccess.open(journal_path+".tmp",FileAccess.WRITE);file.store_string("partial");file.close()
	assert_false(await page.prepare_open());page.call("_on_cell",4,1);await wait_done(0.1)
	assert_eq(calls.size(),0)
func test_terminal_write_failure_never_dispatches_a_new_step_until_reconciled_and_saved() -> void:
	fail_terminal_save=true
	page.call("_on_cell",4,1);await wait_done(0.3)
	assert_eq(calls.size(),1);assert_eq(state.travelPoints,19)
	page.call("_on_cell",0,1);await wait_done(0.3)
	assert_eq(calls.size(),2);assert_true(calls[1].path.ends_with("reconcile"))
	assert_eq(calls[0].body.stepId,calls[1].body.stepId)
	assert_eq(state.travelPoints,19)
	fail_terminal_save=false;page.pending_store.synchronize=Callable()
	assert_true(await page.prepare_open())
	assert_eq(calls.size(),3);assert_true(calls[2].path.ends_with("reconcile"))
	assert_eq(state.travelPoints,19)
func test_terminal_directory_sync_failure_cannot_be_hidden_by_visible_cleared_file() -> void:
	fail_terminal_save=true;fail_directory_only=true
	page.call("_on_cell",4,1);await wait_done(0.3)
	var journal: Dictionary=page.pending_store.read_all()
	for record in journal.slots.values(): assert_false(record.pending,"rename happened, but directory sync failed")
	page.call("_on_cell",0,1);await wait_done(0.3)
	assert_eq(calls.size(),2);assert_true(calls[1].path.ends_with("reconcile"))
	assert_eq(state.travelPoints,19)
	fail_terminal_save=false;page.pending_store.synchronize=Callable()
	assert_true(await page.prepare_open());assert_eq(state.travelPoints,19)
func test_account_switch_retains_old_unresolved_and_token_rotation_can_recover_it() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	var old_id: String=calls[0].body.stepId
	PlayerApi.save_token("local-test-account-b");PlayerApi.save_account("B","fog-unit-b")
	assert_true(await page.prepare_open());assert_eq(calls.size(),1,"no A step sent with B credentials")
	var journal: Dictionary=page.pending_store.read_all()
	assert_eq(journal.slots.size(),1)
	for record in journal.slots.values(): assert_true(record.pending);assert_eq(record.identity.playerId,"fog-unit-a")
	PlayerApi.save_token("local-test-account-a-rotated");PlayerApi.save_account("A","fog-unit-a")
	assert_true(await page.prepare_open());assert_eq(calls.size(),2)
	assert_eq(calls[1].body.stepId,old_id);assert_true(calls[1].path.ends_with("reconcile"))
	assert_eq(state.travelPoints,19)
func test_recomputed_checksum_with_wrong_endpoint_is_rejected_not_sent() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	var wrapper: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(journal_path))
	var data: Dictionary=JSON.parse_string(wrapper.payload)
	for record in data.slots.values(): record.identity.reconcilePath="/api/v1/me/fog/other/reconcile"
	wrapper.payload=JSON.stringify(data);wrapper.sha256=str(wrapper.payload).sha256_text()
	var file:=FileAccess.open(journal_path,FileAccess.WRITE);file.store_string(JSON.stringify(wrapper));file.close()
	assert_false(await page.prepare_open());assert_eq(calls.size(),1)
func test_other_map_body_is_never_reconciled_at_current_maps_endpoint() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	page.set("_map_id","different-map")
	assert_true(await page.prepare_open())
	assert_eq(calls.size(),2);assert_eq(calls[1].path,"/api/v1/me/fog/test/reconcile")

func malformed_terminal(_path: String,body: Dictionary) -> Dictionary:
	calls.append({"path":_path,"body":body.duplicate(true)})
	await get_tree().create_timer(0.02).timeout
	var fog:=state.duplicate(true);fog.erase("pos")
	return {"code":200,"fog":fog,"step":{"id":body.stepId,"status":"committed"}}
func test_missing_authoritative_position_cannot_clear_pending() -> void:
	page.transport=Callable(self,"malformed_terminal")
	page.call("_on_cell",1,1);await wait_done(0.3)
	assert_eq(calls.size(),1)
	var journal: Dictionary=page.pending_store.read_all()
	for record in journal.slots.values(): assert_true(record.pending,"terminal label without authoritative position is not enough")

func test_token_changed_with_stale_cached_account_never_reconciles_as_wrong_player() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	var old_step: String=calls[0].body.stepId
	# A power loss between save_token(B) and save_account(B) leaves A's metadata.
	PlayerApi.save_token("local-test-account-b");page.set("authenticated_id","fog-unit-b")
	assert_true(await page.prepare_open())
	assert_eq(calls.size(),1,"must verify actual session identity before reconciling A's step under B")
	var journal: Dictionary=page.pending_store.read_all()
	for record in journal.slots.values(): assert_true(record.pending);assert_eq(record.identity.playerId,"fog-unit-a")
	PlayerApi.save_token("local-test-account-a-rotated");page.set("authenticated_id","fog-unit-a")
	assert_true(await page.prepare_open())
	assert_eq(calls.size(),2);assert_eq(calls[1].body.stepId,old_step)

func test_same_player_unresolved_at_another_server_address_freezes_instead_of_assuming_independent_endpoint() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	var old_base:=OS.get_environment("XIUXIAN_API_BASE")
	OS.set_environment("XIUXIAN_API_BASE","http://127.0.0.1:9")
	var prepared: bool=await page.prepare_open()
	OS.set_environment("XIUXIAN_API_BASE",old_base)
	assert_false(prepared,"an endpoint alias may be the same backend; old pending must not be forgotten")
	assert_eq(calls.size(),1,"do not send old credentials/body to the different endpoint")
	assert_true(await page.prepare_open());assert_eq(calls.size(),2)

func corrupt_temporary_write(file_path: String) -> bool:
	if file_path.ends_with(".tmp"):
		var file:=FileAccess.open(file_path,FileAccess.WRITE);file.store_string("partial");file.close()
	return true
func test_corrupt_temporary_write_does_not_replace_another_accounts_pending_checkpoint() -> void:
	lose_response=true;page.call("_on_cell",4,1);await wait_done(0.3)
	var original:=FileAccess.get_file_as_bytes(journal_path)
	PlayerApi.save_token("local-test-account-b");PlayerApi.save_account("B","fog-unit-b")
	page.pending_store.synchronize=Callable(self,"corrupt_temporary_write")
	page.call("_on_cell",1,1);await wait_done(0.2)
	assert_eq(calls.size(),1,"corrupt write must not dispatch B's move")
	assert_eq(FileAccess.get_file_as_bytes(journal_path),original,"preserve A's unresolved checkpoint before atomic replace")

func test_committed_terminal_save_failure_updates_authority_hud_but_keeps_pending_frozen() -> void:
	var messages: Array=[]
	page.toast_requested.connect(func(message: String,_success: bool): messages.append(message))
	fail_terminal_save=true
	page.call("_on_cell",4,1);await wait_done(0.3)
	assert_eq(calls.size(),1)
	assert_eq(page.get("_view").get("pos"),{"x":1,"y":1},"confirmed server position must be visible even if journal clear fails")
	assert_eq(page.get("_hud_travel").text,"19/200","show already-deducted authoritative balance")
	assert_false(page.get("_pending_step").is_empty(),"displaying authority must not release unresolved durable checkpoint")
	assert_true(str(messages).contains("已落地"))
	assert_true(str(messages).contains("不能继续"))
	page.call("_on_cell",0,1);await wait_done(0.3)
	assert_eq(calls.size(),2);assert_true(calls[1].path.ends_with("reconcile"))
	assert_eq(state.travelPoints,19)
