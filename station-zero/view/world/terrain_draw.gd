extends RefCounted
## Layers L0 and L1 (spec 5.8, 6): the Mars ground, ice fields and regolith pits from sim data. Procedural while the
## decal entries of the manifest are placeholders (no file); rocks and craters are skipped then. Sparkles animate on
## real time, everything else is static per sim state.

const WorldCtx = preload("res://view/world/world_ctx.gd")

## Tessellation of the spoil heap's half ellipse (a drawing detail, not a game value).
const HEAP_SEGMENTS := 16

## Ice blobs per field, generated once from a view RNG seeded by the field's rounded position (stable across frames).
var _blobs: Dictionary = {}
## Scatter candidates by world cell (a Vector2i), generated once.
var _cells: Dictionary = {}


func draw(c: Object, x: WorldCtx) -> void:
	var t: Dictionary = x.art.terrain
	c.draw_rect(x.view_rect.grow(float(x.art.camera.pan_margin_px)), x.col(t.ground_color))
	var res: Resources = x.world.resources
	var ice_cfg: Dictionary = t.ice
	var decals := x.lib.has_art("terrain.decal.ice")
	if x.lib.has_art("terrain.decal.rocks") or x.lib.has_art("terrain.decal.crater"):
		_draw_scatter(c, x)
	for f in res.ice_fields:
		var reach: float = f.r * float(ice_cfg.blob_rr[1]) + f.r
		if x.visible(Rect2(f.x - reach, f.y - reach, reach * 2.0, reach * 2.0)):
			_draw_ice(c, x, f, ice_cfg, decals)
	for p in res.pits:
		var reach: float = float(t.pit.base_w_px) + float(t.pit.w_per_sqrt_dug_px) * sqrt(float(p.dug)) \
				+ float(t.pit.heap_offset_px[0]) + float(t.pit.heap_rx_px)
		if x.visible(Rect2(p.x - reach, p.y - reach, reach * 2.0, reach * 2.0)):
			_draw_pit(c, x, p, t.pit)


func _blobs_for(f: Resources.Site, cfg: Dictionary) -> Array:
	var key := "%d,%d" % [roundi(f.x), roundi(f.y)]
	if not _blobs.has(key):
		var r := RandomNumberGenerator.new()
		r.seed = key.hash()
		var list: Array = []
		for i in int(cfg.blob_count):
			list.append({"dx": r.randf_range(float(cfg.blob_dx[0]), float(cfg.blob_dx[1])),
					"dy": r.randf_range(float(cfg.blob_dy[0]), float(cfg.blob_dy[1])),
					"rr": r.randf_range(float(cfg.blob_rr[0]), float(cfg.blob_rr[1]))})
		_blobs[key] = list
	return _blobs[key]


func _draw_ice(c: Object, x: WorldCtx, f: Resources.Site, cfg: Dictionary, decals: bool) -> void:
	if decals:
		_draw_decal(c, x, "terrain.decal.ice", Vector2(f.x, f.y), float(x.art.optional.decals.ice_width_over_r) * f.r)
		_draw_sparkles(c, x, f, cfg)
		return
	var left := float(cfg.left_min) + float(cfg.left_span) * float(f.amount) / float(f.start)
	var blobs := _blobs_for(f, cfg)
	var off := float(cfg.offset_frac)
	var base: Color = x.col(cfg.base_color)
	var hi: Color = x.col(cfg.highlight_color)
	var hi_off := float(cfg.highlight_offset_px)
	for b in blobs:
		var p := Vector2(f.x + b.dx * f.r * off, f.y + b.dy * f.r * off)
		x.ellipse(c, p, f.r * b.rr * left, f.r * b.rr * float(cfg.y_scale) * left, base)
	for b in blobs:
		var p := Vector2(f.x + b.dx * f.r * off + hi_off, f.y + b.dy * f.r * off + hi_off)
		x.ellipse(c, p, f.r * b.rr * left * float(cfg.highlight_scale[0]), f.r * b.rr * left * float(cfg.highlight_scale[1]), hi)
	_draw_sparkles(c, x, f, cfg)


func _draw_sparkles(c: Object, x: WorldCtx, f: Resources.Site, cfg: Dictionary) -> void:
	var sparkle: Color = x.col(cfg.sparkle_color)
	var size := float(cfg.sparkle_size_px)
	for i in int(cfg.sparkle_count):
		var ang := i * float(cfg.sparkle_angle_step_rad) + f.x
		var rr: float = f.r * float(cfg.sparkle_radius_frac) * float((i * int(cfg.sparkle_hash_mul)) % int(cfg.sparkle_hash_mod)) \
				/ float(cfg.sparkle_hash_mod)
		if sin(x.real_time * float(cfg.sparkle_rate_rad_s) + 2.0 * i) > float(cfg.sparkle_threshold):
			c.draw_rect(Rect2(f.x + cos(ang) * rr, f.y + sin(ang) * rr * float(cfg.sparkle_y_squash), size, size), sparkle)


