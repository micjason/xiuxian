extends GutTest
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
func before_each() -> void:
	state={"mapId":"test","protocol":"fog-step-v1","revision":"a".repeat(64),"rows":4,"cols":6,"pos":{"x":0,"y":1},"revealed":[],"blocks":[],"objects":[],"travelPoints":20}
	for y in range(4):
		for x in range(6): state.revealed.append("%d,%d"%[x,y])
	calls=[];active_requests=0;max_requests=0;lose_response=false;delay=0.04;reveal_shortcut=false;wrong_position=false;spawn_blocker=false
	page=FogMapPage.new();page.size=Vector2(1080,1920);add_child_autofree(page)
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
		if state.travelPoints <= 0:
			return {"code":200,"fog":state.duplicate(true),"step":{"id":body.stepId,"status":"rejected","error":"游历点不足"}}
		state.pos={"x":body.x,"y":body.y};state.travelPoints-=1
		if reveal_shortcut and not "2,1" in state.revealed: state.revealed.append("2,1")
		if wrong_position: state.pos={"x":2,"y":2}
		if spawn_blocker: state.objects=[{"id":"new-event","kind":"event","x":2,"y":1}]
		state.revision=str(state.travelPoints).sha256_text()
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
