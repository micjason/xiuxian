extends Control
var page: Control
var config: Dictionary
func _ready() -> void:
	call_deferred("run")
func post(path: String,body: Dictionary) -> Dictionary:
	var result: Dictionary=await get_tree().root.get_node("ApiClient").request_json(HTTPClient.METHOD_POST,path,body,PlayerApi.token(),str(body.get("stepId","")))
	print("RECOVERY_HTTP ",path.get_file()," code=",result.get("code",0)," status=",result.get("step",{}).get("status","none"))
	if str(config.phase)=="lost" and path.ends_with("/move"):
		print("COMMITTED_RESPONSE_DROPPED")
		return {"code":0}
	return result
func run() -> void:
	config=JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("FOG_RESTART_CONFIG")))
	if str(config.phase) in ["issue","lost"]:
		PlayerApi.save_token(str(config.token))
		PlayerApi.save_account("restart-fixture",str(config.playerId))
	else:
		# Test the existing login's crash window: token switched, old account cache remains.
		if bool(config.get("resumeToken",false)): PlayerApi.save_token(str(config.token))
		if PlayerApi.token().is_empty() or (not bool(config.get("allowStaleAccountCache",false)) and str(PlayerApi.account().get("playerId",""))!=str(config.playerId)):
			print("DISK_SESSION_MISSING");get_tree().quit(4);return
		print("AUTH_RESUMED_FROM_DISK")
	var prepared_by_main:=false
	if bool(config.get("normalMain",false)):
		var screen: Control=load("res://scenes/main.tscn").instantiate()
		add_child(screen)
		page=screen.get("_fog_page")
		await screen.call("_open_fog")
		prepared_by_main=str(screen.get("_page"))=="fog"
		if not prepared_by_main:
			print("MAIN_ENTRANCE_STATE page=",str(screen.get("_page"))," ledger_error=",str(page.pending_store.error)," account_present=",not str(PlayerApi.account().get("playerId","")).is_empty())
			print("RECOVERY_FROZEN");get_tree().quit(2);return
		print("NORMAL_MAIN_ENTRANCE_RECOVERED")
	else:
		page=load("res://scripts/ui/pages/fog_map_page.gd").new();page.size=Vector2(1080,1920);add_child(page)
		page.transport=post
		var state: Dictionary=await get_tree().root.get_node("ApiClient").request_json(HTTPClient.METHOD_GET,"/api/v1/me/fog",{},PlayerApi.token())
		page.bind_fog(state)
	if str(config.phase) in ["issue","lost"]:
		page.call("_on_cell",3,9)
		if page.get("_runner_running"): await page.route_idle
		await get_tree().create_timer(600).timeout
		get_tree().quit(3)
		return
	var ok: bool=prepared_by_main or await page.prepare_open()
	if not ok:
		print("RECOVERY_FROZEN");get_tree().quit(2);return
	print("RECOVERY_READY")
	if bool(config.get("recoverOnly",false)):
		var recovered: Dictionary=await get_tree().root.get_node("ApiClient").request_json(HTTPClient.METHOD_GET,"/api/v1/me/fog",{},PlayerApi.token())
		var output:=FileAccess.open(str(config.output),FileAccess.WRITE);output.store_string(JSON.stringify(recovered));output.close()
		get_tree().quit(0);return
	while not FileAccess.file_exists(str(config.go)):
		await get_tree().create_timer(0.02).timeout
	page.call("_on_cell",int(config.target.x),int(config.target.y))
	if page.get("_runner_running"): await page.route_idle
	var final: Dictionary=await get_tree().root.get_node("ApiClient").request_json(HTTPClient.METHOD_GET,"/api/v1/me/fog",{},PlayerApi.token())
	var file:=FileAccess.open(str(config.output),FileAccess.WRITE)
	file.store_string(JSON.stringify(final));file.close()
	print("RESTART_FINAL_RECORDED")
	get_tree().quit(0)