func _draw_pit(c: Object, x: WorldCtx, p: Resources.Site, cfg: Dictionary) -> void:
	var root := sqrt(float(p.dug))
	var w := float(cfg.base_w_px) + root * float(cfg.w_per_sqrt_dug_px)
	var h := w * float(cfg.h_over_w)
	var rim := float(cfg.rim_expand_px)
	var top_left := Vector2(p.x - w * 0.5, p.y - h * 0.5)
	if x.lib.has_art("terrain.decal.pit"):
		_draw_decal(c, x, "terrain.decal.pit", Vector2(p.x, p.y), float(x.art.optional.decals.pit_width_over_w) * w)
	else:
		c.draw_rect(Rect2(top_left - Vector2(rim, rim), Vector2(w, h) + Vector2(rim, rim) * 2.0), x.col(cfg.rim_color))
		c.draw_rect(Rect2(top_left, Vector2(w, h)), x.col(cfg.hole_color))
		c.draw_rect(Rect2(top_left, Vector2(w, h * float(cfg.shade_frac))), x.col(cfg.shade_color))
		var stripe: Color = x.col(cfg.stripe_color)
		var yy: float = p.y
		while yy < p.y + h * 0.5 - 1.0:
			c.draw_rect(Rect2(top_left.x + 1.0, yy, w - 2.0, float(cfg.stripe_h_px)), stripe)
			yy += float(cfg.stripe_spacing_px)
	var heap := Vector2(p.x + w * 0.5 + float(cfg.heap_offset_px[0]), p.y + h * 0.5 + float(cfg.heap_offset_px[1]))
	var rx := float(cfg.heap_rx_px) + root * float(cfg.heap_rx_per_sqrt_dug_px)
	var ry := float(cfg.heap_ry_px) + root * float(cfg.heap_ry_per_sqrt_dug_px)
	var pts := PackedVector2Array()
	for k in HEAP_SEGMENTS + 1:
		var a := PI + PI * float(k) / float(HEAP_SEGMENTS)
		pts.append(heap + Vector2(cos(a) * rx, sin(a) * ry))
	c.draw_colored_polygon(pts, x.col(cfg.heap_color))


## A decal of the manifest centred on p at the given world width, its own aspect kept.
func _draw_decal(c: Object, x: WorldCtx, id: String, p: Vector2, width: float, rot: float = 0.0) -> void:
	var t := x.lib.texture(id)
	if t == null:
		return
	var size := Vector2(width, width * float(t.get_height()) / float(t.get_width()))
	if is_zero_approx(rot):
		x.blit(c, id, Rect2(p - size * 0.5, size))
		return
	c.draw_set_transform(p, rot, Vector2.ONE)
	x.blit(c, id, Rect2(-size * 0.5, size))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Candidate rocks and craters of one world cell, from a view RNG seeded by (scatter_seed, cell): {pos, width, rot, crater}.
func _cell_items(cx: int, cy: int, cfg: Dictionary) -> Array:
	var key := Vector2i(cx, cy)
	if _cells.has(key):
		return _cells[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(cfg.scatter_seed), cx, cy])
	var cell := float(cfg.scatter_cell_px)
	var out: Array = []
	for crater in [false, true]:
		if r.randf() < float(cfg.crater_per_cell if crater else cfg.rock_per_cell):
			var wr: Array = cfg.crater_width_px if crater else cfg.rock_width_px
			out.append({"pos": Vector2((cx + r.randf()) * cell, (cy + r.randf()) * cell),
					"width": r.randf_range(float(wr[0]), float(wr[1])), "rot": r.randf() * TAU, "crater": crater})
	_cells[key] = out
	return out


## Rocks and craters scattered over the visible cells, kept clear of buildings, sites, ice fields and pits (spec 3.10).
func _draw_scatter(c: Object, x: WorldCtx) -> void:
	var cfg: Dictionary = x.art.optional.decals
	var cell := float(cfg.scatter_cell_px)
	var area := x.view_rect.grow(cell)
	var tiles: Array = []
	for b in x.world.buildings.list:
		tiles.append(x.vm.footprint_rect(b).grow(float(cfg.clearance_building_px)))
	var spots: Array = []
	for f in x.world.resources.ice_fields:
		spots.append(Rect2(f.x, f.y, 0.0, 0.0).grow(float(cfg.clearance_site_px) + f.r))
	for p in x.world.resources.pits:
		spots.append(Rect2(p.x, p.y, 0.0, 0.0).grow(float(cfg.clearance_site_px)))
	for cy in range(int(floor(area.position.y / cell)), int(floor(area.end.y / cell)) + 1):
		for cx in range(int(floor(area.position.x / cell)), int(floor(area.end.x / cell)) + 1):
			for it in _cell_items(cx, cy, cfg):
				var id := "terrain.decal.crater" if it.crater else "terrain.decal.rocks"
				if not x.lib.has_art(id) or not x.visible(Rect2(it.pos, Vector2.ZERO).grow(it.width)):
					continue
				var blocked := false
				for r in tiles + spots:
					if (r as Rect2).has_point(it.pos):
						blocked = true
						break
				if not blocked:
					_draw_decal(c, x, id, it.pos, it.width, it.rot)
