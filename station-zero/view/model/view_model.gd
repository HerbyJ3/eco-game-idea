extends RefCounted
## The view model facade (spec sprite-view.md 4 to 9): everything the world view needs to draw one frame, as plain data.
##
## It reads the sim (world.beings, buildings, resources, clock) and owns all animation state, keyed by being or
## building id. It never writes the sim and never steps it. Its randomness lives in view-owned
## RandomNumberGenerator instances (particles, interior slots) seeded from art.json ids, never in the sim's SimRng.
## One update(dt_real) per rendered frame; nothing depends on sim speed.

const Camera = preload("res://view/model/camera.gd")
const BeingAnim = preload("res://view/model/being_anim.gd")
const BuildingAnim = preload("res://view/model/building_anim.gd")
const Construction = preload("res://view/model/construction.gd")
const Doors = preload("res://view/model/doors.gd")
const FacingPose = preload("res://view/model/facing_pose.gd")
const Fit = preload("res://view/model/fit.gd")
const InteriorSlots = preload("res://view/model/interior_slots.gd")
const Light = preload("res://view/model/light.gd")
const Particles = preload("res://view/model/particles.gd")
const Selection = preload("res://view/model/selection.gd")

var world: SimWorld
var art: Dictionary
## The manifest {schema, entries}.
var man: Dictionary
## Real seconds the model has been updated for (drives pulses, doors, particles; independent of sim time).
var real_time := 0.0
var camera: Camera
var selection: Selection
var particles: Particles
## True while the debug dot map is shown instead of the sprite view.
var debug_map := false
## World rect that culls interiors; the default empty Rect2 means no culling.
var camera_rect := Rect2()
## Beings that could not be placed (outside without a position, a transit with no corridor). Must stay 0.
var skipped := 0

var _tile_px: float
var _beings: Dictionary = {}
var _buildings: Dictionary = {}
var _interiors: Dictionary = {}
var _interior_rects: Dictionary = {}
var _geometry: Dictionary = {}
var _building_count := -1


func _init(world_in: SimWorld, art_in: Dictionary, man_in: Dictionary) -> void:
	world = world_in
	art = art_in
	man = man_in
	_tile_px = float(SimData.buildings().tile_px)
	camera = Camera.new(art, _layout_union())
	selection = Selection.new(art)
	particles = Particles.new(art, 0)
	_building_count = world.buildings.list.size()


# ---------------------------------------------------------------- queries

func building(id: int) -> BuildingAnim:
	return _buildings.get(id)


## {pos (feet, render position), height_px, phase, moving, lamp_level, visible, inside, pose, facing, face} or null.
func being(id: int) -> Variant:
	return _beings.get(id)


## The interior model of a building while its roof is (partly) open and it is in camera_rect, else null.
func interior(building_id: int) -> InteriorSlots:
	return _interiors.get(building_id)


## Sprite rect of an open interior in world px, Rect2() when closed.
func interior_rect(building_id: int) -> Rect2:
	return _interior_rects.get(building_id, Rect2())


## Footprint rect of a building in world px (the logic rectangle: taps, stakes, work area).
func footprint_rect(b: Buildings.Building) -> Rect2:
	return Rect2(b.tx * _tile_px, b.ty * _tile_px, b.tw * _tile_px, b.th * _tile_px)


## Where the finished kind's exterior sprite is drawn inside the footprint (the fit rect of 4.1).
func sprite_rect(b: Buildings.Building) -> Rect2:
	return _geo(b).ext


func _geo(b: Buildings.Building) -> Dictionary:
	if not _geometry.has(b.id):
		var foot := footprint_rect(b)
		var e: Dictionary = man.entries["building.%s.base" % b.kind]
		var fit := Fit.fit_sprite(foot, Vector2(e.w, e.h), Vector2(e.pivot[0], e.pivot[1]), art)
		_geometry[b.id] = {"foot": foot, "ext": fit.rect}
	return _geometry[b.id]


