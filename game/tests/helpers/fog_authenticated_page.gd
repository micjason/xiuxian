extends FogMapPage
var authenticated_id := ""
func _fetch_identity() -> Dictionary:
	return {"code":200,"playerId":authenticated_id if not authenticated_id.is_empty() else str(PlayerApi.account().get("playerId",""))}
