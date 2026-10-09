extends RefCounted
## Footprint age, alpha and the visible set (spec sprite-view.md 5.7). The sim's footprint list is read only.


## Age in fades: 0 fresh, 1 gone. Fade length is suits.footprint.fade_sols sols.
static func age_of(fp: Resources.Footprint, world: SimWorld) -> float:
	return (world.t - fp.t) / (float(SimData.suits().footprint.fade_sols) * world.clock.sol_h)


static func alpha(age: float, heavy: bool, art: Dictionary) -> float:
	if age >= 1.0:
		return 0.0
	var fp: Dictionary = art.footprint
	return float(fp.heavy_alpha if heavy else fp.light_alpha) * (1.0 - age)


## Prints inside rect that are still visible, as {x, y, heading, alpha, heavy}.
static func drawn(world: SimWorld, rect: Rect2, art: Dictionary) -> Array:
	var out: Array = []
	var fade_h := float(SimData.suits().footprint.fade_sols) * world.clock.sol_h
	for f in world.resources.footprints:
		var age := (world.t - f.t) / fade_h
		if age < 1.0 and rect.has_point(Vector2(f.x, f.y)):
			out.append({"x": f.x, "y": f.y, "heading": f.heading, "alpha": alpha(age, f.heavy, art), "heavy": f.heavy})
	return out
