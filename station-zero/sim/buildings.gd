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
var _next_id := 1


## Adds a building; size defaults to the smallest random size from data. Returns it.
func add(kind: String, tx: int, ty: int, built: float = 1.0, tw: int = -1, th: int = -1) -> Building:
	var cfg := SimData.buildings()
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
