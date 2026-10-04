extends RefCounted
## Interior being model for one open building (spec sprite-view.md 7.2, 7.3). Positions are invented by the view,
## cosmetic, deterministic by being id and the sequence of real-time steps, never fed back to the sim.
##
## Slots come from art.interiors.<kind>, else art.interiors.default. Sleepers take bunks in ascending id order, then
## floor slots; awake beings each hold a free non-bunk slot, walk to it at interior.walk_px_s, pause
## interior.pause_s, then pick another free slot with their own RNG seeded from (being id, building id). When
## there are more beings than slots the extras share floor slots. Positions are normalized to the interior image.

var art: Dictionary
var building_id: int
## Interior image size in world px (the fitted interior rect).
var size_px: Vector2
var _slots: Array
var _door: Vector2
var _recs: Dictionary = {}
var _drawn: Array[int] = []


func _init(art_in: Dictionary, building_id_in: int, kind: String, size_in: Vector2) -> void:
	art = art_in
	building_id = building_id_in
	size_px = size_in
	var interiors: Dictionary = art.interiors
	var def: Dictionary = interiors.get(kind, interiors["default"])
	_slots = def.slots
	_door = Vector2(def.door[0], def.door[1])


func slots() -> Array:
	return _slots


## Ids of the beings drawn, ascending, at most interior.being_cap.
func drawn_ids() -> Array:
	return _drawn.duplicate()


## {id: Vector2 normalized to the interior image} for the drawn beings.
func positions() -> Dictionary:
	var out := {}
	for id in _drawn:
		out[id] = _recs[id].pos
	return out


## {id, type} of the slot a being holds, {} when it holds none.
func slot_of(id: int) -> Dictionary:
	if not _recs.has(id) or int(_recs[id].slot) < 0:
		return {}
	var s: Dictionary = _slots[int(_recs[id].slot)]
	return {"id": s.id, "type": s.type}


## True while an awake being stands at its slot waiting (the talk pose applies only then).
func paused(id: int) -> bool:
	return _recs.has(id) and bool(_recs[id].waiting)


func _slot_pos(i: int) -> Vector2:
	return Vector2(_slots[i].pos[0], _slots[i].pos[1])


func _is_bunk(i: int) -> bool:
	return _slots[i].type == "bunk"


func _floor_slots() -> Array[int]:
	return _free_floor({})


## Floor slot indices nobody holds, optionally without one index.
func _free_floor(held: Dictionary, skip: int = -1) -> Array[int]:
	var out: Array[int] = []
	for i in _slots.size():
		if i != skip and not _is_bunk(i) and not held.has(i):
			out.append(i)
	return out


## inside: Array of {id, state, suit_up} for the beings of the building that are idle, to_door or sleep.
func update(dt_real: float, inside: Array) -> void:
	var states := _sync(inside)
	var held := {}
	var awake: Array[int] = []
	for id in _drawn:
		if states[id].state == "sleep":
			_lay_down(id, held)
		else:
			awake.append(id)
	for id in awake:
		_keep_or_release(id, held, states[id])
	for id in awake:
		if int(_recs[id].slot) < 0 and not _suiting(states[id]):
			_claim_floor(id, held)
	var step := float(art.interior.walk_px_s) * dt_real
	for id in awake:
		_walk(id, held, states[id], step, dt_real)


static func _suiting(st: Dictionary) -> bool:
	return st.state == "to_door" and bool(st.suit_up)


## Sorts, caps, creates records (at the door) for new beings and drops records of beings that left.
func _sync(inside: Array) -> Dictionary:
	var sorted: Array = inside.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	_drawn = []
	var states := {}
	for e in sorted.slice(0, int(art.interior.being_cap)):
		_drawn.append(int(e.id))
		states[int(e.id)] = e
	for id in _recs.keys():
		if not states.has(id):
			_recs.erase(id)
	for id in _drawn:
		if not _recs.has(id):
			var r := RandomNumberGenerator.new()
			r.seed = ("%d|%d" % [id, building_id]).hash()
			_recs[id] = {"pos": _door, "slot": -1, "pause": -1.0, "waiting": false, "shared": false, "id": id, "rng": r}
	return states


## Sleepers lie in the first free bunk, else on the floor.
func _lay_down(id: int, held: Dictionary) -> void:
	var rec: Dictionary = _recs[id]
	var pick := -1
	for i in _slots.size():
		if _is_bunk(i) and not held.has(i):
			pick = i
			break
	if pick < 0:
		var free := _free_floor(held)
		if free.is_empty():
			free = _floor_slots()
		if not free.is_empty():
			pick = free[0]
	rec.slot = pick
	rec.waiting = false
	rec.shared = false
	if pick >= 0:
		held[pick] = id
		rec.pos = _slot_pos(pick)


## An awake being keeps its floor slot unless another being already holds it (shared ones keep it).
func _keep_or_release(id: int, held: Dictionary, st: Dictionary) -> void:
	var rec: Dictionary = _recs[id]
	var s := int(rec.slot)
	if _suiting(st) or s < 0 or _is_bunk(s) or (held.has(s) and not bool(rec.shared)):
		rec.slot = -1
		rec.waiting = false
		rec.shared = false
		return
	held[s] = id


func _claim_floor(id: int, held: Dictionary) -> void:
	var rec: Dictionary = _recs[id]
	var free := _free_floor(held)
	rec.pause = -1.0
	rec.waiting = false
	if free.is_empty():
		var any := _floor_slots()
		if any.is_empty():
			return
		rec.slot = any[rec.rng.randi_range(0, any.size() - 1)]
		rec.shared = true
		return
	var pick: int = free[rec.rng.randi_range(0, free.size() - 1)]
	rec.slot = pick
	rec.shared = false
	held[pick] = id


func _walk(id: int, held: Dictionary, st: Dictionary, step: float, dt: float) -> void:
	var rec: Dictionary = _recs[id]
	var suiting := _suiting(st)
	var target := _door
	if not suiting:
		if int(rec.slot) < 0:
			return
		target = _slot_pos(int(rec.slot))
	var to_target: Vector2 = (target - (rec.pos as Vector2)) * size_px
	var dist := to_target.length()
	if dist > float(art.interior.slot_reach_px):
		rec.waiting = false
		rec.pos = (rec.pos as Vector2) + (to_target / dist * minf(step, dist)) / size_px
		return
	if suiting:
		return
	rec.waiting = true
	if float(rec.pause) < 0.0:
		rec.pause = _span(rec.rng, art.interior.pause_s)
	rec.pause = float(rec.pause) - dt
	if float(rec.pause) <= 0.0:
		_move_on(rec, held)


## The pause is over: take another free floor slot if there is one, else stay.
func _move_on(rec: Dictionary, held: Dictionary) -> void:
	var old := int(rec.slot)
	var free := _free_floor(held, old)
	rec.pause = -1.0
	if free.is_empty():
		return
	if not bool(rec.shared):
		held.erase(old)
	var pick: int = free[rec.rng.randi_range(0, free.size() - 1)]
	rec.slot = pick
	rec.shared = false
	rec.waiting = false
	held[pick] = rec.id


static func _span(r: RandomNumberGenerator, bounds: Array) -> float:
	return r.randf_range(float(bounds[0]), float(bounds[1]))
