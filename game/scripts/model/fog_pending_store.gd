class_name FogPendingStore
extends RefCounted
## Fog-only write-ahead journal. Never stores a session token or an automatic route.
## fflush/rename alone is not power-loss durability: synchronize file AND directory.
var path := "user://fog_pending_v1.json"
var synchronize: Callable
var error := ""

func _parse(text: String) -> Variant:
	var parser:=JSON.new()
	return parser.data if parser.parse(text)==OK else null

func _fail(message: String) -> Dictionary:
	error=message
	return {"ok":false,"error":message}

func _sync(file_path: String) -> bool:
	if synchronize.is_valid(): return bool(synchronize.call(file_path))
	var output: Array=[]
	if OS.get_name()=="Linux":
		var executable := "/usr/bin/sync" if FileAccess.file_exists("/usr/bin/sync") else "/bin/sync"
		var paths:=PackedStringArray([file_path])
		if DirAccess.dir_exists_absolute(file_path):
			# Godot may just have created ~/.local/share/<app>; persist that hierarchy.
			var parent:=file_path
			var home:=OS.get_environment("HOME").simplify_path()
			while parent!=home and parent!="/":
				parent=parent.get_base_dir();paths.append(parent)
		return FileAccess.file_exists(executable) and OS.execute(executable,paths,output,true)==0
	if OS.get_name()=="Android":
		var paths:=PackedStringArray(["fsync",file_path])
		if DirAccess.dir_exists_absolute(file_path): paths.append(file_path.get_base_dir())
		return FileAccess.file_exists("/system/bin/toybox") and OS.execute("/system/bin/toybox",paths,output,true)==0
	return false # Unsupported platforms must not silently fall back to fflush.

func _valid_identity(identity: Variant) -> bool:
	if not identity is Dictionary: return false
	for field in ["server","playerId","mapId","movePath","reconcilePath"]:
		if not identity.get(field) is String or str(identity[field]).is_empty(): return false
	var prefix := "/api/v1/me/fog/%s/" % str(identity.mapId).uri_encode()
	return identity.movePath==prefix+"move" and identity.reconcilePath==prefix+"reconcile"

func _valid_body(body: Variant) -> bool:
	if not body is Dictionary or body.get("protocol")!="fog-step-v1": return false
	if not body.get("stepId") is String or str(body.stepId).length()<8 or str(body.stepId).length()>120: return false
	for c in str(body.stepId):
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	if not body.get("expectedRevision") is String or str(body.expectedRevision).length()!=64 or not str(body.expectedRevision).is_valid_hex_number(): return false
	if not body.get("expectedFrom") is Dictionary: return false
	for v in [body.get("x"),body.get("y"),body.expectedFrom.get("x"),body.expectedFrom.get("y")]:
		if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=floor(float(v)): return false
	return true

func _valid_fog(fog: Variant) -> bool:
	if not fog is Dictionary or fog.get("protocol")!="fog-step-v1" or not fog.get("mapId") is String: return false
	if not fog.get("revision") is String or str(fog.revision).length()!=64 or not str(fog.revision).is_valid_hex_number(): return false
	if not fog.get("pos") is Dictionary: return false
	for v in [fog.pos.get("x"),fog.pos.get("y"),fog.get("rows"),fog.get("cols"),fog.get("travelPoints")]:
		if not (v is int or v is float) or not is_finite(float(v)) or float(v)!=floor(float(v)): return false
	if fog.rows<=0 or fog.cols<=0 or fog.pos.x<0 or fog.pos.y<0 or fog.pos.x>=fog.cols or fog.pos.y>=fog.rows or fog.travelPoints<0: return false
	return fog.get("revealed") is Array and fog.get("blocks") is Array and fog.get("objects") is Array

func key(identity: Dictionary) -> String:
	return JSON.stringify([identity.server,identity.playerId,identity.mapId]).sha256_text()

