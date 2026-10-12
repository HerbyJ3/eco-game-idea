extends RefCounted
## Task 6a view step: spec docs/specs/emotions.md section 13 test 32 (selection rules, hit test, follow, outline, tap from the
## log, the died beat). Moved out of tests/deferred/ at plan step 8 (view); the API names are the ones of spec 7.1 rule 1.

const BeingHit = preload("res://view/model/being_hit.gd")
const Selection = preload("res://view/model/selection.gd")
const ViewModel = preload("res://view/model/view_model.gd")


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _art() -> Dictionary:
	return SimData.load_json("art.json")


func _cfg() -> Dictionary:
	return SimData.load_json("mood.json").selection


func _rec(x: float, y: float, inside: bool, bid: int = 0, visible: bool = true) -> Dictionary:
	return {"pos": Vector2(x, y), "height_px": 20.0, "visible": visible, "inside": inside, "building_id": bid}


func _world_with_building() -> Variant:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("habitat", 40, 0)
	return w


func test_t32a_a_colonist_outside_wins_over_the_building_under_it(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var sel = Selection.new(_art())
	var b = w.buildings.get_building(1)
	var tile := float(SimData.buildings().tile_px)
	var foot := Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile)
	var c := foot.get_center()
	var recs := {7: _rec(c.x, c.y + 10.0, false)}
	sel.tap(c + Vector2(0, 0), w, recs, 1.0)
	t.eq(sel.selected_being, 7, "the colonist is selected")
	t.eq(sel.selected, 0, "and not the building under it")
	t.check(not sel.peek, "the roof is not toggled")
	t._failures.erase(_abort_msg(t))


func test_t32b_the_three_tap_path_at_zoom_1(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var sel = Selection.new(_art())
	var b = w.buildings.get_building(1)
	var tile := float(SimData.buildings().tile_px)
	var c := Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile).get_center()
	var recs := {7: _rec(c.x, c.y, true, 1)}
	sel.tap(c, w, recs, 1.0)
	t.eq(sel.selected, 1, "tap 1: the building is selected")
	t.eq(sel.selected_being, 0, "an inside colonist under a closed roof cannot be hit")
	sel.tap(c, w, recs, 1.0)
	t.check(sel.peek, "tap 2: the roof opens")
	sel.peek_cut = 1.0
	sel.tap(c, w, recs, 1.0)
	t.eq(sel.selected_being, 7, "tap 3: the colonist in the open interior is selected")
	t.eq(sel.selected, 1, "the building stays selected")
	t.check(sel.peek, "and its roof stays open under the player's finger")
	t._failures.erase(_abort_msg(t))


func test_t32c_all_roofs_cut_open_one_tap_selects_an_inside_colonist(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var sel = Selection.new(_art())
	var b = w.buildings.get_building(1)
	var tile := float(SimData.buildings().tile_px)
	var c := Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile).get_center()
	var recs := {7: _rec(c.x, c.y, true, 1)}
	# The tap is on the drawn position (feet raised by half the height): the radius shrinks with the zoom (18 px / 5.4).
	sel.tap(c - Vector2(0.0, 10.0), w, recs, 5.4)
	t.eq(sel.selected_being, 7, "at zoom 5.4 one tap selects the inside colonist")
	t._failures.erase(_abort_msg(t))


