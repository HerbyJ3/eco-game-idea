class_name Resources
extends RefCounted
## Ice fields, regolith pits, spawning, scouting, trip time and launch building.
## Spec: life-support-power.md section 8 (8.1 spawn, 8.2 launch_for, 8.4 scouting) and A2.
## Mining itself arrives in a later step. Numbers come from data/resources.json and data/suits.json.

## An ice field or a regolith pit. Pits have infinite amount.
class Site extends RefCounted:
	## "ice" or "pit". A hauler deposits by kind, so a load from a field that dried is still ice.
	var kind := "pit"
	var x: float
	var y: float
	var amount := INF
	var start := INF
	var dug := 0.0
	var r: float

	func pos() -> Vector2:
		return Vector2(x, y)

## One boot print (spec 8.5). `heavy` marks a being in the construction suit or carrying a load.
class Footprint extends RefCounted:
	var x: float
	var y: float
	var heading: float
	var t: float
	var heavy: bool

## Oldest first, newest last; capped at suits.footprint.cap.
var footprints: Array[Footprint] = []
var ice_fields: Array[Site] = []
var pits: Array[Site] = []
var cfg: Dictionary
var suits: Dictionary
var _buildings: Buildings
var _rng: SimRng


## Holds Buildings and the rng only (never the world: that would be a reference cycle).
func _init(buildings_in: Buildings, rng_in: SimRng) -> void:
	cfg = SimData.resources()
	suits = SimData.suits()
	_buildings = buildings_in
	_rng = rng_in


# ---------------------------------------------------------------- test seams

func add_ice_field(x: float, y: float, amount: float, r: float) -> Site:
	var f := Site.new()
	f.kind = "ice"
	f.x = x
	f.y = y
	f.amount = amount
	f.start = amount
	f.r = r
	ice_fields.append(f)
	return f


func add_pit(x: float, y: float) -> Site:
	var p := Site.new()
	p.x = x
	p.y = y
	p.r = float(cfg.pit.radius_px)
	pits.append(p)
	return p


# ---------------------------------------------------------------- trips

## The online building whose door is nearest the site (tie: lowest id), or null.
func launch_for(site: Site) -> Buildings.Building:
	var tp: float = float(_buildings.cfg.tile_px)
	var best: Buildings.Building = null
	var best_d := INF
	for b in _buildings.list:
		if not b.online():
			continue
		var d := site.pos().distance_to(b.door(tp))
		if d < best_d:
			best_d = d
			best = b
	return best


## Round trip walk plus overhead: 2 x (d_launch + r) / eva_speed + overhead. INF with no online building.
func trip_time(site: Site) -> float:
	var b := launch_for(site)
	if b == null:
		return INF
	var d := site.pos().distance_to(b.door(float(_buildings.cfg.tile_px)))
	return 2.0 * (d + site.r) / float(suits.eva_speed_px_h) + float(suits.trip_overhead_h)


## Sites at or beyond this trip time are never chosen or spawned (0.85 x tank).
func trip_limit() -> float:
	return float(suits.trip_filter) * float(suits.tank_h)


func reachable_ice_count() -> int:
	var n := 0
	for f in ice_fields:
		if f.amount > 0.0 and trip_time(f) < trip_limit():
			n += 1
	return n


# ---------------------------------------------------------------- spawning (spec 8.1, A2)