## Union of the building footprints; the founder layout's when the world has no buildings.
func _layout_union() -> Rect2:
	var list := world.buildings.list
	if list.is_empty():
		var founders := Buildings.new()
		founders.create_layout()
		list = founders.list
	var union := Rect2()
	for i in list.size():
		var r := footprint_rect(list[i])
		union = r if i == 0 else union.merge(r)
	return union


func _layout_centroid() -> Vector2:
	return _layout_union().get_center()


# ---------------------------------------------------------------- input

## Discrete key actions of the sprite view. Pan and zoom keys are continuous and go to the camera directly.
func press_key(key_name: String) -> void:
	var action := camera.action_for_key(key_name)
	if action == "toggle_debug_map":
		debug_map = not debug_map
		return
	if debug_map:
		return
	match action:
		"reset":
			camera.reset(_layout_centroid())
		"deselect":
			selection.deselect()
		"follow_selected":
			camera.follow = not camera.follow


## A press and release in screen px: a tap selects (or toggles peek, or deselects); a longer move is a drag, ignored.
func tap_screen(press: Vector2, release: Vector2, viewport: Vector2) -> void:
	if selection.is_tap(press, release):
		selection.tap(camera.screen_to_world(release, viewport), world)


# ---------------------------------------------------------------- update

## One refresh. Reads the sim, writes only view state.
func update(dt_real: float) -> void:
	real_time += dt_real
	var w := world
	var h := w.clock.mars_hour(w.t)
	if w.buildings.list.size() != _building_count:
		_building_count = w.buildings.list.size()
		camera.set_union(_layout_union())
	_follow_selection()
	camera.update(dt_real)
	selection.update(dt_real, camera.zoom, w)
	var sources: Array = []
	var by_building := _bucket_beings()
	var crew := _crew_size()
	_update_buildings(dt_real, by_building, crew, sources)
	_update_beings(dt_real, h, sources)
	_forget_gone()
	particles.update(dt_real, sources)


func _follow_selection() -> void:
	if not camera.follow or selection.selected == 0:
		return
	var b := world.buildings.get_building(selection.selected)
	if b != null:
		camera.follow_target = footprint_rect(b).get_center()


func _bucket_beings() -> Dictionary:
	var out := {}
	for g in world.beings:
		if out.has(g.building_id):
			out[g.building_id].append(g)
		else:
			out[g.building_id] = [g]
	return out


## Beings in state work on the current site (derived each refresh, like the sim does).
func _crew_size() -> int:
	var site := world.buildings.site
	if site == null:
		return 0
	var n := 0
	for g in world.beings:
		if g.state == "work" and g.job == site:
			n += 1
	return n


func _update_buildings(dt: float, by_building: Dictionary, crew: int, sources: Array) -> void:
	var w := world
	var site := w.buildings.site
	for b in w.buildings.list:
		if not _buildings.has(b.id):
			_buildings[b.id] = BuildingAnim.new(art, b.id, b.kind)
		var mine: Array = by_building.get(b.id, [])
		_buildings[b.id].update(dt, Doors.want_open(b, mine, _tile_px, art), b.offline)
		var geo := _geo(b)
		if selection.cut(b.id, camera.zoom) > 0.0 and b.finished() and _in_view(geo.foot):
			_update_interior(b, mine, dt)
		else:
			_interiors.erase(b.id)
			_interior_rects.erase(b.id)
		if b.offline:
			sources.append({"key": "flicker:%d" % b.id, "kind": "flicker", "rect": geo.foot})
		if site != null and site.building_id == b.id and not b.finished():
			sources.append({"key": "weld_seam:%d" % b.id, "kind": "weld_seam", "rect": geo.ext,
					"f": float(Construction.phases(b.built, art).f), "crew": crew})


func _in_view(rect: Rect2) -> bool:
	return camera_rect.size == Vector2.ZERO or camera_rect.intersects(rect)


