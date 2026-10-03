extends RefCounted
## Task 1, step 5: layout, tunnels and resources (as data and spawning rules; no mining or walking yet).
## Spec: docs/specs/life-support-power.md sections 7.3, 8.1, 8.2 (launch_for, reachable), 8.3 (dry-up), 8.4,
## 11 (A2, A3), 16 (reachable samples), and the "Tests (tests/test_suits.gd, tests/test_layout.gd)" lists.
##
## Existing API used: SimWorld.new(seed, {"blank": true}), add_building(kind, tx, ty, built) -> id,
##  set_offline(id, bool), step(), t, rng, log, stats, buildings.add(kind, tx, ty, built, tw, th) -> Building,
##  buildings.list / get_building(id), Building.tx/ty/tw/th/built/offline/finished()/online(), Building.door(tile_px).
##
## API ASSUMED beyond the existing one (extended the simplest way; spec names where the spec has one):
##  Buildings (sim/buildings.gd)
##  - Building.corridor: null for a building with no parent (the reactor, or one made with add()), else a
##    Dictionary {parent_id: int, p1: Vector2, p2: Vector2, len: float, rect: Rect2i}. p1 and p2 are px, p1 on the
##    parent edge, p2 on the child edge, both on the corridor centre line; len = gap x tile_px; rect is in tiles.
##    The corridor's id is the id of the child building that owns it (Being.corridor_id will use the same id).
##    Its built value is the child's built (spec 7.3), so a corridor is traversable when its child is finished.
##  - Buildings.add_attached(kind, parent_id, dir, tw, th, gap, built := 1.0) -> Building. Places the child `gap`
##    tiles beyond the parent in dir ('r','l','u','d'), centred on the parent's mid row or column, with a corridor
##    3 tiles wide and `gap` long. Centring rounds half up (floor(x + 0.5)), which is what the founder numbers imply
##    (habitat ty = 5 - 4.5 -> 1; workshop corridor x = 6 - 1.5 -> 5). No overlap check (hand-made graphs).
##  - Buildings.find_spot(rng: SimRng) -> Dictionary: {} when no spot after find_spot.tries tries, else
##    {parent_id, dir, tw, th, gap, tx, ty, rect: Rect2i (tiles), corridor_rect: Rect2i (tiles)}. Draw order per try
##    as in the spec: pick(finished buildings), pick(['r','l','u','d']), randi_range(10,14), (8,10), (5,9).
##    It adds nothing: the test commits a spot with add_attached.
##  - Buildings.next_hop(from_id, to_id) -> int: the id of the first corridor on the shortest path over finished
##    corridors, 0 when there is no path or from == to.
##  - SimWorld(seed) without options.blank builds the founder layout (buildings 1..4: reactor, habitat, workshop,
##    green room) and then the founder sites (pit, ice, ice) in _init. The beings are step 6 and not tested here.
##  Resources (sim/resources.gd, class_name Resources), reached as SimWorld.resources
##  - ice_fields: Array of records with x, y, amount, r (a Dictionary or an object, read as f.x); pits: Array with x, y, r.
##  - add_ice_field(x, y, amount, r) -> record and add_pit(x, y) -> record: test seams that append a site.
##  - spawn_site(kind: String ("ice" or "pit"), range: Array [lo, hi]) -> record or null. Appends the record on
##    success. null when no online building exists, or when 400 tries all fail (reject, do not clamp).
##  - trip_time(site) -> float = 2 x (d_launch + r) / 16 + 6 with d_launch to the nearest online door (INF if none).
##    launch_for(site) -> Building or null: the online building whose door is nearest the site, tie lowest id.
##  - reachable_ice_count() -> int: ice fields with amount > 0 and trip_time < 0.85 x tank.
##  - scout(dt: float) -> record or null: one scouting draw. Only when reachable_ice_count() < 2 it draws
##    chance(0.05 x dt), and on success spawn_site("ice", [90, 170]). Returns the new field or null.
##    SimWorld.step() calls it once per step after the ice drain and logs "scouts_found" and counts stats.scouts_found.
##    SimWorld.scouting_enabled (bool): the world-level switch for that call. Default true for a founder world and
##    false for a blank world. Reason: scout() draws rng every step while reachable < 2, and a blank world has no
##    ice, so it would shift the rng stream that tests/test_power.gd and test_colony.gd pin (three test_power tests
##    fail otherwise, see the report). Tests here that step a world and need scouting set it to true.
##  SimWorld
##  - take_ice(field, amount: float) -> float: removes min(amount, field.amount) from the field and returns it.
##    When the field reaches 0 it leaves resources.ice_fields, stats.ice_dry += 1, log "ice_dry" (once), and when
##    reachable_ice_count() < 2 a new field is spawned at once (log "ice_found"). Mining (step 8) will call it.
##  - Stats (top-level keys of world.stats, as in test_power): sol_samples and reachable_ok_samples (spec 16),
##    scouts_found, ice_dry. A sample is taken in phase 11 of the first step of each sol (step 494 for sol 1).
##
## Tests that need a later step are not here: footprints, mining yields and the miner's walk to the launch door
## (step 8), founders as beings (step 6 and 9), balance-run reachable share (step 10).

const TILE := 8.0
const TANK := 36.0
const SPEED := 16.0
const OVERHEAD := 6.0
const FILTER := 0.85
const LIMIT := FILTER * TANK  # 30.6
const DIRS := ["r", "l", "u", "d"]
## The spec says 500 seeds x 40 spawns. Spawns past about 20 per colony mostly exhaust the 400 tries (the 90 px
## spacing fills the ring), so cost grows faster than the number of fields tested: 40 per seed took 15 s in the
## stub, 20 about 3 s for roughly the same count of successful ice spawns per second. Measured numbers are in the report.
const SPAWNS_PER_SEED := 20


# ---------------------------------------------------------------- helpers

func _blank(seed_in: int) -> SimWorld:
	return SimWorld.new(seed_in, {"blank": true})


## Fixture ice fields around the reactor door (48, 80), each 150 px from it (trip 2 x 166 / 16 + 6 = 26.75):
## FA below, FB above, FC to the right. Mutual distances are over 200 px. FAR1 and FAR2 are live but unreachable.
const FA := Vector2(48.0, 230.0)
const FB := Vector2(48.0, -70.0)
const FC := Vector2(198.0, 80.0)
const FAR1 := Vector2(48.0, 480.0)
const FAR2 := Vector2(48.0, -500.0)


func _field(w: SimWorld, p: Vector2, amount: float = 300.0):
	return w.resources.add_ice_field(p.x, p.y, amount, 16.0)


## SimWorld.step() scouts only when the world allows it: blank worlds start with scouting off, so that tests that
## count rng draws (test_power) are not disturbed. Tests that step a world and want scouting switch it on.
func _scouting_on(t, w: SimWorld) -> void:
	t.check("scouting_enabled" in w, "missing SimWorld.scouting_enabled")
	if "scouting_enabled" in w:
		w.set("scouting_enabled", true)


## One finished reactor 12x10 at the origin: door (48, 80).
func _reactor_world(seed_in: int) -> SimWorld:
	var w := _blank(seed_in)
	w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	return w


