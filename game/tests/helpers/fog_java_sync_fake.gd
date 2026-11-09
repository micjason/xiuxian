extends RefCounted
var events: Array=[]
var fail_at: String=""
var exception: RefCounted
var descriptor:=RefCounted.new()
func wrap(_name: String) -> Variant:
	events.append("wrap")
	exception=RefCounted.new() if fail_at=="wrap" else null
	return null if exception else self
func get_exception() -> Variant:
	return exception
func open(path: String,flags: int,mode: int) -> Variant:
	events.append(["open",path,flags,mode])
	exception=RefCounted.new() if fail_at=="open" else null
	return null if exception else descriptor
func fsync(_descriptor: Object) -> void:
	events.append("fsync")
	exception=RefCounted.new() if fail_at=="fsync" else null
func close(_descriptor: Object) -> void:
	events.append("close")
	exception=RefCounted.new() if fail_at=="close" else null