func read_all() -> Dictionary:
	error=""
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path+".tmp"): return _fail("行走记录写入中断，已锁定移动，请保留存档联系维护")
		return {"ok":true,"slots":{}}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: return _fail("无法读取行走记录，已停止移动")
	if file.get_length()>2097152:
		file.close();return _fail("行走记录异常，已停止移动")
	var raw:=file.get_as_text();file.close()
	var wrapper: Variant=_parse(raw)
	if not wrapper is Dictionary or wrapper.get("version")!=1 or not wrapper.get("payload") is String or wrapper.get("sha256")!=str(wrapper.get("payload","")).sha256_text():
		return _fail("行走记录损坏，已锁定移动，请保留存档联系维护")
	var data: Variant=_parse(wrapper.payload)
	if not data is Dictionary or not data.get("slots") is Dictionary: return _fail("行走记录结构异常，已停止移动")
	for id in data.slots:
		var record: Variant=data.slots[id]
		if not record is Dictionary or not _valid_identity(record.get("identity")) or key(record.identity)!=id or not _valid_body(record.get("body")) or not record.get("pending") is bool:
			return _fail("行走记录身份异常，已停止移动")
		if not record.pending:
			var terminal: Variant=record.get("terminal")
			if not terminal is Dictionary or not _valid_fog(terminal.get("fog")) or not terminal.get("step") is Dictionary or terminal.step.get("id")!=record.body.stepId or not terminal.step.get("status") in ["committed","cancelled","rejected"] or terminal.fog.get("mapId")!=record.identity.mapId or terminal.fog.get("protocol")!="fog-step-v1":
				return _fail("行走终态记录异常，已停止移动")
	return {"ok":true,"slots":data.slots}

func _write(slots: Dictionary) -> bool:
	var payload:=JSON.stringify({"slots":slots})
	var bytes:=JSON.stringify({"version":1,"payload":payload,"sha256":payload.sha256_text()}).to_utf8_buffer()
	var temp:=path+".tmp"
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:
		_fail("无法保存行走记录，未派发移动");return false
	var written:=file.store_buffer(bytes)
	file.flush()
	var good:=written and file.get_error()==OK
	file.close()
	var absolute:=ProjectSettings.globalize_path(path)
	if not good or not _sync(ProjectSettings.globalize_path(temp)):
		_fail("行走记录无法可靠写盘，已停止移动");return false
	if FileAccess.get_file_as_bytes(temp)!=bytes:
		_fail("行走临时记录校验失败，旧记录已保留，未派发移动");return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),absolute)!=OK:
		_fail("行走记录替换失败，已停止移动");return false
	if not _sync(absolute.get_base_dir()):
		_fail("行走记录目录同步失败，已停止移动");return false
	var check:=read_all()
	if not bool(check.get("ok",false)) or FileAccess.get_file_as_bytes(path)!=bytes:
		_fail("行走记录校验失败，已停止移动");return false
	return true

func begin(identity: Dictionary, body: Dictionary) -> bool:
	if not _valid_identity(identity) or not _valid_body(body):
		_fail("行走记录身份缺失，已停止移动");return false
	var journal:=read_all()
	if not bool(journal.get("ok",false)): return false
	for record in journal.slots.values():
		if record.pending and record.identity.playerId==identity.playerId:
			_fail("上一步尚未确认，暂不能继续行走");return false
	journal.slots[key(identity)]={"identity":identity.duplicate(true),"body":body.duplicate(true),"pending":true}
	return _write(journal.slots)

func finish(identity: Dictionary, body: Dictionary, result: Dictionary) -> bool:
	var journal:=read_all()
	if not bool(journal.get("ok",false)): return false
	var id:=key(identity)
	var record: Dictionary=journal.slots.get(id,{})
	if record.is_empty() or record.get("body")!=_parse(JSON.stringify(body)) or record.get("identity")!=identity:
		_fail("行走记录已变化，已停止移动");return false
	var fog: Dictionary=result.get("fog",{})
	var step: Dictionary=result.get("step",{})
	if not _valid_fog(fog) or fog.get("mapId")!=identity.mapId or fog.get("protocol")!="fog-step-v1" or step.get("id")!=body.stepId or not step.get("status") in ["committed","cancelled","rejected"]:
		_fail("服务端行走终态不完整，已停止移动");return false
	# One durable transition retains both the original body and current authority.
	record.pending=false;record.terminal={"fog":fog.duplicate(true),"step":step.duplicate(true)}
	journal.slots[id]=record
	return _write(journal.slots)