func _api(t, obj: Object, methods: Array, what: String) -> bool:
	var ok := obj != null
	t.check(ok, "missing %s" % what)
	if not ok:
		return false
	for m in methods:
		if not obj.has_method(m):
			t.check(false, "missing %s.%s()" % [what, m])
			ok = false
	return ok


func _bapi(t, b: Buildings) -> bool:
	return _api(t, b, ["add_attached", "find_spot", "next_hop"], "Buildings")


func _rapi(t, w: SimWorld) -> bool:
	var r: Object = w.get("resources")
	var ok := _api(t, r, ["spawn_site", "trip_time", "launch_for", "reachable_ice_count", "scout",
			"add_ice_field", "add_pit"], "SimWorld.resources")
	return ok and _api(t, w, ["take_ice"], "SimWorld")


func _rect_i(b) -> Rect2i:
	return Rect2i(b.tx, b.ty, b.tw, b.th)


func _rect_px(r: Rect2i) -> Rect2:
	return Rect2(r.position.x * TILE, r.position.y * TILE, r.size.x * TILE, r.size.y * TILE)


## Chebyshev separation in tiles between two tile rects (negative or 0 when touching or overlapping).
## "Within m tiles" is rejected, so a legal pair has separation >= m.
func _sep(a: Rect2i, b: Rect2i) -> int:
	var gx := maxi(a.position.x - b.end.x, b.position.x - a.end.x)
	var gy := maxi(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxi(gx, gy)


func _dist_point_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)


func _all_sites(w: SimWorld) -> Array:
	return w.resources.ice_fields + w.resources.pits


func _count_log(w: SimWorld, kind: String) -> int:
	var n := 0
	for e in w.log:
		if e.kind == kind:
			n += 1
	return n


## Distance from (x, y) to the nearest online building door, INF if none. Independent of the code under test.
func _d_launch(w: SimWorld, x: float, y: float) -> float:
	var best := INF
	for b in w.buildings.list:
		if b.online():
			best = minf(best, Vector2(x, y).distance_to(b.door(TILE)))
	return best


func _trip(w: SimWorld, f) -> float:
	return 2.0 * (_d_launch(w, f.x, f.y) + f.r) / SPEED + OVERHEAD


## The A2 and clearance rules on one site (an ice field or a pit) against the live world.
## `ice` adds the trip check. Independent of the code under test.
func _site_ok(w: SimWorld, f, ice: bool) -> bool:
	var p := Vector2(f.x, f.y)
	for b in w.buildings.list:
		if _dist_point_rect(p, _rect_px(_rect_i(b))) < 55.0 - 1e-9:
			return false
		var c = b.corridor
		if c != null and _rect_px(c.rect).grow(30.0).has_point(p):
			return false
	for g in _all_sites(w):
		if g == f:
			continue
		if p.distance_to(Vector2(g.x, g.y)) <= 90.0:
			return false
	if ice and not (_trip(w, f) < LIMIT):
		return false
	return true


## Grows a hand-made colony: every 4th spawn first adds a building through find_spot, some of them offline.
## Returns counts of ice and pit spawns and of spawns that broke a rule when checked right at spawn.
func _grow_and_spawn(w: SimWorld, spawns: int) -> Dictionary:
	var out := {"ice": 0, "pit": 0, "bad": 0}
	var kinds := ["habitat", "workshop", "green_room", "archive", "comms"]
	for i in spawns:
		if i > 0 and i % 4 == 0:
			var spot: Dictionary = w.buildings.find_spot(w.rng)
			if not spot.is_empty():
				var k: int = (i / 4) % kinds.size()
				var nb = w.buildings.add_attached(kinds[k], spot.parent_id, spot.dir,
						spot.tw, spot.th, spot.gap, 1.0)
				if (i / 4) % 3 == 2:
					w.set_offline(nb.id, true)
		var is_pit := i % 8 == 5
		var f = w.resources.spawn_site("pit" if is_pit else "ice", [70, 110] if is_pit else [90, 170])
		if f == null:
			continue
		out["pit" if is_pit else "ice"] += 1
		if not _site_ok(w, f, not is_pit):
			out.bad += 1
	return out


## Expected geometry of add_attached for a parent rect, derived from the spec (see header).
func _expect_attached(p: Rect2i, dir: String, tw: int, th: int, gap: int) -> Dictionary:
	var mx := p.position.x + p.size.x / 2.0
	var my := p.position.y + p.size.y / 2.0
	var cx := int(floor(mx - 1.5 + 0.5))
	var cy := int(floor(my - 1.5 + 0.5))
	var tx: int
	var ty: int
	var cr: Rect2i
	match dir:
		"r":
			tx = p.end.x + gap
			ty = int(floor(my - th / 2.0 + 0.5))
			cr = Rect2i(p.end.x, cy, gap, 3)
		"l":
			tx = p.position.x - gap - tw
			ty = int(floor(my - th / 2.0 + 0.5))
			cr = Rect2i(p.position.x - gap, cy, gap, 3)
		"d":
			tx = int(floor(mx - tw / 2.0 + 0.5))
			ty = p.end.y + gap
			cr = Rect2i(cx, p.end.y, 3, gap)
		_:
			tx = int(floor(mx - tw / 2.0 + 0.5))
			ty = p.position.y - gap - th
			cr = Rect2i(cx, p.position.y - gap, 3, gap)
	return {"rect": Rect2i(tx, ty, tw, th), "corridor_rect": cr}


## Follows next_hop from `from` to `to`; returns the corridor ids walked, or [-1] if it never arrives.
func _walk(b: Buildings, from: int, to: int) -> Array:
	var out: Array = []
	var cur := from
	for i in 40:
		if cur == to:
			return out
		var c: int = b.next_hop(cur, to)
		if c == 0:
			return [-1]
		out.append(c)
		var owner: Buildings.Building = b.get_building(c)
		cur = int(owner.corridor.parent_id) if cur == c else c
	return [-1]


func _sig_world(w: SimWorld) -> String:
	var s := ""
	for b in w.buildings.list:
		s += "B%d:%s:%d,%d,%d,%d;" % [b.id, b.kind, b.tx, b.ty, b.tw, b.th]
	for f in w.resources.ice_fields:
		s += "I%.9f,%.9f,%.9f,%.9f;" % [f.x, f.y, f.amount, f.r]
	for f in w.resources.pits:
		s += "P%.9f,%.9f,%.9f;" % [f.x, f.y, f.r]
	return s


# ---------------------------------------------------------------- founder layout (spec 7.3, exact)

func test_founder_layout_rects_and_doors(t) -> void:
	for seed_in in [42, 7, 99]:
		var w := SimWorld.new(seed_in)
		var l := w.buildings.list
		t.eq(l.size(), 4, "four founding buildings (seed %d)" % seed_in)
		if l.size() != 4:
			return
		var kinds := ["reactor", "habitat", "workshop", "green_room"]
		var rects := [Rect2i(0, 0, 12, 10), Rect2i(19, 1, 13, 9), Rect2i(0, 16, 12, 9), Rect2i(-19, 1, 12, 9)]
		var doors := [Vector2(48, 80), Vector2(204, 80), Vector2(48, 200), Vector2(-104, 80)]
		for i in 4:
			t.eq(l[i].id, i + 1, "id %d in creation order" % (i + 1))
			t.eq(l[i].kind, kinds[i], "kind of building %d" % (i + 1))
			t.eq(_rect_i(l[i]), rects[i], "rect of %s" % kinds[i])
			t.eq(l[i].door(TILE), doors[i], "door of %s" % kinds[i])
			t.check(l[i].finished() and not l[i].offline, "%s finished and online" % kinds[i])


