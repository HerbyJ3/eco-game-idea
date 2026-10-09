extends Control
## Debug dot map: buildings as rects, beings outside as dots, ice and pits as circles.
## Draws from sim positions only. Auto-fits to the content.

const PAD := 20.0
const COL_BUILDING := Color(0.55, 0.45, 0.4)
const COL_OFFLINE := Color(0.8, 0.25, 0.2)
const COL_SITE := Color(0.9, 0.8, 0.3)
const COL_ICE := Color(0.5, 0.8, 1.0)
const COL_PIT := Color(0.7, 0.6, 0.5)
const COL_BEING := Color(1.0, 1.0, 1.0)

var _sim: Node


func _ready() -> void:
	_sim = get_node("/root/Sim")


func setup(sim: Node) -> void:
	_sim = sim


func _draw() -> void:
	var w: SimWorld = _sim.world
	var tp := float(w.buildings.cfg.tile_px)
	var box := Rect2()
	var first := true
	var rects: Array[Rect2] = []
	for b in w.buildings.list:
		rects.append(Rect2(b.tx * tp, b.ty * tp, b.tw * tp, b.th * tp))
	var circles: Array = []
	for s in w.resources.ice_fields:
		circles.append([s.pos(), s.r, COL_ICE])
	for s in w.resources.pits:
		circles.append([s.pos(), s.r, COL_PIT])
	for r in rects:
		box = r if first else box.merge(r)
		first = false
	for c in circles:
		var cr := Rect2(c[0] - Vector2(c[1], c[1]), Vector2(c[1], c[1]) * 2.0)
		box = cr if first else box.merge(cr)
		first = false
	if first or box.size.x <= 0.0 or box.size.y <= 0.0:
		return
	var k := minf((size.x - 2.0 * PAD) / box.size.x, (size.y - 2.0 * PAD) / box.size.y)
	if k <= 0.0:
		return
	var origin := Vector2(PAD, PAD) - box.position * k
	for i in w.buildings.list.size():
		var b: Buildings.Building = w.buildings.list[i]
		var col := COL_SITE if not b.finished() else (COL_OFFLINE if b.offline else COL_BUILDING)
		draw_rect(Rect2(origin + rects[i].position * k, rects[i].size * k), col, false, 2.0)
	for c in circles:
		draw_arc(origin + c[0] * k, maxf(c[1] * k, 3.0), 0.0, TAU, 24, c[2], 2.0)
	for being in w.beings:
		if being.is_outside() and being.x != null:
			draw_circle(origin + Vector2(float(being.x), float(being.y)) * k, 2.5, COL_BEING)
