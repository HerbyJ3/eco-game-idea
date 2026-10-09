extends RefCounted
## Sprite fit rule (spec sprite-view.md 4.1). Pure geometry, no state.


## Fits a sprite inside a footprint with one scale for both axes, its pivot on the footprint's bottom edge centre.
## Returns {rect: Rect2 (where the sprite is drawn), scale: float, door: Vector2 (where the pivot landed)}.
## With fit.clamp_inside the sprite is shifted horizontally so it never leaves the footprint.
static func fit_sprite(footprint: Rect2, sprite_size: Vector2, pivot_norm: Vector2, art: Dictionary) -> Dictionary:
	var cfg: Dictionary = art.fit
	var f := footprint.grow(float(cfg.box_pad_px))
	var s := minf(f.size.x / sprite_size.x, f.size.y / sprite_size.y)
	var size := sprite_size * s
	var origin := Vector2(f.position.x + f.size.x * 0.5 - pivot_norm.x * size.x, f.end.y - pivot_norm.y * size.y)
	if bool(cfg.clamp_inside):
		origin.x = clampf(origin.x, f.position.x, f.end.x - size.x)
	return {"rect": Rect2(origin, size), "scale": s, "door": origin + pivot_norm * size}