func test_founder_corridors_exact(t) -> void:
	var w := SimWorld.new(42)
	if w.buildings.list.size() != 4:
		t.check(false, "founder layout missing")
		return
	t.check(w.buildings.list[0].corridor == null, "the reactor has no corridor")
	# [child index, p1, p2, len, rect]: lengths 56, 48, 56 px (gaps 7, 6, 7 tiles).
	var expect := [
		[1, Vector2(96, 44), Vector2(152, 44), 56.0, Rect2i(12, 4, 7, 3)],
		[2, Vector2(52, 80), Vector2(52, 128), 48.0, Rect2i(5, 10, 3, 6)],
		[3, Vector2(0, 44), Vector2(-56, 44), 56.0, Rect2i(-7, 4, 7, 3)],
	]
	for e in expect:
		var c = w.buildings.list[e[0]].corridor
		t.check(c != null, "building %d has a corridor" % (e[0] + 1))
		if c == null:
			continue
		t.eq(int(c.parent_id), 1, "parent of building %d is the reactor" % (e[0] + 1))
		t.eq(c.p1, e[1], "p1 of building %d" % (e[0] + 1))
		t.eq(c.p2, e[2], "p2 of building %d" % (e[0] + 1))
		t.near(float(c.len), e[3], 1e-9, "len of building %d" % (e[0] + 1))
		t.eq(c.rect, e[4], "corridor rect of building %d (3 wide, gap long)" % (e[0] + 1))


func test_founder_tunnel_hops(t) -> void:
	var w := SimWorld.new(42)
	if w.buildings.list.size() != 4 or not w.buildings.has_method("next_hop"):
		t.check(false, "founder layout or next_hop missing")
		return
	var b := w.buildings
	t.eq(b.next_hop(1, 3), 3, "reactor to workshop: the workshop corridor")
	t.eq(b.next_hop(3, 1), 3, "workshop to reactor: same corridor")
	t.eq(b.next_hop(2, 3), 2, "habitat to workshop leaves by the habitat corridor")
	t.eq(b.next_hop(2, 4), 2, "habitat to green room leaves by the habitat corridor")
	t.eq(b.next_hop(4, 2), 4, "green room to habitat leaves by the green room corridor")
	t.eq(b.next_hop(1, 1), 0, "already there: no hop")
	t.eq(_walk(b, 2, 4), [2, 4], "habitat to green room: two corridors")


func test_founder_sites_pit_and_two_ice_fields(t) -> void:
	var w := SimWorld.new(42)
	if not _rapi(t, w):
		return
	t.eq(w.resources.pits.size(), 1, "one founder pit")
	t.eq(w.resources.ice_fields.size(), 2, "two founder ice fields")
	if w.resources.pits.size() != 1 or w.resources.ice_fields.size() != 2:
		return
	var pit = w.resources.pits[0]
	t.near(float(pit.r), 9.0, 1e-9, "pit radius 9")
	# Ranges are from an anchor door and creep up to 0.08 x 400 = 32 px; the nearest door can only be closer.
	t.check(_d_launch(w, pit.x, pit.y) <= 110.0 + 32.0 + 1e-6, "pit within 110 + creep of a door")
	var hi := [150.0, 160.0]
	for i in 2:
		var f = w.resources.ice_fields[i]
		t.between(float(f.amount), 260.0, 420.0, "ice %d amount" % i)
		t.between(float(f.r), 16.0, 24.0, "ice %d radius" % i)
		t.check(_d_launch(w, f.x, f.y) <= hi[i] + 32.0 + 1e-6, "ice %d within its founder range + creep" % i)
	for f in w.resources.ice_fields:
		t.check(_site_ok(w, f, true), "founder ice field clear and within the trip rule")
	t.check(_site_ok(w, pit, false), "founder pit clear")
	t.eq(w.resources.reachable_ice_count(), 2, "both founder fields are reachable")


func test_founder_sites_200_seeds_obey_every_rule(t) -> void:
	var bad := 0
	for s in 200:
		var w := SimWorld.new(1000 + s)
		if not _rapi(t, w):
			return
		if w.resources.pits.size() != 1 or w.resources.ice_fields.size() != 2:
			bad += 1
			continue
		for f in w.resources.ice_fields:
			if not _site_ok(w, f, true):
				bad += 1
		if not _site_ok(w, w.resources.pits[0], false):
			bad += 1
	t.eq(bad, 0, "founder sites over 200 seeds breaking a rule")


# ---------------------------------------------------------------- door point

func test_door_is_bottom_centre_for_100_random_rects(t) -> void:
	var rng := SimRng.new(5)
	var b := Buildings.new()
	var wrong := 0
	for i in 100:
		var tx := rng.randi_range(-60, 60)
		var ty := rng.randi_range(-60, 60)
		var tw := rng.randi_range(10, 14)
		var th := rng.randi_range(8, 10)
		var bb := b.add("habitat", tx, ty, 1.0, tw, th)
		var expect := Vector2((tx + tw / 2.0) * TILE, (ty + th) * TILE)
		if bb.door(TILE) != expect:
			wrong += 1
	t.eq(wrong, 0, "doors off the bottom centre")
	t.eq(b.add("habitat", 0, 0, 1.0, 13, 9).door(TILE), Vector2(52, 72), "odd width 13: x = 6.5 x 8")


# ---------------------------------------------------------------- add_attached geometry