func test_t32d_hit_test_radius_nearest_and_ties(t) -> void:
	t._failures.append(_abort_msg(t))
	var c := _cfg()
	var r := float(c.tap_radius_px)
	var recs := {3: _rec(100.0, 100.0, false), 5: _rec(100.0 + 4.0, 100.0, false), 9: _rec(300.0, 300.0, false)}
	var cut_of := func(_b: int) -> float: return 0.0
	var pt := Vector2(100.0, 100.0 - 10.0)
	t.eq(BeingHit.pick(pt, recs, cut_of, 1.0, c), 3, "nearest wins")
	t.eq(BeingHit.pick(Vector2(102.0, 90.0), recs, cut_of, 1.0, c), 3, "a tie goes to the lowest id")
	t.eq(BeingHit.pick(Vector2(100.0 + r + 5.0, 90.0), {3: _rec(100.0, 100.0, false)}, cut_of, 1.0, c), 0, "outside tap_radius_px: nothing")
	t.eq(BeingHit.pick(Vector2(100.0 + r * 0.9, 90.0), {3: _rec(100.0, 100.0, false)}, cut_of, 4.0, c), 0, "the radius is divided by the zoom")
	t.eq(BeingHit.pick(pt, {3: _rec(100.0, 100.0, false, 0, false)}, cut_of, 1.0, c), 0, "an invisible record cannot be hit")
	var below := func(_b: int) -> float: return float(c.open_cut_min) - 0.01
	var above := func(_b: int) -> float: return float(c.open_cut_min)
	t.eq(BeingHit.pick(pt, {3: _rec(100.0, 100.0, true, 1)}, below, 1.0, c), 0, "inside a roof cut below open_cut_min: no hit")
	t.eq(BeingHit.pick(pt, {3: _rec(100.0, 100.0, true, 1)}, above, 1.0, c), 3, "at open_cut_min: hit")
	t._failures.erase(_abort_msg(t))


func test_t32e_closing_rules(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var sel = Selection.new(_art())
	var b = w.buildings.get_building(1)
	var tile := float(SimData.buildings().tile_px)
	var foot := Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile)
	var c := foot.get_center()
	var empty := foot.position - Vector2(50, 50)
	sel.selected_being = 7
	sel.tap(c, w, {}, 1.0)
	t.eq(sel.selected_being, 0, "a tap on a building while a colonist is selected closes the selection")
	t.eq(sel.selected, 0, "and is consumed: the building is not selected or toggled")
	sel.tap(c, w, {}, 1.0)
	t.eq(sel.selected, 1, "the next tap acts as normal")
	sel.selected_being = 7
	sel.tap(empty, w, {}, 1.0)
	t.eq(sel.selected_being, 0, "a tap on empty ground clears the colonist")
	sel.selected_being = 7
	sel.selected = 1
	sel.peek = true
	sel.deselect()
	t.check(sel.selected_being == 0 and sel.selected == 0 and not sel.peek, "deselect (Esc) clears the colonist, the building and peek")
	# Selecting a colonist outside any open roof clears a selected building.
	sel.selected = 1
	sel.tap(Vector2(500, 500), w, {7: _rec(500.0, 510.0, false)}, 1.0)
	t.eq(sel.selected_being, 7, "a colonist outside is selected")
	t.eq(sel.selected, 0, "and a selected building is cleared")
	t._failures.erase(_abort_msg(t))


