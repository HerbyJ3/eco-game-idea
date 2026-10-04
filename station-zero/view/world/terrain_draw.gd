extends RefCounted
## Layers L0 and L1 (spec 5.8, 6): the Mars ground, ice fields and regolith pits from sim data. Procedural while the
## decal entries of the manifest are placeholders (no file); rocks and craters are skipped then. Sparkles animate on
## real time, everything else is static per sim state.

const WorldCtx = preload("res://view/world/world_ctx.gd")

## Tessellation of the spoil heap's half ellipse (a drawing detail, not a game value).
const HEAP_SEGMENTS := 16

## Ice blobs per field, generated once from a view RNG seeded by the field's rounded position (stable across frames).
var _blobs: Dictionary = {}


func draw(c: Object, x: WorldCtx) -> void:
	var t: Dictionary = x.art.terrain
	c.draw_rect(x.view_rect.grow(float(x.art.camera.pan_margin_px)), x.col(t.ground_color))
	var res: Resources = x.world.resources
	var ice_cfg: Dictionary = t.ice
	var decals := x.lib.has_art("terrain.decal.ice")
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


func _draw_ice(c: Object, x: WorldCtx, f: Resources.Site, cfg: Dictionary, _decals: bool) -> void:
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
