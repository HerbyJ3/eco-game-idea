class_name Buildings
extends RefCounted
## Building records and the list that owns them. Spec: life-support-power.md sections 4 and 7.
## Power, layout, tunnels and construction arrive in later steps; the record already carries the
## fields they need.

## One building. `built` is 0..1 (1 = finished); a construction site is a building with built < 1.
class Building extends RefCounted:
	var id: int
	var kind: String
	var tx: int
	var ty: int
	var tw: int
	var th: int
	var built: float
	var offline := false
	## t when it went offline, else null (feeds stats.max_offline_h).
	var offline_since: Variant = null
	## Tunnel to the parent, or null (reactor, hand-made buildings): {parent_id, p1, p2, len, rect}.
	## p1 (px) is on the parent edge, p2 on this building's edge, rect is in tiles. The corridor is
	## identified by this building's id and is traversable once this building is finished.
	var corridor: Variant = null

	func finished() -> bool:
		return built >= 1.0

	## Online = built and not offline.
	func online() -> bool:
		return built >= 1.0 and not offline

	## Door = bottom centre, in px.
	func door(tile_px: float) -> Vector2:
		return Vector2((tx + tw / 2.0) * tile_px, (ty + th) * tile_px)

## Never-shorted sentinel (spec section 4).
const NEVER := -1e9
## The four layout directions, in draw order (a hard rule of find_spot, spec 7.3).
const DIRS: Array[String] = ["r", "l", "u", "d"]

var list: Array[Building] = []
var last_short_t: float = NEVER
## Set by SimWorld: the god-power hooks (supply multiplier) and the world clock.
var powers: Powers
## World clock, pushed in by SimWorld whenever t changes (a Callable here would form a reference cycle).
var now: float = 0.0
var cfg: Dictionary
var _next_id := 1


func _init() -> void:
	cfg = SimData.buildings()


func _now() -> float:
	return now


## Adds a building; size defaults to the smallest random size from data. Returns it.
func add(kind: String, tx: int, ty: int, built: float = 1.0, tw: int = -1, th: int = -1) -> Building:
	assert(cfg.kinds.has(kind), "unknown building kind %s" % kind)
	var b := Building.new()
	b.id = _next_id
	_next_id += 1
	b.kind = kind
	b.tx = tx
	b.ty = ty
	b.tw = tw if tw > 0 else int(cfg.size.tw[0])
	b.th = th if th > 0 else int(cfg.size.th[0])
	b.built = built
	list.append(b)
	return b


func get_building(id: int) -> Building:
	for b in list:
		if b.id == id:
			return b
	return null


func count() -> int:
	return list.size()


## Online buildings of a kind.
func count_online(kind: String) -> int:
	var n := 0
	for b in list:
		if b.kind == kind and b.online():
			n += 1
	return n


# ---------------------------------------------------------------- layout (spec section 7.3)

## Chebyshev separation in tiles between two tile rects (<= 0 when touching or overlapping).
static func separation(a: Rect2i, b: Rect2i) -> int:
	var gx := maxi(a.position.x - b.end.x, b.position.x - a.end.x)
	var gy := maxi(a.position.y - b.end.y, b.position.y - a.end.y)
	return maxi(gx, gy)


## Rounds half up: floor(centre - own/2 + 0.5).
static func _centred(start: int, size: int, own: int) -> int:
	return floori(start + size / 2.0 - own / 2.0 + 0.5)


## Rect and corridor rect (tiles) of a child `gap` tiles beyond `parent` in `dir`, centred on the
## parent's mid row or column. The corridor is `corridor_width_tiles` wide and `gap` long.
func _place(parent: Building, dir: String, tw: int, th: int, gap: int) -> Dictionary:
	var cw: int = int(cfg.find_spot.corridor_width_tiles)
	var px := parent.tx
	var py := parent.ty
	var ex := parent.tx + parent.tw
	var ey := parent.ty + parent.th
	var cx := _centred(px, parent.tw, cw)
	var cy := _centred(py, parent.th, cw)
	match dir:
		"r":
			return {"rect": Rect2i(ex + gap, _centred(py, parent.th, th), tw, th),
					"corridor_rect": Rect2i(ex, cy, gap, cw)}
		"l":
			return {"rect": Rect2i(px - gap - tw, _centred(py, parent.th, th), tw, th),
					"corridor_rect": Rect2i(px - gap, cy, gap, cw)}
		"d":
			return {"rect": Rect2i(_centred(px, parent.tw, tw), ey + gap, tw, th),
					"corridor_rect": Rect2i(cx, ey, cw, gap)}
		_:
			return {"rect": Rect2i(_centred(px, parent.tw, tw), py - gap - th, tw, th),
					"corridor_rect": Rect2i(cx, py - gap, cw, gap)}