func test_add_attached_geometry_all_directions(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	var parent := b.add("reactor", 100, 100, 1.0, 12, 10)
	var cases := [
		["r", 13, 9, 7], ["r", 10, 8, 5], ["r", 14, 10, 9],
		["l", 12, 9, 7], ["l", 11, 8, 6],
		["d", 12, 9, 6], ["d", 14, 8, 9], ["d", 13, 10, 5],
		["u", 12, 9, 5], ["u", 10, 10, 8], ["u", 13, 8, 7],
	]
	for c in cases:
		var nb = b.add_attached("habitat", parent.id, c[0], c[1], c[2], c[3], 1.0)
		var e := _expect_attached(_rect_i(parent), c[0], c[1], c[2], c[3])
		var label := "%s %dx%d gap %d" % [c[0], c[1], c[2], c[3]]
		t.eq(_rect_i(nb), e.rect, "rect " + label)
		var cor = nb.corridor
		t.check(cor != null, "corridor " + label)
		if cor == null:
			continue
		t.eq(cor.rect, e.corridor_rect, "corridor rect " + label)
		t.eq(int(cor.parent_id), parent.id, "parent " + label)
		t.near(float(cor.len), c[3] * TILE, 1e-9, "len " + label)
		t.near(cor.p1.distance_to(cor.p2), float(cor.len), 1e-9, "p1 to p2 is len " + label)
		var cr := _rect_px(cor.rect).grow(0.01)
		t.check(cr.has_point(cor.p1) and cr.has_point(cor.p2), "p1, p2 on the corridor " + label)
		t.eq(_sep(_rect_i(nb), _rect_i(parent)), c[3], "gap tiles between parent and child " + label)


func test_site_has_its_corridor_but_it_is_not_traversable_until_finished(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	var p := b.add("reactor", 0, 0, 1.0, 12, 10)
	var site = b.add_attached("habitat", p.id, "r", 13, 9, 7, 0.0)
	t.eq(site.built, 0.0, "site starts at built 0")
	t.check(site.corridor != null, "a site already has its corridor rect")
	site.built = 0.5
	t.eq(b.next_hop(p.id, site.id), 0, "an unfinished corridor is not traversed (from the parent)")
	t.eq(b.next_hop(site.id, p.id), 0, "an unfinished corridor is not traversed (from the site)")
	site.built = 1.0
	t.eq(b.next_hop(p.id, site.id), site.id, "finished: traversable")


# ---------------------------------------------------------------- tunnel graph and BFS

func test_bfs_five_node_graph(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	# 1 reactor; 2 right of 1; 3 below 1; 4 right of 2; 5 below 3.   Path 5 -> 4 is 5, 3, 1, 2, 4:
	# corridors 5 (5-3), 3 (3-1), 2 (1-2), 4 (2-4).
	var n1 := b.add("reactor", 0, 0, 1.0, 12, 10)
	var n2 = b.add_attached("habitat", n1.id, "r", 13, 9, 7, 1.0)
	var n3 = b.add_attached("workshop", n1.id, "d", 12, 9, 6, 1.0)
	var n4 = b.add_attached("archive", n2.id, "r", 12, 9, 6, 1.0)
	var n5 = b.add_attached("comms", n3.id, "d", 12, 9, 6, 1.0)
	t.eq([n1.id, n2.id, n3.id, n4.id, n5.id], [1, 2, 3, 4, 5], "ids in creation order")
	t.eq(_walk(b, 5, 4), [5, 3, 2, 4], "5 to 4: four corridors")
	t.eq(b.next_hop(5, 4), 5, "first hop 5 -> 4 is corridor 5")
	t.eq(b.next_hop(4, 5), 4, "first hop 4 -> 5 is corridor 4")
	t.eq(_walk(b, 4, 5), [4, 2, 3, 5], "4 to 5")
	t.eq(_walk(b, 1, 5), [3, 5], "1 to 5")
	t.eq(_walk(b, 3, 2), [3, 2], "3 to 2 (siblings via the parent)")
	t.eq(b.next_hop(3, 3), 0, "same node: no hop")
	# Offline buildings are passable (A3).
	n3.offline = true
	t.eq(_walk(b, 5, 4), [5, 3, 2, 4], "an offline building in the middle is still passable")


func test_bfs_disconnected_returns_none(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	var n1 := b.add("reactor", 0, 0, 1.0, 12, 10)
	var n2 = b.add_attached("habitat", n1.id, "r", 13, 9, 7, 1.0)
	var island := b.add("workshop", 500, 500, 1.0, 12, 9)
	t.eq(b.next_hop(n1.id, island.id), 0, "no path to an island")
	t.eq(b.next_hop(island.id, n2.id), 0, "no path from an island")
	t.eq(b.next_hop(n1.id, 99), 0, "unknown target: none")
	t.eq(b.next_hop(n1.id, n2.id), n2.id, "the connected pair still routes")


func test_bfs_unfinished_corridor_cuts_the_path(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	var n1 := b.add("reactor", 0, 0, 1.0, 12, 10)
	var n2 = b.add_attached("habitat", n1.id, "r", 13, 9, 7, 0.4)
	var n3 = b.add_attached("workshop", n2.id, "r", 12, 9, 6, 1.0)
	t.eq(b.next_hop(n1.id, n3.id), 0, "1 to 3 blocked by the unfinished corridor of 2")
	t.eq(b.next_hop(n3.id, n1.id), 0, "3 to 1 blocked too")
	n2.built = 1.0
	t.eq(_walk(b, 1, 3), [2, 3], "finished: 1 to 3 is two corridors")


func test_bfs_shortest_over_random_trees(t) -> void:
	if not _bapi(t, Buildings.new()):
		return
	var rng := SimRng.new(77)
	var wrong := 0
	var pairs := 0
	for tree in 30:
		var b := Buildings.new()
		var ids: Array = [b.add("reactor", 0, 0, 1.0, 12, 10).id]
		var parent_of := {ids[0]: 0}
		for i in 11:
			var p: int = rng.pick(ids)
			var nb = b.add_attached("habitat", p, rng.pick(DIRS), 12, 9, rng.randi_range(5, 9), 1.0)
			ids.append(nb.id)
			parent_of[nb.id] = p
		for k in 8:
			var a: int = rng.pick(ids)
			var c: int = rng.pick(ids)
			var anc_a: Array = [a]
			while parent_of[anc_a[-1]] != 0:
				anc_a.append(parent_of[anc_a[-1]])
			var anc_c: Array = [c]
			while parent_of[anc_c[-1]] != 0:
				anc_c.append(parent_of[anc_c[-1]])
			var best := 9999
			for i in anc_a.size():
				var j := anc_c.find(anc_a[i])
				if j >= 0:
					best = mini(best, i + j)
			var walked := _walk(b, a, c)
			pairs += 1
			if walked.size() != best or (best > 0 and walked[0] == -1):
				wrong += 1
	t.eq(pairs, 240, "pairs checked")
	t.eq(wrong, 0, "walks that were not the shortest tree path")


# ---------------------------------------------------------------- find_spot

func test_find_spot_never_overlaps_500_seeds_20_sites(t) -> void:
	if not _bapi(t, Buildings.new()):
		return
	var placed := 0
	var no_spot := 0
	var overlap := 0
	var corridor_hit := 0
	var cor_vs_building := 0
	var cor_vs_cor := 0
	var out_of_range := 0
	var min_b_sep := 999
	for s in 500:
		var b := Buildings.new()
		var rng := SimRng.new(s)
		b.add("reactor", 0, 0, 1.0, 12, 10)
		for k in 20:
			var spot: Dictionary = b.find_spot(rng)
			if spot.is_empty():
				no_spot += 1
				continue
			var parent := b.get_building(int(spot.parent_id))
			if spot.tw < 10 or spot.tw > 14 or spot.th < 8 or spot.th > 10 or spot.gap < 5 or spot.gap > 9:
				out_of_range += 1
			for o in b.list:
				var sp := _sep(spot.rect, _rect_i(o))
				min_b_sep = mini(min_b_sep, sp)
				if sp < 2:
					overlap += 1
				if o.id != parent.id and _sep(spot.corridor_rect, _rect_i(o)) < 1:
					cor_vs_building += 1
				if o.corridor != null:
					if _sep(spot.rect, o.corridor.rect) < 1:
						corridor_hit += 1
					if _sep(spot.corridor_rect, o.corridor.rect) < 1:
						cor_vs_cor += 1
			placed += 1
			b.add_attached("habitat", spot.parent_id, spot.dir, spot.tw, spot.th, spot.gap, 1.0)
	t.eq(overlap, 0, "spots within 2 tiles of a building")
	t.eq(corridor_hit, 0, "spots within 1 tile of a corridor")
	t.eq(cor_vs_building, 0, "new corridors within 1 tile of a building other than the parent")
	t.eq(cor_vs_cor, 0, "new corridors within 1 tile of another corridor")
	t.eq(out_of_range, 0, "sizes or gaps outside 10..14, 8..10, 5..9")
	t.check(placed >= 5000, "at least half of the 10,000 attempts found a spot (placed %d, none %d)" % [placed, no_spot])
	t.check(min_b_sep >= 2, "minimum building separation observed %d" % min_b_sep)


func test_find_spot_result_matches_add_attached(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	var rng := SimRng.new(3)
	b.add("reactor", 0, 0, 1.0, 12, 10)
	var committed := 0
	for k in 10:
		var spot: Dictionary = b.find_spot(rng)
		if spot.is_empty():
			continue
		var nb = b.add_attached("workshop", spot.parent_id, spot.dir, spot.tw, spot.th, spot.gap, 1.0)
		committed += 1
		t.eq(_rect_i(nb), spot.rect, "committed rect equals the spot rect (%d)" % k)
		t.eq(nb.corridor.rect, spot.corridor_rect, "committed corridor equals the spot corridor (%d)" % k)
		t.eq(int(nb.corridor.parent_id), int(spot.parent_id), "parent (%d)" % k)
		t.eq(Vector2i(nb.tx, nb.ty), Vector2i(spot.tx, spot.ty), "tx, ty (%d)" % k)
	t.check(committed >= 5, "enough spots committed (%d)" % committed)


func test_find_spot_draw_order_first_try(t) -> void:
	# A lone reactor: the first try is always acceptable, so the result shows the draw order exactly:
	# pick(finished buildings), pick(dirs), tw 10..14, th 8..10, gap 5..9.
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	b.add("reactor", 0, 0, 1.0, 12, 10)
	for seed_in in [1, 2, 3, 4, 5, 6]:
		var rng := SimRng.new(seed_in)
		var ref := SimRng.new(seed_in)
		var spot: Dictionary = b.find_spot(rng)
		ref.pick([1])
		var dir: String = ref.pick(DIRS)
		var tw := ref.randi_range(10, 14)
		var th := ref.randi_range(8, 10)
		var gap := ref.randi_range(5, 9)
		t.check(not spot.is_empty(), "lone reactor always has a spot (seed %d)" % seed_in)
		if spot.is_empty():
			continue
		t.eq(spot.dir, dir, "dir draw (seed %d)" % seed_in)
		t.eq([spot.tw, spot.th, spot.gap], [tw, th, gap], "tw, th, gap draws (seed %d)" % seed_in)
		t.eq(rng.randf(), ref.randf(), "exactly 5 draws consumed on an accepted first try (seed %d)" % seed_in)


func test_find_spot_parents_are_finished_buildings_only(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	t.check(b.find_spot(SimRng.new(1)).is_empty(), "no buildings: no spot")
	var site := b.add("habitat", 300, 0, 0.3, 13, 9)
	t.check(b.find_spot(SimRng.new(1)).is_empty(), "only an unfinished site: no spot")
	b.add("reactor", 0, 0, 1.0, 12, 10)
	var offline := b.add("workshop", 0, 200, 1.0, 12, 9)
	offline.offline = true
	var seen_offline := false
	for s in 200:
		var spot: Dictionary = b.find_spot(SimRng.new(s))
		if spot.is_empty():
			continue
		t.check(spot.parent_id != site.id, "never a site as parent (seed %d)" % s)
		if spot.parent_id == offline.id:
			seen_offline = true
	t.check(seen_offline, "an offline finished building can be a parent (spec: including offline)")


## Directed margin tests. The random-growth test cannot see the corridor margin (building spacing 2 already keeps
## corridors apart in almost every grown colony: with the corridor rule disabled it still passes), so these build the
## one situation that does: a long corridor of an unfinished pair X-Y (never parents) next to the one candidate
## R + 'r', 10 x 8, gap 9, i.e. rect (21, 1, 10, 8) and corridor (12, 4, 9, 3), while X and Y stay 6 tiles from it.
func _blocked_world(x_tx: int) -> Buildings:
	var b := Buildings.new()
	b.add("reactor", 0, 0, 1.0, 12, 10)
	var x := b.add("workshop", x_tx, -13, 0.5, 10, 8)
	b.add_attached("comms", x.id, "d", 10, 8, 20, 0.5)
	return b


## Seeds whose first try draws exactly the candidate above (1 in 300 seeds).
func _candidate_seeds(count: int) -> Array:
	var out: Array = []
	var s := 0
	while out.size() < count and s < 20000:
		var ref := SimRng.new(s)
		ref.pick([1])
		var dir: String = ref.pick(DIRS)
		var tw := ref.randi_range(10, 14)
		var th := ref.randi_range(8, 10)
		var gap := ref.randi_range(5, 9)
		if dir == "r" and tw == 10 and th == 8 and gap == 9:
			out.append(s)
		s += 1
	return out


func _is_candidate(spot: Dictionary) -> bool:
	return not spot.is_empty() and spot.dir == "r" and spot.tw == 10 and spot.th == 8 and spot.gap == 9


func test_find_spot_corridor_margin_crossing_and_touching(t) -> void:
	if not _bapi(t, Buildings.new()):
		return
	var seeds := _candidate_seeds(8)
	t.eq(seeds.size(), 8, "found 8 seeds that draw the candidate first")
	var control := Buildings.new()
	control.add("reactor", 0, 0, 1.0, 12, 10)
	for s in seeds:
		var c: Dictionary = control.find_spot(SimRng.new(s))
		t.check(_is_candidate(c), "control (lone reactor) accepts the candidate (seed %d)" % s)
		if not c.is_empty():
			t.eq(c.rect, Rect2i(21, 1, 10, 8), "candidate rect")
			t.eq(c.corridor_rect, Rect2i(12, 4, 9, 3), "candidate corridor")
	# Crossing: X-Y corridor at x 16..19 runs through the candidate corridor (12..21 x 4..7).
	var crossing := _blocked_world(12)
	var cc = crossing.list[2].corridor.rect
	t.eq(cc, Rect2i(16, -5, 3, 20), "crossing corridor geometry")
	t.check(_sep(Rect2i(12, 4, 9, 3), cc) < 1, "it does cross the candidate corridor")
	t.check(_sep(Rect2i(21, 1, 10, 8), cc) >= 1, "but the candidate rect itself is clear of it")
	for s in seeds:
		t.check(not _is_candidate(crossing.find_spot(SimRng.new(s))), "corridor crossing a corridor is rejected (seed %d)" % s)
	# Touching: X-Y corridor at x 31..34 touches the candidate rect (21..31) with separation 0 < 1.
	var touching := _blocked_world(27)
	var tc = touching.list[2].corridor.rect
	t.eq(tc, Rect2i(31, -5, 3, 20), "touching corridor geometry")
	t.eq(_sep(Rect2i(21, 1, 10, 8), tc), 0, "separation exactly 0 from the candidate rect")
	for b in touching.list:
		t.check(_sep(Rect2i(21, 1, 10, 8), Rect2i(b.tx, b.ty, b.tw, b.th)) >= 2 or b.id == 1, "buildings are 2+ tiles from the candidate (id %d)" % b.id)
	for s in seeds:
		t.check(not _is_candidate(touching.find_spot(SimRng.new(s))), "a rect touching a corridor is rejected (seed %d)" % s)



func test_find_spot_gives_up_after_80_tries(t) -> void:
	var b := Buildings.new()
	if not _bapi(t, b):
		return
	b.add("reactor", 0, 0, 1.0, 12, 10)
	# Four unfinished slabs (never parents) cover every place a child of the reactor could go.
	b.add("habitat", 13, -40, 0.1, 45, 90)    # right
	b.add("habitat", -60, -40, 0.1, 59, 90)   # left
	b.add("habitat", -40, -60, 0.1, 100, 59)  # up
	b.add("habitat", -40, 11, 0.1, 100, 59)   # down
	var rng := SimRng.new(8)
	var spot: Dictionary = b.find_spot(rng)
	t.check(spot.is_empty(), "no acceptable spot: empty result, no site this check")
	var ref := SimRng.new(8)
	for i in 80:
		ref.pick([1])
		ref.pick(DIRS)
		ref.randi_range(10, 14)
		ref.randi_range(8, 10)
		ref.randi_range(5, 9)
	t.eq(rng.randf(), ref.randf(), "exactly 80 tries of 5 draws were made")


func test_layout_determinism(t) -> void:
	var sigs: Array = []
	for seed_in in [42, 42, 43]:
		var w := SimWorld.new(seed_in)
		if not _rapi(t, w):
			return
		for k in 12:
			var spot: Dictionary = w.buildings.find_spot(w.rng)
			if not spot.is_empty():
				w.buildings.add_attached("habitat", spot.parent_id, spot.dir, spot.tw, spot.th, spot.gap, 1.0)
			w.resources.spawn_site("ice", [90, 170])
		sigs.append(_sig_world(w))
	t.eq(sigs[0], sigs[1], "same seed, same layout and fields")
	t.check(sigs[0] != sigs[2], "a different seed differs")


# ---------------------------------------------------------------- trip time, launch, reachable

func test_trip_time_numbers_from_the_spec(t) -> void:
	var w := _reactor_world(1)  # door (48, 80)
	if not _rapi(t, w):
		return
	var far = w.resources.add_ice_field(48.0, 80.0 + 196.0, 300.0, 16.0)
	t.near(w.resources.trip_time(far), 2.0 * (196.0 + 16.0) / 16.0 + 6.0, 1e-9, "196 px, r 16")
	t.near(w.resources.trip_time(far), 32.5, 1e-9, "spec value 32.5")
	t.check(w.resources.trip_time(far) >= LIMIT, "fails the 30.6 filter")
	var near = w.resources.add_ice_field(48.0 + 170.0, 80.0, 300.0, 24.0)
	t.near(w.resources.trip_time(near), 30.25, 1e-9, "170 px, r 24: spec value 30.25")
	t.check(w.resources.trip_time(near) < LIMIT, "passes the 30.6 filter")
	t.eq(w.resources.reachable_ice_count(), 1, "only the near field is reachable")
	# The boundary is d + r = 196.8 (trip 30.6); stay 0.1 px either side to keep clear of float noise.
	var edge = w.resources.add_ice_field(48.0, 80.0 + 180.9, 300.0, 16.0)
	t.check(not (w.resources.trip_time(edge) < LIMIT), "d + r = 196.9 fails")
	var inside = w.resources.add_ice_field(48.0, 80.0 - 180.7, 300.0, 16.0)
	t.check(w.resources.trip_time(inside) < LIMIT, "d + r = 196.7 passes")


func test_dry_field_is_not_reachable_even_if_listed(t) -> void:
	var w := _reactor_world(1)
	if not _rapi(t, w):
		return
	var f = w.resources.add_ice_field(48.0, 230.0, 0.0, 16.0)
	t.eq(w.resources.reachable_ice_count(), 0, "amount 0 does not count as reachable")
	f.amount = 5.0
	t.eq(w.resources.reachable_ice_count(), 1, "amount > 0 does")


func test_launch_is_the_nearest_online_door_and_trip_uses_it(t) -> void:
	var w := _reactor_world(2)
	if not _rapi(t, w):
		return
	var hab: int = w.buildings.add_attached("habitat", 1, "r", 13, 9, 7, 1.0).id  # door (204, 80)
	var site = w.resources.add_ice_field(204.0, 80.0 + 150.0, 300.0, 20.0)
	t.eq(w.resources.launch_for(site).id, hab, "habitat door is nearer")
	t.near(w.resources.trip_time(site), 2.0 * (150.0 + 20.0) / 16.0 + 6.0, 1e-9, "trip from the habitat door")
	w.set_offline(hab, true)
	t.eq(w.resources.launch_for(site).id, 1, "habitat dark: the next nearest online building")
	var d := Vector2(204, 230).distance_to(Vector2(48, 80))
	t.near(w.resources.trip_time(site), 2.0 * (d + 20.0) / 16.0 + 6.0, 1e-9, "trip from the reactor door")
	t.check(not (w.resources.trip_time(site) < LIMIT), "now beyond the filter (d = %.1f)" % d)
	t.eq(w.resources.reachable_ice_count(), 0, "unreachable while the habitat is dark")
	w.set_offline(hab, false)
	t.eq(w.resources.reachable_ice_count(), 1, "reachable again")


func test_launch_tie_goes_to_the_lowest_id_and_none_online_gives_none(t) -> void:
	var w := _blank(3)
	if not _rapi(t, w):
		return
	var a: int = w.add_building("workshop", 0, 0)
	var c: int = w.add_building("workshop", 0, 0)  # identical rect: identical door
	var s = w.resources.add_ice_field(40.0, 200.0, 300.0, 16.0)
	t.eq(w.resources.launch_for(s).id, a, "equal distance goes to the lowest id")
	t.check(c > a, "second building has the higher id")
	w.set_offline(a, true)
	t.eq(w.resources.launch_for(s).id, c, "lowest id dark: the other")
	w.set_offline(c, true)
	t.check(w.resources.launch_for(s) == null, "no online building: no launch")
	t.eq(w.resources.trip_time(s), INF, "no online building: trip time is infinite")
	t.eq(w.resources.reachable_ice_count(), 0, "and nothing is reachable")


# ---------------------------------------------------------------- spawning (A2: reject, not clamp)

func test_spawn_invariant_500_seeds_trip_check_at_spawn(t) -> void:
	if not _rapi(t, _reactor_world(1)):
		return
	var ice := 0
	var pits := 0
	var bad := 0
	for s in 500:
		var w := _reactor_world(s)
		var r := _grow_and_spawn(w, SPAWNS_PER_SEED)
		ice += r.ice
		pits += r.pit
		bad += r.bad
	t.eq(bad, 0, "spawns that broke the trip rule or a clearance (ice %d, pits %d)" % [ice, pits])
	t.check(ice >= 5000, "at least 5,000 ice spawns happened (got %d)" % ice)
	t.check(pits >= 500, "at least 500 pit spawns happened (got %d)" % pits)


func test_spawn_is_rejected_not_clamped(t) -> void:
	# Every candidate from 190..200 px has d + r >= 206 > 196.8, so all 400 tries are rejected.
	for s in 40:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		var f = w.resources.spawn_site("ice", [190, 200])
		t.check(f == null, "no field when the whole range is beyond the trip rule (seed %d)" % s)
		t.eq(w.resources.ice_fields.size(), 0, "nothing appended (seed %d)" % s)
	# A range straddling the limit: successes pass the rule, with no pile-up at the boundary (a clamp would put
	# every result at d + r = 196.8).
	var ok := 0
	var at_edge := 0
	for s in 200:
		var w := _reactor_world(s)
		var f = w.resources.spawn_site("ice", [150, 200])
		if f == null:
			continue
		ok += 1
		var dr := _d_launch(w, f.x, f.y) + float(f.r)
		t.check(dr < 196.8, "d + r = %.2f below 196.8" % dr)
		if dr > 196.0:
			at_edge += 1
	t.check(ok >= 190, "most seeds find a spot in 150..200 (%d of 200)" % ok)
	t.check(at_edge < ok / 4, "no pile-up at the boundary (%d of %d above 196)" % [at_edge, ok])


func test_spawn_needs_an_online_building(t) -> void:
	var w := _blank(5)
	if not _rapi(t, w):
		return
	t.check(w.resources.spawn_site("ice", [90, 170]) == null, "no buildings: no spawn")
	var r: int = w.add_building("reactor", 0, 0)
	w.set_offline(r, true)
	t.check(w.resources.spawn_site("ice", [90, 170]) == null, "only an offline building: no spawn")
	t.check(w.resources.spawn_site("pit", [70, 110]) == null, "no pit either")
	t.eq(w.resources.ice_fields.size() + w.resources.pits.size(), 0, "nothing appended")
	w.add_building("habitat", 40, 0, 0.5)
	t.check(w.resources.spawn_site("ice", [90, 170]) == null, "a site is not an online building")
	w.set_offline(r, false)
	t.check(w.resources.spawn_site("ice", [90, 170]) != null, "online reactor: spawns")


func test_spawn_properties_ice_and_pit(t) -> void:
	var w := _reactor_world(11)
	if not _rapi(t, w):
		return
	var f = w.resources.spawn_site("ice", [90, 170])
	t.check(f != null, "ice spawns")
	if f != null:
		t.between(float(f.amount), 260.0, 420.0, "amount")
		t.between(float(f.r), 16.0, 24.0, "radius")
		t.check(w.resources.ice_fields.has(f) and w.resources.pits.is_empty(), "appended to ice_fields only")
		t.between(_d_launch(w, f.x, f.y), 55.0, 170.0 + 32.0, "distance from the door: clearance 55, range 90..170 plus creep")
	var p = w.resources.spawn_site("pit", [70, 110])
	t.check(p != null, "pit spawns")
	if p != null:
		t.near(float(p.r), 9.0, 1e-9, "pit radius 9")
		t.check(w.resources.pits.has(p) and w.resources.ice_fields.size() == 1, "appended to pits only")
		t.check(_site_ok(w, p, false), "pit clear of everything")


func test_spawn_clearances_in_the_founder_colony(t) -> void:
	# Founder colony with its corridors (56, 48, 56 px): 5 spawns on each of 60 seeds.
	var bad := 0
	var n := 0
	for s in 60:
		var w := SimWorld.new(s)
		if not _rapi(t, w):
			return
		for i in 5:
			var is_ice := i % 2 == 0
			var f = w.resources.spawn_site("ice" if is_ice else "pit", [90, 170] if is_ice else [70, 110])
			if f == null:
				continue
			n += 1
			if not _site_ok(w, f, is_ice):
				bad += 1
	t.eq(bad, 0, "founder-colony spawns breaking a clearance or the trip rule")
	t.check(n >= 150, "enough spawns exercised (%d)" % n)


# ---------------------------------------------------------------- dry-up

func test_take_ice_clamps_and_dry_field_is_removed(t) -> void:
	var w := _reactor_world(4)
	if not _rapi(t, w):
		return
	var f = _field(w, FA)
	_field(w, FB)
	_field(w, FC)
	t.near(w.take_ice(f, 100.0), 100.0, 1e-9, "takes what was asked")
	t.near(float(f.amount), 200.0, 1e-9, "amount drops")
	t.check(w.resources.ice_fields.has(f), "still listed")
	t.near(w.take_ice(f, 500.0), 200.0, 1e-9, "never more than remains")
	t.check(float(f.amount) >= 0.0, "amount never negative")
	t.check(not w.resources.ice_fields.has(f), "a dry field leaves the list")
	t.eq(_count_log(w, "ice_dry"), 1, "ice_dry logged once")
	t.eq(int(w.stats.get("ice_dry", -1)), 1, "stats.ice_dry")
	t.near(w.take_ice(f, 5.0), 0.0, 1e-9, "a second miner at the dry field gets 0")
	t.eq(_count_log(w, "ice_dry"), 1, "not logged again")
	t.eq(int(w.stats.get("ice_dry", -1)), 1, "stats.ice_dry not counted again")


func test_dry_up_with_two_others_live_spawns_nothing(t) -> void:
	var w := _reactor_world(6)
	if not _rapi(t, w):
		return
	var a = _field(w, FA)
	var b = _field(w, FB)
	var c = _field(w, FC)
	t.eq(w.resources.reachable_ice_count(), 3, "three reachable")
	w.take_ice(a, 1000.0)
	t.eq(w.resources.ice_fields.size(), 2, "no extra spawn with 2 others live")
	t.check(w.resources.ice_fields.has(b) and w.resources.ice_fields.has(c), "the other two remain")
	t.eq(_count_log(w, "ice_found"), 0, "no ice_found")


func test_dry_up_below_two_reachable_spawns_at_once(t) -> void:
	var failures := 0
	var found_logs := 0
	for s in 40:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		var a = _field(w, FA)
		var b = _field(w, FB)
		w.take_ice(a, 1000.0)
		if w.resources.reachable_ice_count() < 2 or not w.resources.ice_fields.has(b):
			failures += 1
		found_logs += _count_log(w, "ice_found")
	t.eq(failures, 0, "dry-ups that left fewer than 2 reachable fields")
	t.eq(found_logs, 40, "one ice_found per dry-up")


func test_unreachable_fields_do_not_count_for_the_floor(t) -> void:
	var w := _reactor_world(9)
	if not _rapi(t, w):
		return
	var a = _field(w, FA)
	var far = _field(w, FAR1)  # live but unreachable
	var far2 = _field(w, FAR2)       # live but unreachable
	t.eq(w.resources.reachable_ice_count(), 1, "one reachable of three live")
	w.take_ice(a, 1000.0)
	t.eq(w.resources.ice_fields.size(), 3, "far fields kept and one new field spawned")
	t.check(w.resources.ice_fields.has(far) and w.resources.ice_fields.has(far2), "far fields stay in the list")
	t.check(w.resources.reachable_ice_count() >= 1, "the new field is reachable")


func test_repeated_dry_ups_keep_two_reachable_over_20_seeds(t) -> void:
	var low := 0
	var drained := 0
	for s in 20:
		var w := _reactor_world(100 + s)
		if not _rapi(t, w):
			return
		w.resources.spawn_site("ice", [90, 170])
		w.resources.spawn_site("ice", [90, 170])
		for k in 12:
			if w.resources.ice_fields.is_empty():
				break
			w.take_ice(w.resources.ice_fields[0], 1000.0)
			drained += 1
			if w.resources.reachable_ice_count() < 2:
				low += 1
	t.check(drained >= 200, "enough dry-ups exercised (%d)" % drained)
	t.eq(low, 0, "dry-ups that left fewer than 2 reachable")


# ---------------------------------------------------------------- scouting

func test_scouting_rate_one_reachable_field_500_seeds(t) -> void:
	if not _rapi(t, _reactor_world(1)):
		return
	var hit := 0
	for s in 500:
		var w := _reactor_world(s)
		_field(w, FA)
		for i in 2000:
			if w.resources.scout(0.05) != null:
				hit += 1
				break
	var frac := hit / 500.0
	t.between(frac, 0.97, 1.0, "fraction of 500 seeds that scout at least once in 2,000 steps (1 - e^-5 = 0.993), got %.3f" % frac)


func test_scouting_per_step_chance(t) -> void:
	# p = 0.05 x 0.05 = 0.0025 per step: the first-spawn wait is geometric with mean 400 steps.
	var total := 0
	var n := 0
	for s in 150:
		var w := _reactor_world(5000 + s)
		if not _rapi(t, w):
			return
		_field(w, FA)
		for i in 6000:
			if w.resources.scout(0.05) != null:
				total += i + 1
				n += 1
				break
	t.eq(n, 150, "every world scouts within 6,000 steps")
	t.between(total / float(maxi(n, 1)), 300.0, 500.0, "mean wait about 1 / 0.0025 = 400 steps")


func test_scouting_stops_at_two_reachable_and_ignores_unreachable_fields(t) -> void:
	var spawned := 0
	for s in 20:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		_field(w, FA)
		_field(w, FB)
		for i in 2000:
			if w.resources.scout(0.05) != null:
				spawned += 1
		t.eq(w.resources.ice_fields.size(), 2, "reachable 2: no new field (seed %d)" % s)
	t.eq(spawned, 0, "no spawns with 2 reachable over 20 x 2,000 steps")
	# Two listed but unreachable fields do not stop it.
	var hit := 0
	for s in 20:
		var w := _reactor_world(s)
		_field(w, FAR1)
		_field(w, FAR2)
		for i in 3000:
			if w.resources.scout(0.05) != null:
				hit += 1
				break
	t.check(hit >= 18, "listed but unreachable fields still trigger scouting (%d of 20)" % hit)


func test_scouting_continues_with_a_pit_present_and_spawns_a_valid_field(t) -> void:
	var done := 0
	for s in 20:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		w.resources.add_pit(48.0, 230.0)
		var before = w.resources.ice_fields.size()
		for i in 4000:
			var f = w.resources.scout(0.05)
			if f != null:
				done += 1
				t.eq(w.resources.ice_fields.size(), before + 1, "one field appended (seed %d)" % s)
				t.check(w.resources.ice_fields.has(f), "returned field is the appended one")
				t.check(_site_ok(w, f, true), "scouted field passes the trip rule and clearances (seed %d)" % s)
				break
	t.check(done >= 19, "scouting went on with a pit present (%d of 20)" % done)


func test_world_step_scouts_and_logs(t) -> void:
	var found_seed := -1
	var log_n := 0
	var stat_n := 0
	for s in 40:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		_scouting_on(t, w)
		_field(w, FA)
		for i in 1500:
			w.step()
			if int(w.stats.get("scouts_found", 0)) > 0:
				break
		stat_n = int(w.stats.get("scouts_found", 0))
		log_n = _count_log(w, "scouts_found")
		if stat_n > 0:
			found_seed = s
			break
	t.check(found_seed >= 0, "some seed in 40 scouts within 1,500 world steps")
	t.eq(stat_n, 1, "stats.scouts_found counts the find")
	t.eq(log_n, 1, "one scouts_found log line")


# ---------------------------------------------------------------- reachable-ice sample stat (spec 16)

func test_reachable_sample_stat_at_each_sol_boundary(t) -> void:
	var seen_not_ok := false
	var seen_ok := false
	for s in 24:
		var w := _reactor_world(s)
		if not _rapi(t, w):
			return
		_scouting_on(t, w)
		_field(w, FA)
		if s % 2 == 0:
			_field(w, FB)  # even seeds start with 2 reachable
		for i in 493:
			w.step()
		var n0 := int(w.stats.get("sol_samples", -1))
		var k0 := int(w.stats.get("reachable_ok_samples", -1))
		t.check(n0 >= 0 and k0 >= 0, "sample keys exist (seed %d)" % s)
		w.step()  # step 494: first step of sol 1
		t.eq(int(w.stats.get("sol_samples", -1)), n0 + 1, "one sample at the first step of sol 1 (seed %d)" % s)
		var ok_now: bool = w.resources.reachable_ice_count() >= 2
		t.eq(int(w.stats.get("reachable_ok_samples", -1)), k0 + (1 if ok_now else 0), "ok sample iff >= 2 reachable (seed %d)" % s)
		seen_not_ok = seen_not_ok or not ok_now
		seen_ok = seen_ok or ok_now
		for i in 492:
			w.step()
		t.eq(int(w.stats.get("sol_samples", -1)), n0 + 1, "no sample inside the sol (seed %d)" % s)
		w.step()  # step 987: sol 2
		t.eq(int(w.stats.get("sol_samples", -1)), n0 + 2, "second sample at sol 2 (seed %d)" % s)
	t.check(seen_ok, "some seed sampled with >= 2 reachable")
	t.check(seen_not_ok, "some seed sampled with fewer than 2 (scouting had not found one yet)")


# ---------------------------------------------------------------- seeded determinism of spawning

func test_spawn_determinism_and_seed_sensitivity(t) -> void:
	var a := _reactor_world(31)
	var b := _reactor_world(31)
	var c := _reactor_world(32)
	if not _rapi(t, a):
		return
	for w in [a, b, c]:
		_grow_and_spawn(w, 24)
	t.eq(_sig_world(a), _sig_world(b), "same seed, same colony and fields")
	t.check(_sig_world(a) != _sig_world(c), "different seed, different fields")
	# Scouting is seeded too.
	var fa := _reactor_world(8)
	var fb := _reactor_world(8)
	_field(fa, FA)
	_field(fb, FA)
	for i in 3000:
		fa.resources.scout(0.05)
		fb.resources.scout(0.05)
	t.eq(_sig_world(fa), _sig_world(fb), "scouting is deterministic per seed")
	t.eq(fa.rng.randf(), fb.rng.randf(), "same number of rng draws consumed")
