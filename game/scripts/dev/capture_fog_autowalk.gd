extends Control
## Real desktop renderer + real private HTTP API. Handler invocation is automated, not Android/manual play.
var page: Control
var note: Label
var trace: Array=[]
var drop_response := false
var requests := 0
var active := 0
var max_active := 0
const OUT := "/workspace/cp_fix_shots/fog_autowalk"
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1080,1920))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	PlayerApi.save_token(FileAccess.get_file_as_string("/workspace/.deploy/fog-autowalk/capture-session").strip_edges())
	page=FogMapPage.new();page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(page)
	page.transport=Callable(self,"request")
	note=Label.new();note.position=Vector2(30,1640);note.size=Vector2(1020,130);note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",28);note.add_theme_color_override("font_color",Color("6B4A3A"));note.z_index=100;add_child(note)
	page.toast_requested.connect(func(text: String,_ok: bool)->void: note.text="本地PC / 真实HTTP / 自动化测试
"+text)
	await get_tree().process_frame
	await run()
	var f=FileAccess.open(OUT+"/http-trace.json",FileAccess.WRITE);f.store_string(JSON.stringify({"events":trace,"max_inflight":max_active},"  "))
	get_tree().quit()
func request(path: String,body: Dictionary) -> Dictionary:
	requests+=1;active+=1;max_active=maxi(active,max_active)
	trace.append({"event":"send","path":path,"from":body.get("expectedFrom",{}),"target":[body.get("x"),body.get("y")],"stepId":body.get("stepId")})
	await get_tree().create_timer(0.10).timeout
	var result: Dictionary=await ApiClient.request_json(HTTPClient.METHOD_POST,path,body,PlayerApi.token(),str(body.get("stepId","capture-%d-%d" % [Time.get_ticks_usec(),randi()])) )
	active-=1
	trace.append({"event":"response","code":result.get("code"),"step":result.get("step"),"pos":result.get("fog",{}).get("pos"),"travel":result.get("fog",{}).get("travelPoints")})
	if drop_response and path.ends_with("move"):
		drop_response=false;trace.append({"event":"deliberately_drop_committed_response"});return {"code":0}
	return result
func fixture(name: String) -> void:
	page.stop_route()
	var result: Dictionary=await ApiClient.request_json(HTTPClient.METHOD_POST,"/__fog_fixture/"+name,{},PlayerApi.token())
	assert(int(result.get("code",0))==200)
	page.bind_fog(result)
	await get_tree().process_frame
func idle() -> void:
	var deadline:=Time.get_ticks_msec()+15000
	while page.get("_runner_running") and Time.get_ticks_msec()<deadline: await get_tree().process_frame
	assert(not page.get("_runner_running"))
func shot(name: String,text: String="") -> void:
	if not text.is_empty(): note.text="本地PC / 真实HTTP / 自动化测试
"+text
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	image.save_png(OUT+"/"+name+".png")
	var view: Dictionary=page.get("_view")
	trace.append({"shot":name,"pos":view.get("pos"),"travel":view.get("travel"),"explore":[view.get("explore_revealed"),view.get("explore_total")]})
	print("CAPTURE ",name," pos=",view.get("pos")," travel=",view.get("travel")," explore=",view.get("explore_revealed"),"/",view.get("explore_total"))
func run() -> void:
	await fixture("known")
	await shot("01_before","点击已揭开的远处 (6,5)，以当前可达快照为界")
	page.call("_on_cell",6,5)
	while int(page.get("_view").pos.y)==10 and page.get("_runner_running"): await get_tree().process_frame
	await get_tree().create_timer(0.04).timeout
	await shot("02_midway","逐步服务端确认后动画；不会顺路开箱或开战")
	await idle()
	assert(int(page.get("_view").pos.x)==6 and int(page.get("_view").pos.y)==5)
	await shot("03_arrived","抵达远处 (6,5)，真实逐步扣费")
	await fixture("known")
	var before:=requests
	page.call("_on_cell",6,5)
	await get_tree().create_timer(0.03).timeout
	page.stop_route()
	await idle()
	assert(requests==before+1)
	await shot("04_cancelled","取消：只落已派出的1步，后续没有移动请求")
	await fixture("known")
	drop_response=true;page.call("_on_cell",6,5);await idle()
	assert(not page.get("_pending_step").is_empty())
	await shot("05_response_lost","人为丢弃已提交响应：停止，保留未决步骤，不回滚/重发移动")
	page.call("_on_cell",3,10);await idle()
	assert(int(page.get("_view").pos.x)==3 and int(page.get("_view").pos.y)==10)
	assert(page.get("_view").travel==198)
	await shot("06_recovered","原stepId终态对账后，新目标才走；最终200→198只扣2步")
	before=requests;page.call("_on_cell",0,0);await shot("07_unknown_rejected")
	assert(requests==before)
	page.call("_on_cell",1,5);await shot("08_unreachable_rejected")
	assert(requests==before)
	await fixture("guard")
	assert(page.get("_view").explore_revealed==78)
	await shot("09_guard_before","谷口例外：78/79，(4,1)已揭，可明确点入纯移动拨雾")
	page.call("_on_cell",4,1);await idle()
	assert(page.get("_view").explore_full)
	assert(page.get("_view").explore_revealed==79)
	await shot("10_guard_79_of_79","站谷口揭雾79/79；没有自动开战")
	page.call("_on_cell",4,1)
	assert(page.get("_confirm").visible)
	await shot("11_guard_confirm","探索满后仍须主动确认开战")
	await full_journey()

func full_journey() -> void:
	await fixture("spawn")
	trace.append({"event":"fresh_spawn_journey_begin","note":"harness issues separate explicit destinations; production route never expands snapshot"})
	await shot("12_fresh_spawn","真实新局5/79起步，测试程序逐次下达独立已知目标")
	var command_count := 0
	var start_requests := requests
	while not bool(page.get("_view").get("explore_full",false)) and command_count < 150:
		var view: Dictionary=page.get("_view")
		var snapshot: Array=view.revealed.duplicate(true)
		var best := Vector2i(-1,-1)
		var best_score := 999999
		var chest := false
		for key in snapshot:
			var xy: PackedStringArray=str(key).split(",")
			var cell := Vector2i(int(xy[0]),int(xy[1]))
			var obj := FogRoute.object_at(view,cell)
			if not obj.is_empty() and str(obj.get("kind","")) != "exit": continue
			var plan := FogRoute.plan(view,cell,snapshot)
			if not plan.ok or plan.path.is_empty(): continue
			var gain := 0
			for d in FogRoute.DIRS:
				var n: Vector2i=cell+d
				if n.x<0 or n.y<0 or n.x>=int(view.cols) or n.y>=int(view.rows) or FogMapView.is_blocked(view,n.x,n.y): continue
				if not FogMapView.cell_key(n.x,n.y) in snapshot: gain+=1
			if gain<=0: continue
			var score: int=plan.path.size()*4-gain
			if score<best_score: best=cell;best_score=score
		if best == Vector2i(-1,-1):
			for obj in view.objects:
				if str(obj.get("kind",""))!="chest" or bool(obj.get("opened",false)): continue
				var cell := Vector2i(int(obj.x),int(obj.y))
				var plan := FogRoute.plan(view,cell,snapshot)
				if plan.ok and plan.path.size()<best_score:
					best=cell;best_score=plan.path.size();chest=true
		assert(best != Vector2i(-1,-1),"no legal revealed frontier or explicit chest")
		command_count+=1
		trace.append({"event":"separate_explicit_destination","number":command_count,"target":[best.x,best.y],"revealed_before":view.explore_revealed})
		page.call("_on_cell",best.x,best.y)
		await idle()
		if chest:
			assert(page.get("_confirm").visible)
			trace.append({"event":"explicit_user_confirm_chest"})
			page.call("_on_confirm_fight")
			while bool(page.get("_busy")): await get_tree().process_frame
		assert(int(page.get("_view").travel)>0,"fresh exploration must stay within real budget")
	assert(bool(page.get("_view").explore_full))
	assert(int(page.get("_view").explore_revealed)==79)
	await shot("13_fresh_journey_79_of_79","新局逐次独立点击探索至79/79；箱子均须显式确认")
	trace.append({"event":"fresh_spawn_journey_complete","commands":command_count,"requests":requests-start_requests,"travel":page.get("_view").travel})