## Centre line of a corridor rect as [p1, p2] in px, p1 on the parent side.
func _corridor_points(cr: Rect2i, dir: String) -> Array[Vector2]:
	var tp: float = float(cfg.tile_px)
	var mid := Vector2(cr.position.x + cr.size.x / 2.0, cr.position.y + cr.size.y / 2.0) * tp
	var a := Vector2(cr.position.x, cr.position.y) * tp
	var e := Vector2(cr.end.x, cr.end.y) * tp
	match dir:
		"r":
			return [Vector2(a.x, mid.y), Vector2(e.x, mid.y)]
		"l":
			return [Vector2(e.x, mid.y), Vector2(a.x, mid.y)]
		"d":
			return [Vector2(mid.x, a.y), Vector2(mid.x, e.y)]
		_:
			return [Vector2(mid.x, e.y), Vector2(mid.x, a.y)]


## Adds a building `gap` tiles beyond the parent with its corridor. No overlap check (find_spot
## does that); hand-made graphs may place anything.
func add_attached(kind: String, parent_id: int, dir: String, tw: int, th: int, gap: int,
		built: float = 1.0) -> Building:
	var parent := get_building(parent_id)
	assert(parent != null, "add_attached: unknown parent %d" % parent_id)
	var pl := _place(parent, dir, tw, th, gap)
	var r: Rect2i = pl.rect
	var b := add(kind, r.position.x, r.position.y, built, tw, th)
	var pts := _corridor_points(pl.corridor_rect, dir)
	b.corridor = {"parent_id": parent_id, "p1": pts[0], "p2": pts[1],
			"len": gap * float(cfg.tile_px), "rect": pl.corridor_rect}
	return b


## Founding buildings from data/buildings.json `layout`: the core, then each attached building.
func create_layout() -> void:
	var core: Dictionary = cfg.layout.core
	var root := add("reactor", int(core.tx), int(core.ty), 1.0, int(core.tw), int(core.th))
	for a: Dictionary in cfg.layout.attached:
		add_attached(a.kind, root.id, a.dir, int(a.tw), int(a.th), int(a.gap), 1.0)


## Spec 7.3. Up to find_spot.tries tries; the first acceptable spot wins. Adds nothing.
## Draws per try: pick(finished buildings), pick(dirs), tw, th, gap. Returns {} for no spot, else
## {parent_id, dir, tw, th, gap, tx, ty, rect, corridor_rect}.
func find_spot(rng: SimRng) -> Dictionary:
	var parents: Array[Building] = []
	for b in list:
		if b.finished():
			parents.append(b)
	if parents.is_empty():
		return {}
	var fs: Dictionary = cfg.find_spot
	var size: Dictionary = cfg.size
	for i in int(fs.tries):
		var parent: Building = rng.pick(parents)
		var dir: String = rng.pick(DIRS)
		var tw := rng.randi_range(int(size.tw[0]), int(size.tw[1]))
		var th := rng.randi_range(int(size.th[0]), int(size.th[1]))
		var gap := rng.randi_range(int(size.gap[0]), int(size.gap[1]))
		var pl := _place(parent, dir, tw, th, gap)
		if _spot_clear(pl.rect, pl.corridor_rect, parent.id):
			var r: Rect2i = pl.rect
			return {"parent_id": parent.id, "dir": dir, "tw": tw, "th": th, "gap": gap,
					"tx": r.position.x, "ty": r.position.y, "rect": r, "corridor_rect": pl.corridor_rect}
	return {}


func _spot_clear(rect: Rect2i, cor: Rect2i, parent_id: int) -> bool:
	var overlap: int = int(cfg.find_spot.overlap_margin_tiles)
	var margin: int = int(cfg.find_spot.corridor_margin_tiles)
	for o in list:
		if separation(rect, Rect2i(o.tx, o.ty, o.tw, o.th)) < overlap:
			return false
		if o.id != parent_id and separation(cor, Rect2i(o.tx, o.ty, o.tw, o.th)) < margin:
			return false
		if o.corridor != null:
			var oc: Rect2i = o.corridor.rect
			if separation(rect, oc) < margin or separation(cor, oc) < margin:
				return false
	return true


