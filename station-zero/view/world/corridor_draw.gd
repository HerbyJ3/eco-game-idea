extends RefCounted
## Layer L3 (spec 5.5, 5.7, 6) and the corridor lamps of L9: the tunnels between buildings. A tunnel reveals during the
## first part of its building's construction (the owning building's `built`, corridors have none of their own), with a
## dashed outline of the full path until the building is finished. Pure drawing from the sim records.

const WorldCtx = preload("res://view/world/world_ctx.gd")

const Construction = preload("res://view/model/construction.gd")


## Corridors with the tunnel part that is built: {p1, p2, tip (end of the revealed part), horizontal, building}.
static func tunnels(world: SimWorld, art: Dictionary) -> Array:
	var out: Array = []
	for b in world.buildings.list:
		if b.corridor == null:
			continue
		var p1: Vector2 = b.corridor.p1
		var p2: Vector2 = b.corridor.p2
		var prog := Construction.corridor_frac(b.built, art)
		out.append({"p1": p1, "p2": p2, "tip": p1.lerp(p2, prog), "prog": prog, "horizontal": is_equal_approx(p1.y, p2.y),
				"building": b})
	return out


func draw(c: Object, x: WorldCtx) -> void:
	var cfg: Dictionary = x.art.corridor
	var sh: Dictionary = x.art.light.shadow
	var shadow_a: float = float(sh.alpha) * x.daylight
	var shadow_off: Vector2 = x.shadow * float(sh.corridor_scale)
	for t in tunnels(x.world, x.art):
		var b: Buildings.Building = t.building
		var span := Rect2(t.p1, Vector2.ZERO).expand(t.p2).grow(float(cfg.edge_half_px))
		if not x.visible(span):
			continue
		if b.built < 1.0:
			var kind_cfg: Variant = x.art.kinds.get(b.kind)
			var hex: String = kind_cfg.color if kind_cfg != null else String(cfg.unbuilt_color_fallback)
			c.draw_dashed_line(t.p1, t.p2, x.col(hex, float(cfg.unbuilt_alpha)), float(cfg.unbuilt_line_w_px),
					float(cfg.unbuilt_dash_px[0]))
			if t.prog <= 0.0:
				continue
		_draw_tunnel(c, x, cfg, t, shadow_a, shadow_off)


func _draw_tunnel(c: Object, x: WorldCtx, cfg: Dictionary, t: Dictionary, shadow_a: float, shadow_off: Vector2) -> void:
	var a: Vector2 = t.p1
	var e: Vector2 = t.tip
	var lo := Vector2(minf(a.x, e.x), minf(a.y, e.y))
	var hi := Vector2(maxf(a.x, e.x), maxf(a.y, e.y))
	var half := float(cfg.edge_half_px)
	var top := float(cfg.body_top_px)
	var body := float(cfg.body_h_px)
	var hl := float(cfg.highlight_h_px)
	var rib_w := float(cfg.rib_w_px)
	var rib_h := float(cfg.rib_h_px)
	var spacing := float(cfg.rib_spacing_px)
	var inset := float(cfg.rib_inset_px)
	var shadow: Color = x.col(x.art.light.shadow.color, shadow_a)
	var edge: Color = x.col(cfg.edge_color)
	var body_c: Color = x.col(cfg.body_color)
	var hl_c: Color = x.col(cfg.highlight_color)
	var rib_c: Color = x.col(cfg.rib_color)
	var sw := float(cfg.shadow_w_px)
	var sh_half := float(cfg.shadow_half_px)
	if t.horizontal:
		var len := hi.x - lo.x
		var y: float = a.y
		if shadow_a > 0.0:
			c.draw_rect(Rect2(lo.x + shadow_off.x, y - sh_half + shadow_off.y, len, sw), shadow)
		c.draw_rect(Rect2(lo.x, y - half, len, half * 2.0), edge)
		c.draw_rect(Rect2(lo.x, y + top, len, body), body_c)
		c.draw_rect(Rect2(lo.x, y + top, len, hl), hl_c)
		var rx := lo.x + inset
		while rx < hi.x - rib_w:
			c.draw_rect(Rect2(rx, y + top, rib_w, rib_h), rib_c)
			rx += spacing
	else:
		var len := hi.y - lo.y
		var px: float = a.x
		if shadow_a > 0.0:
			c.draw_rect(Rect2(px - sh_half + shadow_off.x, lo.y + shadow_off.y, sw, len), shadow)
		c.draw_rect(Rect2(px - half, lo.y, half * 2.0, len), edge)
		c.draw_rect(Rect2(px + top, lo.y, body, len), body_c)
		c.draw_rect(Rect2(px + top, lo.y, hl, len), hl_c)
		var ry := lo.y + inset
		while ry < hi.y - rib_w:
			c.draw_rect(Rect2(px + top, ry, rib_h, rib_w), rib_c)
			ry += spacing


## Additive lamps along finished tunnels at night: 1 px dots from the parent end, ending short of the building.
func draw_lamps(c: Object, x: WorldCtx) -> void:
	if x.night <= 0.0:
		return
	var l: Dictionary = x.art.light.corridor_lamps
	var color: Color = x.col(l.color, float(l.alpha) * x.night)
	var size := float(l.size_px)
	for t in tunnels(x.world, x.art):
		var b: Buildings.Building = t.building
		if not b.finished() or not x.visible(Rect2(t.p1, Vector2.ZERO).expand(t.p2).grow(size)):
			continue
		var along: Vector2 = (t.p2 - t.p1)
		var len := along.length()
		var dir := along / len
		var d := float(l.start_px)
		while d < len - float(l.end_inset_px):
			var p: Vector2 = t.p1 + dir * d
			c.draw_rect(Rect2(p - Vector2(size, size) * 0.5, Vector2(size, size)), color)
			d += float(l.spacing_px)
