extends RefCounted
## Construction phases and the per-site draw list (spec sprite-view.md 5.5). Progress is shown by the building itself,
## never by a bar or a number.


## p: build progress after the slab starts; f: wall reveal; g: paint; sa: scaffold alpha. All 0..1 except p.
static func phases(built: float, art: Dictionary) -> Dictionary:
	var c: Dictionary = art.construction
	var p := maxf(0.0, (built - float(c.start_built)) / float(c.span_built))
	var f := clampf((p - float(c.wall.start_p)) / float(c.wall.span_p), 0.0, 1.0)
	var g := clampf((p - float(c.paint.start_p)) / float(c.paint.span_p), 0.0, 1.0)
	var fade_in := float(c.scaffold.fade_in_p)
	var fade_out := float(c.scaffold.fade_out_p)
	var sa := 1.0
	if p < fade_in:
		sa = p / fade_in
	elif p > fade_out:
		sa = maxf(0.0, (1.0 - p) / (1.0 - fade_out))
	return {"p": p, "f": f, "g": g, "sa": sa}


## Fraction of the tunnel length that is revealed (the owning building's built).
static func corridor_frac(built: float, art: Dictionary) -> float:
	return minf(1.0, built / float(art.construction.corridor_built_frac))


## Layers to draw for a site, in order, for the sprite rect. Empty when finished. gray and paint carry the unpadded clip
## top y (the view adds construction.clip_pad_px at draw time).
static func draw_list(built: float, rect: Rect2, art: Dictionary) -> Array:
	var out: Array = []
	if built >= 1.0:
		return out
	var ph := phases(built, art)
	out.append({"layer": "stakes"})
	out.append({"layer": "ghost"})
	out.append({"layer": "tunnel"})
	if float(ph.p) > 0.0:
		out.append({"layer": "slab"})
	if float(ph.f) > 0.0:
		out.append({"layer": "gray", "clip_top": rect.position.y + rect.size.y * (1.0 - float(ph.f))})
		if float(ph.g) > 0.0:
			out.append({"layer": "paint", "clip_top": rect.position.y + rect.size.y * (1.0 - float(ph.g))})
	if float(ph.sa) > 0.0:
		out.append({"layer": "scaffold"})
	return out
