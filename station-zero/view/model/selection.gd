extends RefCounted
## Selection, peek and the roof cut (spec sprite-view.md 9). The view's only inputs are taps, never sim commands.

const BeingHit = preload("res://view/model/being_hit.gd")
const PanelText = preload("res://view/model/being_panel.gd")

var art: Dictionary
## Selected colonist id, 0 for none (docs/specs/emotions.md 7.1).
var selected_being := 0
## Selected building id, 0 for none.
var selected := 0
var peek := false
## Eased 0..1 roof cut of the selected building.
var peek_cut := 0.0


func _init(art_in: Dictionary) -> void:
	art = art_in


## A tap at a world point. A colonist hit (BeingHit.pick on the per-being records) wins over the building under it and does
## not toggle the roof; selecting a colonist clears a selected building unless the colonist is inside that building and its
## roof is open. With a colonist selected, any other tap only closes the colonist (consumed). Otherwise the building whose
## footprint holds the point is selected; tapping the selected building toggles peek (ignored on a site); tapping empty
## ground deselects.
func tap(world_pt: Vector2, world: SimWorld, records: Dictionary = {}, zoom: float = 1.0) -> void:
	var cut_of := func(building_id: int) -> float: return cut(building_id, zoom)
	var id := BeingHit.pick(world_pt, records, cut_of, zoom, PanelText.selection_cfg())
	if id != 0:
		var r: Dictionary = records[id]
		var keep: bool = bool(r.inside) and int(r.building_id) == selected and peek
		selected_being = id
		if not keep:
			selected = 0
			peek = false
		return
	if selected_being != 0:
		selected_being = 0
		return
	var tile := float(SimData.buildings().tile_px)
	var hit: Buildings.Building = null
	for b in world.buildings.list:
		if Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile).has_point(world_pt):
			hit = b
			break
	if hit == null:
		selected = 0
		peek = false
	elif hit.id == selected:
		peek = (not peek) and hit.finished()
	else:
		selected = hit.id
		peek = false


## Press and release closer than camera.drag_threshold_px (screen px) is a tap.
func is_tap(press: Vector2, release: Vector2) -> bool:
	return press.distance_to(release) < float(art.camera.drag_threshold_px)


func deselect() -> void:
	selected_being = 0
	selected = 0
	peek = false


## Eases peek_cut linearly over selection.roof_fade_s; a selected site never opens. Selection itself persists.
func update(dt_real: float, _zoom: float, world: SimWorld) -> void:
	var b := world.buildings.get_building(selected) if selected != 0 else null
	var open := peek and b != null and b.finished()
	peek_cut = move_toward(peek_cut, 1.0 if open else 0.0, dt_real / float(art.selection.roof_fade_s))


## Roof cut of a building: the zoom cut for every building, or the peek cut for the selected one, whichever is larger.
func cut(building_id: int, zoom: float) -> float:
	return maxf(zoom_cut(zoom, art), peek_cut if building_id == selected else 0.0)


static func zoom_cut(zoom: float, art: Dictionary) -> float:
	var s: Dictionary = art.selection
	return clampf((zoom - float(s.zoom_cut_start)) / float(s.zoom_cut_span), 0.0, 1.0)


## Which outline mask hugs the building at this cut.
static func outline_source(cut_value: float, art: Dictionary) -> String:
	return "exterior" if cut_value < float(art.selection.silhouette_cut_below) else "interior"


static func pulse(real_time: float, art: Dictionary) -> float:
	var s: Dictionary = art.selection
	return float(s.pulse_base) + float(s.pulse_amp) * sin(real_time * float(s.pulse_rate_rad_s))



## Selects a colonist without a tap (from a log line): the building selection and its roof are closed, one panel only.
func select_being(id: int) -> void:
	selected_being = id
	selected = 0
	peek = false
