extends "res://scripts/ui/play_screen.gd"
func _get_fog() -> Dictionary:
	await get_tree().create_timer(0.12).timeout
	return {"code":200,"fog":{"protocol":"fog-step-v1","revision":"a".repeat(64),"rows":3,"cols":3,"pos":{"x":1,"y":1},"revealed":["1,1"],"objects":[],"blocks":[],"travelPoints":20}}

func _ready() -> void:
	super._ready()
	_fog_page.identity_provider=Callable(self,"fixture_identity")
func fixture_identity() -> Dictionary:
	return {"code":200,"playerId":str(PlayerApi.account().get("playerId",""))}