func _update_interior(b: Buildings.Building, mine: Array, dt: float) -> void:
	var e: Dictionary = man.entries.get("building.%s.interior" % b.kind, {})
	if e.is_empty():
		return
	if not _interiors.has(b.id):
		var rect: Rect2 = Fit.fit_sprite(_geo(b).ext, Vector2(e.w, e.h), Vector2(e.pivot[0], 1.0), art).rect
		_interior_rects[b.id] = rect
		_interiors[b.id] = InteriorSlots.new(art, b.id, b.kind, rect.size)
	var inside: Array = []
	for g in mine:
		if g.state == "idle" or g.state == "to_door" or g.state == "sleep":
			inside.append({"id": g.id, "state": g.state, "suit_up": g.suit_up})
	_interiors[b.id].update(dt, inside)


func _new_record(g: Being) -> Dictionary:
	return {"anim": BeingAnim.new(art, g.id), "pos": Vector2.ZERO, "height_px": 0.0, "phase": 0.0, "moving": false,
			"lamp_level": 0.0, "visible": false, "inside": false, "pose": {}, "facing": {"dir": "front", "mirror": false},
			"face": 1, "space": ""}


func _update_beings(dt: float, h: float, sources: Array) -> void:
	var talk := _talk_flags()
	for g in world.beings:
		if not _beings.has(g.id):
			_beings[g.id] = _new_record(g)
		_update_being(g, _beings[g.id], dt, h, talk, sources)


## Places one being and, when it is drawn, picks its pose. A being that is not drawn skips pose and lamp work.
func _update_being(g: Being, rec: Dictionary, dt: float, h: float, talk: Dictionary, sources: Array) -> void:
	var anim: BeingAnim = rec.anim
	var space := ""
	var feet := Vector2.ZERO
	var heading: Variant = null
	var outside := g.is_outside()
	if outside:
		if g.x == null:
			skipped += 1
		else:
			space = "outside"
			feet = Vector2(g.x, g.y)
			heading = g.heading
	elif g.state == "transit":
		var c := world.buildings.get_building(int(g.corridor_id)) if g.corridor_id != null else null
		if c == null or c.corridor == null:
			skipped += 1
		else:
			var s := float(g.transit_t) if g.from_a else 1.0 - float(g.transit_t)
			space = "transit"
			feet = (c.corridor.p1 as Vector2).lerp(c.corridor.p2, s)
			rec.facing = FacingPose.transit_facing(c.corridor.p1, c.corridor.p2, g.from_a, art)
	elif _interiors.has(g.building_id):
		var pos: Variant = _interiors[g.building_id].positions().get(g.id)
		if pos != null:
			var rr: Rect2 = _interior_rects[g.building_id]
			space = "interior"
			feet = rr.position + (pos as Vector2) * rr.size
	rec.visible = space != ""
	rec.inside = space == "interior"
	if space == "" and anim.lamp_level == 0.0:
		return
	if space != rec.space:
		anim.reset_samples()
		rec.space = space
	if space != "":
		anim.push_sample(feet, real_time)
		rec.pos = anim.render_pos(real_time)
		rec.phase = anim.phase
		rec.moving = anim.moving_at(real_time)
		rec.height_px = FacingPose.height_px(g.earth_born, space == "interior", art)
	anim.update_lamp(dt, Light.lamp_target(h, outside, outside and g.lamp_on(world), art))
	rec.lamp_level = anim.lamp_level
	if space == "":
		return
	_set_facing(rec, space, heading, anim)
	var t: Dictionary = talk.get(g.id, {})
	rec.pose = FacingPose.pose_frame({"state": g.state, "suit_kind": g.suit_kind(), "role": g.role, "id": g.id,
			"load": g.load, "wait_h": g.wait_h, "after": g.after, "returning": g.returning, "moving": rec.moving,
			"facing": rec.facing, "face": rec.face, "real_time": real_time, "walk_frame": anim.frame_index(),
			"talking": not t.is_empty(), "speaks_first": t.get("first", true)}, art, man)
	if space == "outside" and float(g.wait_h) > SimWorld.STEP_EPS:
		_add_work_source(g, rec, sources)


