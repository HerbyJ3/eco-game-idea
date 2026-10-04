extends RefCounted
## Facing, walk frame, pose and frame selection, sprite height (spec sprite-view.md 4.2 to 4.4).


## Direction from a vector (y down): front or back when vertical dominates by walk.vertical_dominance, else side
## (mirrored when moving left).
static func facing_vec(v: Vector2, art: Dictionary) -> Dictionary:
	if absf(v.y) > absf(v.x) * float(art.walk.vertical_dominance):
		return {"dir": "front" if v.y > 0.0 else "back", "mirror": false}
	return {"dir": "side", "mirror": v.x < 0.0}


static func facing(heading_rad: float, art: Dictionary) -> Dictionary:
	return facing_vec(Vector2(cos(heading_rad), sin(heading_rad)), art)


## A being in a tunnel walks p1 to p2 when from_a, else p2 to p1.
static func transit_facing(p1: Vector2, p2: Vector2, from_a: bool, art: Dictionary) -> Dictionary:
	return facing_vec((p2 - p1) if from_a else (p1 - p2), art)


## Frame index 0..walk.frames-1 from the walk phase in radians.
static func walk_frame(phase: float, art: Dictionary) -> int:
	var n := int(art.walk.frames)
	return int(floor(phase / TAU * n)) % n


## The frame name if the sheet has it, else idle_front (the construction sheet has no idle_side).
static func resolve_frame(sheet: String, frame: String, art: Dictionary) -> String:
	var rows: Dictionary = art.sheets.rows
	for row in rows:
		if String(row).begins_with("walk_") and frame.begins_with(String(row) + "_"):
			var k := frame.trim_prefix(String(row) + "_")
			return frame if k.is_valid_int() and int(k) < int(art.walk.frames) else "idle_front"
	return frame if frame in art.sheets[sheet].extras else "idle_front"


## World px height of a colonist: Earth-born base, Mars-born multiplier, interior multiplier.
static func height_px(earth_born: bool, interior: bool, art: Dictionary) -> float:
	var c: Dictionary = art.colonist
	var h := float(c.height_px)
	if not earth_born:
		h *= float(c.mars_born_scale)
	if interior:
		h *= float(c.interior_scale)
	return h


## 0 for the first half of each period of 1/hz seconds, 1 for the second (the alternation of weld, dig).
static func _alt(real_time: float, hz: float) -> int:
	return int(floor(real_time * 2.0 * hz)) % 2


static func _sleeping_id(d: Dictionary, art: Dictionary) -> String:
	return "character.sleeping.%s.%d" % [d.role, int(d.id) % int(art.optional.sleeping.poses)]


## Picks sheet, frame, mirror and rotation (first matching row of the spec 4.4 table).
## d: state, suit_kind, role, id, load, wait_h, after, returning, moving, facing {dir, mirror}, face (+1/-1),
## real_time, walk_frame, talking, speaks_first. man: the manifest {entries}.
static func pose_frame(d: Dictionary, art: Dictionary, man: Dictionary) -> Dictionary:
	var suit: String = d.suit_kind
	var sheet_key := "jumpsuit" if suit == "none" else suit
	var out := {"sheet": ("character.jumpsuit." + String(d.role)) if suit == "none" else ("character." + suit),
			"frame": "idle_front", "mirror": false, "rotate_deg": 0.0}
	var rt := float(d.real_time)
	var pausing := float(d.wait_h) > SimWorld.STEP_EPS
	var face_mirror := int(d.face) < 0
	if d.state == "sleep":
		var sid := _sleeping_id(d, art)
		var e: Dictionary = man.entries.get(sid, {})
		if not bool(e.get("placeholder", true)) and e.get("file") != null:
			out.sheet = sid
			out.frame = "sleep"
		else:
			out.rotate_deg = float(art.colonist.sleeper_rotation_deg)
		return out
	var frame := "idle_front"
	var mirror := false
	if suit == "construction" and d.state == "work" and pausing:
		frame = "weld_1" if _alt(rt, float(art.walk.weld_hz)) == 0 else "weld_2"
		mirror = face_mirror
	elif suit == "eva" and d.state == "mining" and pausing:
		frame = "dig" if _alt(rt, float(art.walk.dig_hz)) == 0 else "idle_side"
		mirror = face_mirror
	elif (suit == "eva" and float(d.load) > 0.0) \
			or (suit == "construction" and d.state == "eva" and d.after == "work" and not d.returning):
		frame = "carry"
		mirror = bool(d.facing.mirror) if d.moving else face_mirror
	elif suit == "none" and d.talking:
		var turn := int(floor(rt / float(art.interior.talk_phase_s))) % 2
		frame = "talk" if (turn == 0) == bool(d.speaks_first) else "idle_front"
	elif d.moving:
		frame = "walk_%s_%d" % [d.facing.dir, int(d.walk_frame)]
		mirror = bool(d.facing.mirror)
	out.frame = resolve_frame(sheet_key, frame, art)
	out.mirror = mirror
	return out