## kind is "ice" or "pit". Up to spawn.tries tries; each draws pick(online buildings), angle,
## distance (+ creep per try), then, only for a candidate that clears every spacing rule, the ice
## amount and radius. A candidate failing the trip rule is rejected, never clamped. Appends and
## returns the site, or null (no online building, or every try rejected).
func spawn_site(kind: String, dist_range: Array) -> Site:
	var online: Array[Buildings.Building] = []
	for b in _buildings.list:
		if b.online():
			online.append(b)
	if online.is_empty():
		return null
	var sp: Dictionary = cfg.spawn
	var tp: float = float(_buildings.cfg.tile_px)
	var is_ice := kind == "ice"
	for i in int(sp.tries):
		var anchor: Buildings.Building = _rng.pick(online)
		var ang := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(float(dist_range[0]), float(dist_range[1])) \
				+ float(sp.creep_px_per_try) * i
		var p := anchor.door(tp) + Vector2(cos(ang), sin(ang)) * dist
		if not _clear(p, tp):
			continue
		var s := Site.new()
		s.x = p.x
		s.y = p.y
		if is_ice:
			s.kind = "ice"
			var a: Array = cfg.ice_field.amount
			var rr: Array = cfg.ice_field.radius_px
			s.amount = _rng.randf_range(float(a[0]), float(a[1]))
			s.start = s.amount
			s.r = _rng.randf_range(float(rr[0]), float(rr[1]))
		else:
			s.r = float(cfg.pit.radius_px)
		if not (trip_time(s) < trip_limit()):
			continue
		if is_ice:
			ice_fields.append(s)
		else:
			pits.append(s)
		return s
	return null


## Spacing rules: clear of every building, every other site, and every corridor plus margin.
func _clear(p: Vector2, tp: float) -> bool:
	var sp: Dictionary = cfg.spawn
	var b_clear: float = float(sp.clearance_building_px)
	var t_clear: float = float(sp.clearance_tunnel_px)
	for b in _buildings.list:
		var r := Rect2(b.tx * tp, b.ty * tp, b.tw * tp, b.th * tp)
		var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
		var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
		if sqrt(dx * dx + dy * dy) < b_clear:
			return false
		if b.corridor != null:
			var cr: Rect2i = b.corridor.rect
			var cpx := Rect2(cr.position.x * tp, cr.position.y * tp, cr.size.x * tp, cr.size.y * tp)
			if cpx.grow(t_clear).has_point(p):
				return false
	var s_clear: float = float(sp.clearance_site_px)
	for g in ice_fields:
		if p.distance_to(g.pos()) <= s_clear:
			return false
	for g in pits:
		if p.distance_to(g.pos()) <= s_clear:
			return false
	return true


## Founder sites in spawn order: the pit, then the ice fields (spec 8.1).
func spawn_founder_sites() -> void:
	var sp: Dictionary = cfg.spawn
	spawn_site("pit", sp.founder_pit_px)
	for rng_range: Array in sp.founder_ice_px:
		spawn_site("ice", rng_range)


## Spec 8.4: when fewer than scout.min_reachable fields are reachable, one draw of
## chance(chance_per_h x dt); on success spawns an ice field in the scouting range. Returns it or null.
func scout(dt: float) -> Site:
	if reachable_ice_count() >= int(cfg.scout.min_reachable):
		return null
	if not _rng.chance(float(cfg.scout.chance_per_h) * dt):
		return null
	return spawn_site("ice", cfg.spawn.ice_px)


## The field a dry-up replacement uses: the same range as scouting (step 5 notes).
func respawn_if_short() -> Site:
	if reachable_ice_count() >= int(cfg.scout.min_reachable):
		return null
	return spawn_site("ice", cfg.spawn.ice_px)


# ---------------------------------------------------------------- footprints (spec 8.5)

func add_footprint(x: float, y: float, heading: float, t: float, heavy: bool) -> void:
	var f := Footprint.new()
	f.x = x
	f.y = y
	f.heading = heading
	f.t = t
	f.heavy = heavy
	footprints.append(f)
	while footprints.size() > int(suits.footprint.cap):
		footprints.pop_front()


## Phase 11: drops prints older than `fade_h` (elapsed-since comparator, spec section 3).
func expire_footprints(t: float, fade_h: float) -> void:
	var keep: Array[Footprint] = []
	for f in footprints:
		if not (t - f.t > fade_h + SimWorld.STEP_EPS):
			keep.append(f)
	footprints = keep