## Facing and the last horizontal sign (face). Outside beings use the sim heading, transit the tunnel direction
## (set by the caller), interior beings the direction they last moved.
func _set_facing(rec: Dictionary, space: String, heading: Variant, anim: BeingAnim) -> void:
	var horizontal := 0.0
	if space == "outside" and heading != null:
		rec.facing = FacingPose.facing(float(heading), art)
		horizontal = cos(float(heading))
	elif space == "interior":
		rec.facing = FacingPose.facing_vec(anim.move_dir, art) if anim.move_dir != Vector2.ZERO \
				else {"dir": "front", "mirror": false}
		horizontal = anim.move_dir.x
	elif space == "transit":
		horizontal = -1.0 if rec.facing.mirror else 1.0 if rec.facing.dir == "side" else 0.0
	if not is_zero_approx(horizontal):
		rec.face = 1 if horizontal > 0.0 else -1


func _add_work_source(g: Being, rec: Dictionary, sources: Array) -> void:
	var scale_h := float(rec.height_px) / float(art.colonist.height_px)
	var suit := g.suit_kind()
	if suit == "construction" and g.state == "work":
		sources.append({"key": "weld_hand:%d" % g.id, "kind": "weld_hand", "feet": rec.pos, "face": rec.face,
				"scale": scale_h})
	elif suit == "eva" and g.state == "mining":
		var ice: bool = g.mine is Dictionary and g.mine.get("site") != null and g.mine.site.kind == "ice"
		sources.append({"key": "dig:%d" % g.id, "kind": "dig", "feet": rec.pos, "face": rec.face, "scale": scale_h,
				"ice": ice})


## For open interiors: {being id: {first: bool}} for jumpsuit beings pausing at a slot with another non-sleeping being
## within interior.talk_radius_px. The lower id of a pair speaks first.
func _talk_flags() -> Dictionary:
	var out := {}
	var radius := float(art.interior.talk_radius_px)
	for bid in _interiors:
		var model: InteriorSlots = _interiors[bid]
		var rr: Rect2 = _interior_rects[bid]
		var awake: Dictionary = {}
		var pos: Dictionary = model.positions()
		for id in pos:
			if model.slot_of(id).get("type", "") != "bunk":
				awake[id] = rr.position + (pos[id] as Vector2) * rr.size
		for id in awake:
			if not model.paused(id):
				continue
			var nearest := -1
			for other in awake:
				if other != id and (awake[other] as Vector2).distance_to(awake[id]) <= radius \
						and (nearest < 0 or other < nearest):
					nearest = other
			if nearest >= 0:
				out[id] = {"first": id < nearest}
	return out


func _forget_gone() -> void:
	if _beings.size() == world.beings.size():
		return
	var live := {}
	for g in world.beings:
		live[g.id] = true
	for id in _beings.keys():
		if not live.has(id):
			_beings.erase(id)


## A hash of every piece of view state, for equality checks.
func signature() -> String:
	var parts: Array[String] = ["%s|%d|%d|%s|%s" % [str(real_time), skipped, 1 if debug_map else 0, str(camera.zoom),
			str(camera.center)]]
	for id in _beings:
		var r: Dictionary = _beings[id]
		parts.append("g%d|%s|%s|%s|%s|%s" % [id, str(r.pos), str(r.phase), str(r.lamp_level), str(r.pose.get("frame", "")),
				str(r.visible)])
	for id in _buildings:
		var a: BuildingAnim = _buildings[id]
		parts.append("B%d|%s|%s" % [id, str(a.door_open), str(a.power)])
	for id in _interiors:
		parts.append("I%d|%s" % [id, str(_interiors[id].positions())])
	parts.append(str(particles.snapshot()))
	parts.append("%d|%d|%s" % [selection.selected, 1 if selection.peek else 0, str(selection.peek_cut)])
	return "\n".join(parts).sha256_text()
