extends RefCounted
## Door want, easing and leaf geometry (spec sprite-view.md 5.2). Reads beings, never writes them.


## True when this finished building's door should open: a miner suiting up inside (to_door, suit_up, mine or
## mine_intent, no job: builders suit up at the tunnel end), or an eva being that left from this building and is within
## door.radius_px of its door. Never reads `mine` for the outside case (it is null on the return trip).
static func want_open(b: Buildings.Building, beings: Array, tile_px: float, art: Dictionary) -> bool:
	if not b.finished():
		return false
	var door := b.door(tile_px)
	var radius := float(art.door.radius_px)
	for g in beings:
		if g.building_id != b.id:
			continue
		if g.state == "to_door":
			if g.suit_up and g.job == null and (g.mine != null or g.mine_intent != null):
				return true
		elif g.x != null and g.is_outside() and g.suit_kind() == "eva":
			if Vector2(g.x, g.y).distance_to(door) < radius:
				return true
	return false


## One frame of door easing in real time (independent of sim speed and pause). dt is clamped to door.max_dt_s.
static func ease_open(open: float, want: bool, dt: float, art: Dictionary) -> float:
	var d: Dictionary = art.door
	var step := minf(minf(dt, float(d.max_dt_s)) * float(d.ease_rate_per_s), 1.0)
	return clampf(open + ((1.0 if want else 0.0) - open) * step, 0.0, 1.0)


## Leaf offsets in px relative to the door rect, plus the clip rect (the door rect at the origin).
## split: {left, right, clip}; rollup: {panel, clip}.
static func leaf_offsets(open: float, mode: String, door_size: Vector2, art: Dictionary) -> Dictionary:
	var clip := Rect2(Vector2.ZERO, door_size)
	var travel := float(art.door.travel_frac)
	if mode == "rollup":
		return {"panel": Vector2(0.0, -open * door_size.y * travel), "clip": clip}
	var off := open * door_size.x * 0.5 * travel
	return {"left": Vector2(-off, 0.0), "right": Vector2(off, 0.0), "clip": clip}
