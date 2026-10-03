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
