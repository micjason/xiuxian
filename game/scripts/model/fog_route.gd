class_name FogRoute
extends RefCounted
## Pure four-way shortest path inside a click-time revealed snapshot.
const DIRS := [Vector2i(-1,0), Vector2i(1,0), Vector2i(0,-1), Vector2i(0,1)]

static func object_at(view: Dictionary, cell: Vector2i) -> Dictionary:
	for obj in view.get("objects", []):
		if int(obj.get("x",-1)) == cell.x and int(obj.get("y",-1)) == cell.y:
			var kind := str(obj.get("kind",""))
			if (kind == "chest" and not bool(obj.get("opened",false))) or (kind == "monster" and not bool(obj.get("defeated",false))) or (kind == "event" and not bool(obj.get("done",false))) or (kind == "exit" and not bool(obj.get("passed",obj.get("defeated",false)))):
				return obj
	return {}

static func passable(view: Dictionary, cell: Vector2i, guard_goal: Vector2i = Vector2i(-1,-1)) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= int(view.get("cols",0)) or cell.y >= int(view.get("rows",0)):
		return false
	if FogMapView.is_blocked(view,cell.x,cell.y): return false
	var obj := object_at(view,cell)
	return obj.is_empty() or (cell == guard_goal and str(obj.get("kind","")) == "exit" and not bool(view.get("explore_full",false)))

static func plan(view: Dictionary, target: Vector2i, snapshot: Array) -> Dictionary:
	var fail := {"ok":false,"path":[],"object":{},"error":"目标不可达，请选择已揭开且连通的道路"}
	if not FogMapView.cell_key(target.x,target.y) in snapshot:
		fail.error="迷雾未散，请先走到已揭开的边缘"
		return fail
	var start := Vector2i(int(view.get("pos",{}).get("x",0)),int(view.get("pos",{}).get("y",0)))
	if not FogMapView.cell_key(start.x,start.y) in snapshot: return fail
	var obj := object_at(view,target)
	var guard_goal := Vector2i(-1,-1)
	if str(obj.get("kind","")) == "exit" and not bool(view.get("explore_full",false)):
		guard_goal=target
		obj={}
	var goals: Array = []
	if obj.is_empty():
		if not passable(view,target,guard_goal): return fail
		goals.append(target)
	else:
		for d in DIRS:
			var n: Vector2i = target+d
			if FogMapView.cell_key(n.x,n.y) in snapshot and passable(view,n): goals.append(n)
		if start == target: goals.append(start)
	var queue: Array = [start]
	var prev: Dictionary = {start:start}
	var index := 0
	while index < queue.size():
		var c: Vector2i=queue[index];index+=1
		if c in goals:
			var path: Array=[]
			while c != start:
				path.push_front(c);c=prev[c]
			return {"ok":true,"path":path,"object":obj,"error":""}
		for d in DIRS:
			var n: Vector2i=c+d
			if prev.has(n) or not FogMapView.cell_key(n.x,n.y) in snapshot or not passable(view,n,guard_goal): continue
			prev[n]=c;queue.append(n)
	return fail