## First corridor (its id is the child building's id) on the shortest path over finished corridors,
## breadth first in creation order. 0 when from == to, either is unknown, or there is no path.
## Offline buildings are passable (spec A3).
func next_hop(from_id: int, to_id: int) -> int:
	if from_id == to_id or get_building(from_id) == null or get_building(to_id) == null:
		return 0
	var first := {from_id: 0}
	var queue: Array[int] = [from_id]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for b in list:
			if b.corridor == null or not b.finished():
				continue
			var other := 0
			if b.id == cur:
				other = int(b.corridor.parent_id)
			elif int(b.corridor.parent_id) == cur:
				other = b.id
			else:
				continue
			if first.has(other):
				continue
			first[other] = b.id if cur == from_id else first[cur]
			if other == to_id:
				return int(first[other])
			queue.append(other)
	return 0


# ---------------------------------------------------------------- power (spec section 7)

func kind_draw(kind: String) -> float:
	return float(cfg.kinds[kind].draw)


## Finished reactors x reactor_supply, times the fortune multiplier while now < power_multiplier_until.
func supply() -> float:
	var n := 0
	for b in list:
		if b.kind == "reactor" and b.finished():
			n += 1
	var mult := 1.0
	if powers != null and _now() < powers.power_multiplier_until:
		mult = float(cfg.fortune.multiplier)
	return n * float(cfg.reactor_supply) * mult


## Online finished buildings draw their kind draw; unfinished sites draw site_draw; offline draw 0.
func draw() -> float:
	var total := 0.0
	for b in list:
		if not b.finished():
			total += float(cfg.site_draw)
		elif not b.offline:
			total += kind_draw(b.kind)
	return total


func margin() -> float:
	return supply() - draw()


## The draw if no finished building were offline (spec section 13, target 5).
func demand() -> float:
	var total := 0.0
	for b in list:
		total += float(cfg.site_draw) if not b.finished() else kind_draw(b.kind)
	return total


## Forget the last short so the re-online hold is over (called by Powers).
func clear_short_hold() -> void:
	last_short_t = NEVER


## Nearest online habitat by distance between building centres (tiles), the `from` building
## itself included. Null if none. Ties go to the lowest id (list is in ascending id order).
func nearest_online_habitat(from_building_id: int) -> Building:
	var from := get_building(from_building_id)
	if from == null:
		return null
	var c := Vector2(from.tx + from.tw / 2.0, from.ty + from.th / 2.0)
	var best: Building = null
	var best_d := INF
	for b in list:
		if b.kind != "habitat" or not b.online():
			continue
		var d := c.distance_squared_to(Vector2(b.tx + b.tw / 2.0, b.ty + b.th / 2.0))
		if d < best_d:
			best_d = d
			best = b
	return best


## Phase 3. At most one short or one re-online. Returns {} or
## {kind: "short"|"back_online", building: Building, offline_h: float (back_online only)}.
## Draws (only on a short): chance(newest_chance); on failure, pick(candidates).
func manage_power(t: float, rng: SimRng) -> Dictionary:
	var sup := supply()
	var cur := draw()
	if cur > sup:
		var candidates: Array = []
		for b in list:
			if b.kind != "reactor" and b.online():
				candidates.append(b)
		if candidates.is_empty():
			return {}
		var target: Building
		if rng.chance(float(cfg.short.newest_chance)):
			target = candidates[candidates.size() - 1]
		else:
			target = rng.pick(candidates)
		target.offline = true
		target.offline_since = t
		last_short_t = t
		return {"kind": "short", "building": target}
	if t - last_short_t <= float(cfg.reonline.hold_h) + SimWorld.STEP_EPS:
		return {}
	var limit := float(cfg.reonline.load_fraction) * sup
	for b in list:
		if b.finished() and b.offline and cur + kind_draw(b.kind) <= limit:
			var since := float(b.offline_since) if b.offline_since != null else t
			b.offline = false
			b.offline_since = null
			return {"kind": "back_online", "building": b, "offline_h": t - since}
	return {}
