extends RefCounted
## Hit test for tapping a colonist (docs/specs/emotions.md 7.1 rule 1). Pure: it reads the view model's per-being records
## and the roof cuts, never the sim.


## The nearest colonist id within selection.tap_radius_px (screen px, so divided by the zoom) of the drawn position (feet
## raised by half the height), or 0. Records not visible are skipped; an inside record counts only when its building's roof
## cut is at least selection.open_cut_min. Ties go to the lowest id.
static func pick(world_pt: Vector2, records: Dictionary, cut_of: Callable, zoom: float, cfg: Dictionary) -> int:
	var radius := float(cfg.tap_radius_px) / zoom
	var open_min := float(cfg.open_cut_min)
	var best := 0
	var best_d := INF
	var ids: Array = records.keys()
	ids.sort()
	for id: int in ids:
		var r: Dictionary = records[id]
		if not bool(r.visible):
			continue
		if bool(r.inside) and float(cut_of.call(int(r.building_id))) < open_min:
			continue
		var centre: Vector2 = (r.pos as Vector2) - Vector2(0.0, float(r.height_px) * 0.5)
		var d := world_pt.distance_to(centre)
		if d <= radius and d < best_d:
			best = id
			best_d = d
	return best