func test_t32f_follow_the_selected_colonist(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/processed/manifest.json"))
	var out = w.add_being(1, "builder")
	out.state = "eva"
	out.x = 300.0
	out.y = 200.0
	out.heading = 0.0
	out.air_h = 30.0
	var inn = w.add_being(1, "builder")
	inn.state = "idle"
	var vm = ViewModel.new(w, _art(), man)
	vm.update(1.0 / 60.0)
	vm.selection.selected_being = out.id
	var rec = vm.being(out.id)
	t.check(vm.follow_target_for_selection().is_equal_approx(rec.pos), "an outside colonist: its drawn position")
	var b = w.buildings.get_building(1)
	vm.selection.selected_being = inn.id
	t.check(vm.follow_target_for_selection().is_equal_approx(vm.footprint_rect(b).get_center()),
			"a colonist inside a closed roof: the footprint centre of its building")
	vm.selection.selected_being = 0
	vm.selection.selected = 1
	t.check(vm.follow_target_for_selection().is_equal_approx(vm.footprint_rect(b).get_center()), "no colonist: the building as before")
	# tap_screen passes the records: a tap on the outside colonist selects it.
	vm.selection.deselect()
	var vp := Vector2(1280, 720)
	var scr: Vector2 = (rec.pos - Vector2(0.0, float(rec.height_px) * 0.5) - vm.camera.center) * vm.camera.zoom + vp * 0.5
	vm.tap_screen(scr, scr, vp)
	t.eq(vm.selection.selected_being, out.id, "tap_screen selects the colonist under the tap")
	t._failures.erase(_abort_msg(t))


func test_t32g_the_outline_is_built_from_the_sprite_alpha(t) -> void:
	t._failures.append(_abort_msg(t))
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(3, 6):
		for y in range(3, 6):
			img.set_pixel(x, y, Color(1, 1, 1, 1))
	var ring: Image = load("res://view/model/selection_outline.gd").ring(img, 1)
	t.check(ring.get_pixel(2, 4).a > 0.0 and ring.get_pixel(6, 4).a > 0.0, "a one-pixel ring appears beside the opaque block")
	t.check(ring.get_pixel(4, 4).a == 0.0, "and not on the sprite itself")
	t.check(ring.get_pixel(0, 0).a == 0.0, "nor far away")
	t._failures.erase(_abort_msg(t))


func test_t32h_a_log_line_maps_to_its_being_and_a_dead_being_opens_the_died_beat(t) -> void:
	t._failures.append(_abort_msg(t))
	var entries := [{"text": "a", "being_id": 4}, {"text": "b"}, {"text": "c", "being_id": 9}]
	var load_main = load("res://view/main.gd")
	t.check(load_main != null, "main.gd loads")
	var e = load_main.call("log_entry_at", 2.0 * 18.0 + 3.0, 18.0, entries, 3)
	t.check(e != null and int(e.being_id) == 9, "a tap on the third line of three reads its entry's being_id")
	var none = load_main.call("log_entry_at", 1.0 * 18.0 + 3.0, 18.0, entries, 3)
	t.check(none == null or not none.has("being_id"), "a line without a being_id is not a target")
	# A dead being: the panel text is its death record's name, "has died".
	var w = _world_with_building()
	var g = w.add_being(1, "builder")
	g.name = "Vana-3"
	w.beings.erase(g)
	w.stats.deaths_list.append({"t": 0.0, "sol": 0, "clock_sol": 0, "being_id": g.id, "name": "Vana-3", "cause": "age"})
	t.eq(load("res://view/model/being_panel.gd").died_line(w, g.id), "Vana-3 has died.", "a dead being opens straight to the died sentence")
	t._failures.erase(_abort_msg(t))


func _hud(w) -> Array:
	var sim: Node = load("res://view/sim_host.gd").new()
	sim.world = w
	var main: Control = (load("res://view/main.tscn") as PackedScene).instantiate()
	main.setup(sim)
	return [main, sim]


func test_t32i_the_panel_opens_holds_and_closes_through_the_hud(t) -> void:
	t._failures.append(_abort_msg(t))
	var w = _world_with_building()
	var g = w.add_being(1, "builder")
	g.name = "Vana-3"
	g.persona.description = "warm and nurturing"
	var hud := _hud(w)
	var main: Control = hud[0]
	main._process(0.016)
	t.eq(main.panel_text(), "", "closed with nothing selected")
	main._world.vm.selection.select_being(g.id)
	main._process(0.016)
	t.check(main.panel_text().begins_with("Vana-3 is warm and nurturing."), "opens with the who sentence (%s)" % main.panel_text())
	t.check(main.panel_text().find("knows no one well yet.") >= 0, "and the company sentence")
	# A band change shows only after the hold; the panel never refreshes faster than refresh_hz.
	g.mood_band = 0
	main._process(0.1)
	t.check(main.panel_text().find("struggling") < 0, "a pending band change waits for the hold")
	main._process(1.2)
	t.check(main.panel_text().find("is struggling.") >= 0, "and shows after it")
	# Death: the died beat for died_beat_s, then closed.
	w.beings.erase(g)
	w.stats.deaths_list.append({"t": 0.0, "sol": 0, "clock_sol": 0, "being_id": g.id, "name": "Vana-3", "cause": "age"})
	main._process(0.5)
	t.eq(main.panel_text(), "Vana-3 has died.", "the died beat")
	main._process(2.0)
	t.eq(main.panel_text(), "", "closes after the beat")
	t.eq(main._world.vm.selection.selected_being, 0, "and the selection is cleared")
	main.free()
	hud[1].free()
	t._failures.erase(_abort_msg(t))
