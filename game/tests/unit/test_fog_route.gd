extends GutTest
var route: Script
func before_each() -> void:
	route = load("res://scripts/model/fog_route.gd")
	assert_not_null(route, "known-region planner exists")
func view(w: int = 6, h: int = 4) -> Dictionary:
	var r: Array = []
	for y in range(h):
		for x in range(w): r.append("%d,%d" % [x,y])
	return {"cols":w,"rows":h,"pos":{"x":0,"y":1},"revealed":r,"blocks":[],"objects":[],"explore_full":false}
func plan(v: Dictionary, x: int, y: int, s: Array = []) -> Dictionary:
	if route == null: return {}
	return route.plan(v,Vector2i(x,y),v.revealed if s.is_empty() else s)
func test_u_wall_uses_shortest_detour_not_three_or_five_limit() -> void:
	if route == null: return
	var v := view()
	v.blocks=[{"x":1,"y":0},{"x":1,"y":1},{"x":1,"y":2}]
	var p := plan(v,2,1)
	assert_true(p.ok)
	assert_eq(p.path.size(),6)
	assert_eq(p.path[-1],Vector2i(2,1))
func test_visible_island_and_unknown_adjacent_rejected() -> void:
	if route == null: return
	var v := view();v.revealed=["0,1","2,1"]
	assert_false(plan(v,2,1).ok)
	assert_false(plan(v,1,1).ok)
func test_snapshot_does_not_grow_after_new_reveal() -> void:
	if route == null: return
	var v := view();var s: Array=["0,1","1,1"]
	assert_false(plan(v,2,1,s).ok)
func test_object_target_stops_at_shortest_legal_neighbor() -> void:
	if route == null: return
	var v := view();v.objects=[{"id":"c","kind":"chest","x":3,"y":1,"opened":false}]
	var p := plan(v,3,1)
	assert_true(p.ok);assert_eq(p.path, [Vector2i(1,1),Vector2i(2,1)])
	assert_eq(p.object.id,"c")
func test_living_objects_not_traversed_but_can_be_routed_around() -> void:
	if route == null: return
	for kind in ["chest","monster","event"]:
		var v := view();v.objects=[{"id":"o","kind":kind,"x":1,"y":1}]
		var p := plan(v,2,1)
		assert_eq(p.path.size(),4)
		assert_false(Vector2i(1,1) in p.path)
func test_completed_objects_passable_and_incidental_adjacent_monster_not_triggered() -> void:
	if route == null: return
	var v := view();v.objects=[{"id":"m","kind":"monster","x":1,"y":1,"defeated":true},{"id":"m2","kind":"monster","x":1,"y":0}]
	var p := plan(v,2,1)
	assert_eq(p.path.size(),2);assert_true(p.object.is_empty())
func test_guard_explicit_prefull_stand_but_full_approach_confirm() -> void:
	if route == null: return
	var v := view();v.objects=[{"id":"m_guard","kind":"exit","x":2,"y":1}]
	assert_eq(plan(v,2,1).path[-1],Vector2i(2,1))
	v.explore_full=true
	var p := plan(v,2,1)
	assert_eq(p.path[-1],Vector2i(1,1));assert_eq(p.object.id,"m_guard")
func test_unreachable_object_and_out_of_bounds_have_feedback() -> void:
	if route == null: return
	var v := view();v.revealed=["0,1","3,1"];v.objects=[{"id":"c","kind":"chest","x":3,"y":1}]
	assert_false(plan(v,3,1).ok);assert_false(plan(v,6,1).ok)
