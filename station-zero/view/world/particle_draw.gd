extends RefCounted
## Particles from the model's snapshot (spec 5.4, 5.6): dust and frost under the tint (L7), sparks and flicker as
## additive light (L9). Positions, life and velocity come from the particle model; this only draws them.

const WorldCtx = preload("res://view/world/world_ctx.gd")


## Dig dust and frost: soft discs fading with the life left, drawn above the beings and below the tint.
func draw_dust(c: Object, x: WorldCtx) -> void:
	var cfg: Dictionary = x.art.particles.dig
	for p in x.vm.particles.snapshot():
		if p.kind != "dig":
			continue
		var left: float = p.life / p.max_life
		var hex: String = cfg.frost_color if p.ice else cfg.dust_color
		c.draw_circle(Vector2(p.x, p.y), p.radius, x.col(hex, float(cfg.alpha) * left))


## Weld sparks as short additive streaks, and the offline flicker discs.
func draw_sparks(c: Object, x: WorldCtx) -> void:
	var cfg: Dictionary = x.art.particles
	var spark: Dictionary = cfg.spark
	var hot: Color = x.col(spark.hot_color)
	var cool: Color = x.col(spark.cool_color)
	var width := float(spark.line_w_px)
	var off: Dictionary = x.art.offline
	var flicker: Color = x.col(off.flicker_color, float(off.flicker_alpha))
	for p in x.vm.particles.snapshot():
		match p.kind:
			"weld_hand", "weld_seam":
				var left: float = p.life / p.max_life
				var color := hot if left > float(spark.hot_above_life_left) else cool
				var from := Vector2(p.x - p.vx * x.dt, p.y - p.vy * x.dt)
				c.draw_line(from, Vector2(p.x, p.y), Color(color.r, color.g, color.b, left), width)
			"flicker":
				c.draw_circle(Vector2(p.x, p.y), float(off.flicker_radius_px), flicker)
