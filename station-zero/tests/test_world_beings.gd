extends RefCounted
## Task 2, steps 14 to 16: colonists, footprints and terrain decals, selection and roof-open interiors in the sprite
## world view. Spec: docs/specs/sprite-view.md sections 4.4, 5.7, 5.8, 6, 7, 9, 10. Like test_world_view, the layers are
## drawn into a recorder so every draw command (and the texture log of the context) is inspected without a renderer.

const WV = preload("res://tests/test_world_view.gd")
const BeingDraw = preload("res://view/world/being_draw.gd")
const SelectionDraw = preload("res://view/world/selection_draw.gd")
const Footprints = preload("res://view/model/footprints.gd")
const DT := 1.0 / 60.0

var _wv := WV.new()


## A showcase world at the given hour.
func _world(hour: float = 12.0) -> SimWorld:
	var w: SimWorld = _wv._showcase()
	_wv._set_hour(w, hour)
	return w


func _eva(w: SimWorld, role: String, x: float, y: float, earth_born: bool = true, state: String = "eva") -> Being:
	var g := w.add_being(w.buildings.list[0].id, role)
	g.earth_born = earth_born
	g.state = state
	g.x = x
	g.y = y
	g.heading = 0.0
	g.air_h = 4.0
	return g


func _inside(w: SimWorld, kind: String, role: String, state: String = "idle", born: bool = true) -> Being:
	for b in w.buildings.list:
		if b.kind == kind:
			var g := w.add_being(b.id, role)
			g.earth_born = born
			g.state = state
			return g
	return null


func _building(w: SimWorld, kind: String) -> Buildings.Building:
	for b in w.buildings.list:
		if b.kind == kind:
			return b
	return null


## Draws one layer with the texture log on; returns {cmds, log}.
func _layer(view: Node2D, id: String) -> Dictionary:
	view.ctx.record = true
	view.ctx.log.clear()
	var rec := WV.Recorder.new()
	view.draw_layer(rec, id)
	return {"cmds": rec.cmds, "log": view.ctx.log.duplicate(), "rec": rec}


func _sprites(log: Array) -> Array:
	var out: Array = []
	for e in log:
		if String(e.id).begins_with("character."):
			out.append(e)
	return out


func _open_roof(view: Node2D, b: Buildings.Building) -> void:
	view.vm.selection.selected = b.id
	view.vm.selection.peek = true
	for i in 30:
		view._process(DT)


# ---------------------------------------------------------------- beings: where and which atlas

func test_beings_drawn_only_outside_or_in_an_open_roof(t) -> void:
	var w := _world()
	var out := _eva(w, "builder", 100.0, 108.0)
	var hab_g := _inside(w, "habitat", "social")
	var tunnel_g := _inside(w, "comms", "tender")
	tunnel_g.state = "transit"
	var green := _building(w, "green_room")
	green.corridor = {"parent_id": w.buildings.list[0].id, "p1": Vector2(48, 80), "p2": Vector2(48, 144), "len": 64.0,
			"rect": Rect2i(5, 10, 2, 8)}
	tunnel_g.corridor_id = green.id
	tunnel_g.from_a = true
	tunnel_g.transit_t = 0.5
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(2.0, Vector2(100, 100))
	_wv._frames(view, 5)
	var ent := _sprites(_layer(view, "entities").log)
	var tra := _sprites(_layer(view, "transit").log)
	t.eq(ent.size(), 1, "closed roof: one sprite in the entity layer (the outside being)")
	t.eq(String(ent[0].id), "character.eva", "an EVA being uses the eva atlas")
	t.eq(tra.size(), 1, "one tunnel being in the transit layer")
	t.eq(String(tra[0].id), "character.jumpsuit.tender", "tunnel beings wear the role jumpsuit")
	t.near((tra[0].feet as Vector2).x, 48.0, 0.01, "the tunnel being is on the tunnel line")
	t.check(view.vm.being(hab_g.id).visible == false, "a being inside a closed building is not placed")
	# Open the habitat roof: its interior being appears, above the interior art.
	_open_roof(view, _building(w, "habitat"))
	view.set_camera(4.0, Vector2(212, 36))
	_wv._frames(view, 5)
	var layer := _layer(view, "entities")
	var ids: Array = []
	for e in layer.log:
		ids.append(String(e.id))
	var interior_at := ids.find("building.habitat.interior")
	t.check(interior_at >= 0, "the open roof draws the interior art")
	var jump := ids.find("character.jumpsuit.social")
	t.check(jump > interior_at, "the interior being is drawn after (above) the interior art")
	_wv._free(pair)


func test_frame_rects_come_from_the_right_atlas_per_suit_and_role(t) -> void:
	var w := _world()
	var eva := _eva(w, "curious", 90.0, 108.0)
	var weld := _eva(w, "builder", 110.0, 108.0, true, "work")
	weld.construction_suit = true
	weld.wait_h = 1.0
	var carry := _eva(w, "tender", 130.0, 108.0)
	carry.load = 1.0
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(110, 108))
	_wv._frames(view, 5)
	var by_x := {}
	for e in _sprites(_layer(view, "entities").log):
		by_x[roundi((e.feet as Vector2).x)] = e
	var lib: ArtLibrary = view.lib
	t.eq(String(by_x[90].id), "character.eva", "EVA suit atlas")
	t.eq(String(by_x[110].id), "character.construction", "a builder in a construction suit uses the construction atlas")
	t.eq(String(by_x[130].id), "character.eva", "the carrier is in an EVA suit")
	t.eq(by_x[90].src, lib.frame_rect("eva", "idle_front"), "an idle EVA being shows the idle_front cell of the eva sheet")
	t.eq(by_x[130].src, lib.frame_rect("eva", "carry"), "a loaded EVA being shows the carry cell")
	var weld_src: Rect2 = by_x[110].src
	t.check(weld_src == lib.frame_rect("construction", "weld_1") or weld_src == lib.frame_rect("construction", "weld_2"),
			"a welding builder shows a weld frame of the construction sheet")
	for k in by_x:
		var cell := float(lib.sheet("eva").cell_px)
		t.eq((by_x[k].src as Rect2).size, Vector2(cell, cell), "frame source is one atlas cell")
	# Jumpsuit atlases are per role.
	for role in ["builder", "curious", "social", "tender"]:
		var w2 := _world()
		var g := _inside(w2, "habitat", role)
		g.state = "transit"
		var gr := _building(w2, "green_room")
		gr.corridor = {"parent_id": w2.buildings.list[0].id, "p1": Vector2(48, 80), "p2": Vector2(48, 144), "len": 64.0,
				"rect": Rect2i(5, 10, 2, 8)}
		g.corridor_id = gr.id
		g.transit_t = 0.4
		g.from_a = true
		var p2 := _wv._make(w2)
		_wv._frames(p2[1], 3)
		var sp := _sprites(_layer(p2[1], "transit").log)
		t.eq(String(sp[0].id), "character.jumpsuit." + role, "role %s picks its recolored jumpsuit atlas" % role)
		_wv._free(p2)
	_wv._free(pair)


func test_mars_born_scale_and_feet_on_the_position(t) -> void:
	var w := _world()
	var a := _eva(w, "builder", 100.0, 108.0, true)
	var b := _eva(w, "builder", 120.0, 108.0, false)
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(6.0, Vector2(110, 108))
	_wv._frames(view, 5)
	var sp := _sprites(_layer(view, "entities").log)
	var earth: Dictionary = sp[0] if roundi(sp[0].feet.x) == 100 else sp[1]
	var mars: Dictionary = sp[1] if roundi(sp[0].feet.x) == 100 else sp[0]
	var art: Dictionary = view.art
	t.near((mars.rect as Rect2).size.x / (earth.rect as Rect2).size.x, float(art.colonist.mars_born_scale), 1e-4,
			"a Mars-born being is drawn 1.1x")
	var cell := float(view.lib.sheet("eva").cell_px)
	var s := float(art.colonist.height_px) / float(art.pipeline.character_height_in_cell_px)
	t.near((earth.rect as Rect2).size.x, cell * s, 1e-4, "Earth-born scale is height_px over the character height in the cell")
	# The pivot (feet) stays on the position: the dest rect's pivot point is the origin, the draw origin is the position.
	var pivot := Vector2(float(view.lib.sheet("eva").pivot_px[0]), float(view.lib.sheet("eva").pivot_px[1]))
	t.near(-(mars.rect as Rect2).position.x, pivot.x * s * float(art.colonist.mars_born_scale), 1e-3, "the pivot scales with the sprite")
	t.near((earth.feet as Vector2).x, 100.0, 0.01, "feet x on the sim position")
	t.near((mars.feet as Vector2).x, 120.0, 0.01, "Mars-born feet x on the sim position")
	t.check(absf((mars.feet as Vector2).y - 108.0) < float(art.walk.bob_walk_px) + 0.01, "feet y on the sim position (within the bob)")
	t.eq(a.earth_born != b.earth_born, true, "the pair differs only in birth")
	_wv._free(pair)


func test_walking_being_mirrors_and_faces(t) -> void:
	var w := _world()
	var g := _eva(w, "builder", 100.0, 108.0)
	g.heading = PI
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(6.0, Vector2(100, 108))
	_wv._frames(view, 3)
	# Walk left at 20 px/s of real time.
	for i in 30:
		g.x = float(g.x) - 0.5
		view._process(DT)
	var sp := _sprites(_layer(view, "entities").log)
	t.eq(sp.size(), 1, "one walker")
	t.eq(bool(sp[0].mirror), true, "a being walking left is mirrored")
	var pose: Dictionary = view.vm.being(g.id).pose
	t.check(String(pose.frame).begins_with("walk_side_"), "walking sideways uses a walk_side frame (%s)" % pose.frame)
	_wv._free(pair)


# ---------------------------------------------------------------- lamps

func test_helmet_lamp_follows_the_schedule_and_sits_on_the_anchor(t) -> void:
	var levels := {}
	for hour in [12.0, 19.5, 23.0]:
		var w := _world(hour)
		var g := _eva(w, "builder", 100.0, 108.0)
		var pair := _wv._make(w)
		var view: Node2D = pair[1]
		view.set_camera(6.0, Vector2(100, 108))
		view.settle_view(2.0)
		var rec: Dictionary = view.vm.being(g.id)
		levels[hour] = float(rec.lamp_level)
		var lights := _layer(view, "lights")
		var discs := 0
		for c in lights.cmds:
			if c.cmd == "tex" and c.tex == view.ctx.glow:
				discs += 1
		if hour == 12.0:
			t.eq(rec.lamp_level, 0.0, "no lamp by day")
			t.eq(BeingDraw.lamp_params(view.ctx, g.id, rec).is_empty(), true, "no lamp parameters by day")
		else:
			var l := BeingDraw.lamp_params(view.ctx, g.id, rec)
			var p := BeingDraw.sprite_params(view.ctx, g.id, rec)
			var a: Vector2 = view.lib.lamp_anchor("eva", rec.pose.frame)
			var pivot := Vector2(float(view.lib.sheet("eva").pivot_px[0]), float(view.lib.sheet("eva").pivot_px[1]))
			var want: Vector2 = (p.feet as Vector2) + (a - pivot) * float(p.scale) * (Vector2(-1, 1) if p.mirror else Vector2.ONE)
			t.near((l.anchor as Vector2).x, want.x, 1e-4, "hour %.1f: the lamp glow is at the frame's lamp anchor (x)" % hour)
			t.near((l.anchor as Vector2).y, want.y, 1e-4, "hour %.1f: the lamp glow is at the frame's lamp anchor (y)" % hour)
			t.check(want.y < (rec.pos as Vector2).y - float(view.art.colonist.height_px) * 0.5, "the lamp is up on the helmet")
			t.check(discs >= 3, "hour %.1f: outer disc, core and ground pool are drawn (%d)" % [hour, discs])
		_wv._free(pair)
	t.check(levels[19.5] > 0.0 and levels[19.5] < levels[23.0], "the lamp is dimmer at 19:30 (%.2f) than at 23:00 (%.2f)" % [levels[19.5], levels[23.0]])
	t.near(levels[23.0], 1.0, 0.01, "full lamp at night")


func test_lamp_is_off_inside_and_for_jumpsuits(t) -> void:
	var w := _world(23.0)
	var g := _inside(w, "habitat", "builder")
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.settle_view(1.0)
	t.eq(float(view.vm.being(g.id).lamp_level), 0.0, "no lamp inside")
	t.eq(_layer(view, "lights").log.filter(func(e): return String(e.id).begins_with("character.")).size(), 0, "no being sprite on the additive layer")
	_wv._free(pair)


# ---------------------------------------------------------------- footprints and terrain

func test_footprint_batch_count_equals_the_model(t) -> void:
	var w := SimWorld.new(42)
	for i in 1480:
		w.step()
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(0.6, Vector2(100, 100))
	_wv._frames(view, 3)
	var prints := w.resources.footprints.size()
	t.check(prints >= 20, "the run left prints (%d)" % prints)
	var layer := _layer(view, "footprints")
	var prims := 0
	var texes := {}
	for c in layer.cmds:
		if c.cmd == "prim":
			prims += 1
			texes[c.tex] = true
			t.eq((c.points as PackedVector2Array).size(), 4, "one quad per print")
	var want := Footprints.drawn(w, view.ctx.view_rect.grow(maxf(float(view.art.footprint.rx_px), float(view.art.footprint.ry_px))), view.art)
	t.eq(prims, want.size(), "quads drawn equal the model's drawn prints in the camera")
	t.check(prims > 0, "some prints are in view")
	t.eq(texes.size(), 1, "every print shares one baked texture (one batch)")
	t.eq(layer.cmds.size(), prims, "nothing but quads in the layer")
	# Alpha follows heavy and age.
	var alphas := {}
	for i in want.size():
		alphas[snappedf(float(want[i].alpha), 0.0001)] = true
	var k := 0
	for c in layer.cmds:
		t.near((c.colors as PackedColorArray)[0].a, float(want[k].alpha), 1e-5, "print %d alpha from the model" % k)
		k += 1
		if k > 40:
			break
	# A being far from the view contributes nothing: look away.
	view.set_camera(6.0, Vector2(5000, 5000))
	_wv._frames(view, 2)
	var far := 0
	for c in _layer(view, "footprints").cmds:
		far += 1 if c.cmd == "prim" else 0
	t.eq(far, 0, "no quads far from every print")
	_wv._free(pair)


func test_baked_footprint_has_ellipse_and_heel(t) -> void:
	var art: Dictionary = SimData.load_json("art.json")
	var img := load("res://view/world/footprint_draw.gd").bake(art) as Image
	var w := img.get_width()
	var h := img.get_height()
	t.check(w > h, "the print is wider than tall (rx > ry)")
	t.eq(img.get_pixel(w / 2, h / 2).a > 0.99, true, "the centre is solid")
	t.eq(img.get_pixel(0, 0).a, 0.0, "the corner is clear")
	var heel := img.get_pixel(int(w * (0.5 + 0.55 / (2.0 * float(art.footprint.rx_px)))), h / 2)
	var body := img.get_pixel(w / 2, h / 2)
	t.check(heel.r > body.r, "the heel is lighter than the body")


class NoDecalLib extends ArtLibrary:
	## The real manifest now carries the terrain decals; these tests are about the procedural fallback, so the decals are hidden.
	func has_art(id: String) -> bool:
		return false if id.begins_with("terrain.decal.") else super.has_art(id)

	func texture(id: String) -> Texture2D:
		return null if id.begins_with("terrain.decal.") else super.texture(id)


class FakeLib extends ArtLibrary:
	var tex_obj: ImageTexture
	func _init() -> void:
		var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		tex_obj = ImageTexture.create_from_image(img)

	func has_art(id: String) -> bool:
		return id.begins_with("terrain.decal.") or super.has_art(id)

	func texture(id: String) -> Texture2D:
		return tex_obj if id.begins_with("terrain.decal.") else super.texture(id)


func test_terrain_decals_when_present_else_procedural_without_rocks(t) -> void:
	var w := SimWorld.new(42, {"blank": true})
	w.resources.add_ice_field(60.0, 60.0, 100.0, 12.0)
	w.resources.add_pit(200.0, 80.0)
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(1.0, Vector2(130, 70))
	view.lib = NoDecalLib.new()
	view.lib.load_manifest()
	view.ctx.lib = view.lib
	_wv._frames(view, 3)
	var plain := _layer(view, "terrain")
	var decals := 0
	for e in plain.log:
		decals += 1 if String(e.id).begins_with("terrain.decal.") else 0
	t.eq(decals, 0, "no decal in the manifest: nothing textured, no rocks or craters")
	t.check(plain.rec.count("circle") > 0 or plain.rec.count("poly") > 0, "the procedural ice and pit are drawn instead")
	var rect_cmds: int = plain.rec.count("rect")
	# Now with decals.
	view.lib = FakeLib.new()
	view.lib.load_manifest()
	view.ctx.lib = view.lib
	var with := _layer(view, "terrain")
	var kinds := {}
	for e in with.log:
		kinds[String(e.id)] = int(kinds.get(String(e.id), 0)) + 1
	t.eq(int(kinds.get("terrain.decal.ice", 0)), 1, "one ice decal per field")
	t.eq(int(kinds.get("terrain.decal.pit", 0)), 1, "one pit decal per pit")
	t.check(int(kinds.get("terrain.decal.rocks", 0)) > 0, "rocks are scattered when the decals exist (%s)" % str(kinds))
	t.check(with.rec.count("rect") < rect_cmds, "the pit's procedural rim, hole and stripes are replaced by the decal")
	# Same scatter again: stable.
	var again := _layer(view, "terrain")
	t.eq(again.log.size(), with.log.size(), "the scatter is stable across frames")
	var ice: Dictionary = {}
	for e in with.log:
		if e.id == "terrain.decal.ice":
			ice = e
	t.near((ice.rect as Rect2).size.x, float(view.art.optional.decals.ice_width_over_r) * 12.0, 1e-4, "ice decal width is 2.6 r")
	_wv._free(pair)


# ---------------------------------------------------------------- selection

func test_selection_outline_only_when_selected_and_never_a_rect(t) -> void:
	var w := _world()
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(212, 36))
	_wv._frames(view, 3)
	t.eq(_layer(view, "selection").cmds.size(), 0, "nothing selected: no outline commands")
	var hab := _building(w, "habitat")
	view.vm.selection.selected = hab.id
	_wv._frames(view, 3)
	var layer := _layer(view, "selection")
	t.check(layer.cmds.size() >= 2, "selected: the outline and its halo are drawn (%d)" % layer.cmds.size())
	for c in layer.cmds:
		t.eq(c.cmd, "tex", "the outline is a texture, never a plain rect or line")
	var ring: Dictionary = layer.log[layer.log.size() - 1]
	var halo: Dictionary = layer.log[0]
	t.check(String(ring.id).begins_with("outline.building.habitat"), "outline built from the habitat sprite (%s)" % ring.id)
	t.near(float(halo.alpha) / float(ring.alpha), float(view.art.selection.halo_alpha), 1e-4, "the halo is 0.3 of the pulse")
	var pulse: float = load("res://view/model/selection.gd").pulse(view.vm.real_time, view.art)
	t.near(float(ring.alpha), pulse, 1e-5, "the outline alpha is the model's pulse")
	t.check((halo.rect as Rect2).size.x > (ring.rect as Rect2).size.x, "the halo is wider than the ring")
	var ext: Rect2 = view.vm.sprite_rect(hab)
	t.check((ring.rect as Rect2).encloses(ext), "the ring surrounds the sprite rect")
	# The outline pulses over time.
	var a1: float = ring.alpha
	view.vm.update(0.3)
	view._update_frame(0.0)
	var again := _layer(view, "selection")
	t.check(not is_equal_approx(float(again.log[again.log.size() - 1].alpha), a1), "the pulse moves with time")
	# Tapping empty ground deselects; the next frames draw nothing.
	view.vm.selection.deselect()
	_wv._frames(view, 2)
	t.eq(_layer(view, "selection").cmds.size(), 0, "deselected: no outline")
	_wv._free(pair)


func test_outline_ring_hugs_the_silhouette(t) -> void:
	# A disc: the ring is a band around it, with clear corners (a box outline would fill them).
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			if Vector2(x - 31.5, y - 31.5).length() <= 20.0:
				img.set_pixel(x, y, Color.WHITE)
	var radius := 4
	var ring := SelectionDraw.build_ring(img, radius, 100, Color.WHITE)
	t.eq(ring.get_width(), 64 + radius * 2, "the canvas grows by the radius on every side")
	t.eq(ring.get_pixel(0, 0).a, 0.0, "the corner is clear")
	t.eq(ring.get_pixel(ring.get_width() - 1, ring.get_height() - 1).a, 0.0, "the opposite corner is clear")
	var inside_hits := 0
	var band := 0
	var far := 0
	for y in ring.get_height():
		for x in ring.get_width():
			if ring.get_pixel(x, y).a <= 0.0:
				continue
			band += 1
			var d := Vector2(x - radius - 31.5, y - radius - 31.5).length()
			if d <= 20.0:
				inside_hits += 1
			if d > 20.0 + float(radius) + 1.5:
				far += 1
	t.eq(inside_hits, 0, "no ring pixel inside the silhouette")
	t.eq(far, 0, "no ring pixel farther than the radius from it")
	t.check(band > 100, "the ring has body (%d px)" % band)
	var box := (64 + radius * 2) * (64 + radius * 2)
	t.check(band < box / 3, "the ring is a thin band, not a filled rectangle (%d of %d)" % [band, box])


func test_outline_of_a_real_building_has_clear_corners(t) -> void:
	var w := _world()
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	_wv._frames(view, 2)
	var sel: SelectionDraw = SelectionDraw.new()
	for kind in ["reactor", "habitat", "workshop", "green_room"]:
		var r := sel.ring_for(view.ctx, "building.%s.base" % kind)
		t.check(not r.is_empty(), "%s: a ring is built from the sprite alpha" % kind)
		var img: Image = (r.tex as ImageTexture).get_image()
		t.eq(img.get_pixel(0, 0).a, 0.0, "%s: ring corner is clear" % kind)
		t.eq(img.get_pixel(img.get_width() - 1, 0).a, 0.0, "%s: ring top-right corner is clear" % kind)
		var solid := 0
		for y in range(0, img.get_height(), 3):
			for x in range(0, img.get_width(), 3):
				solid += 1 if img.get_pixel(x, y).a > 0.0 else 0
		var sampled := (img.get_width() / 3 + 1) * (img.get_height() / 3 + 1)
		t.check(solid < sampled / 3, "%s: the ring covers a small share of its canvas, not a box (%d of %d)" % [kind, solid, sampled])
	_wv._free(pair)


func test_outline_follows_the_roof_open_interior(t) -> void:
	var w := _world()
	_inside(w, "habitat", "social")
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(212, 36))
	var hab := _building(w, "habitat")
	view.vm.selection.selected = hab.id
	_wv._frames(view, 3)
	var closed := _layer(view, "selection")
	t.check(String(closed.log[closed.log.size() - 1].id).ends_with("habitat.base"), "closed roof: the exterior silhouette")
	_open_roof(view, hab)
	var open := _layer(view, "selection")
	t.check(String(open.log[open.log.size() - 1].id).ends_with("habitat.interior"), "open roof: the interior silhouette")
	_wv._free(pair)


# ---------------------------------------------------------------- roof and interiors

func test_roof_returns_at_lower_zoom_and_peek_fades(t) -> void:
	var w := _world()
	_inside(w, "habitat", "social")
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	var hab := _building(w, "habitat")
	view.set_camera(3.0, Vector2(212, 36))
	_wv._frames(view, 3)
	var l1 := _layer(view, "entities")
	var ids1: Array = l1.log.map(func(e): return String(e.id))
	t.check(ids1.has("building.habitat.base") and not ids1.has("building.habitat.interior"), "zoom 3: roof on, no interior")
	view.set_camera(6.0, Vector2(212, 36))
	_wv._frames(view, 3)
	var l2 := _layer(view, "entities")
	var base_alpha := -1.0
	var int_alpha := -1.0
	for e in l2.log:
		if e.id == "building.habitat.base":
			base_alpha = e.alpha
		if e.id == "building.habitat.interior":
			int_alpha = e.alpha
	t.check(int_alpha > 0.99, "zoom 6: the interior is fully shown")
	t.check(base_alpha <= 0.001 or base_alpha == -1.0, "zoom 6: the exterior is gone")
	view.set_camera(3.0, Vector2(212, 36))
	_wv._frames(view, 3)
	var l3 := _layer(view, "entities")
	var ids3: Array = l3.log.map(func(e): return String(e.id))
	t.check(ids3.has("building.habitat.base") and not ids3.has("building.habitat.interior"), "back at zoom 3: the roof returns")
	# Peek fades over roof_fade_s: halfway the cut is in between.
	view.vm.selection.selected = hab.id
	view.vm.selection.peek = true
	view.vm.update(float(view.art.selection.roof_fade_s) * 0.5)
	view._update_frame(0.0)
	var mid := _layer(view, "entities")
	var half_i := -1.0
	var half_b := -1.0
	for e in mid.log:
		if e.id == "building.habitat.interior":
			half_i = e.alpha
		if e.id == "building.habitat.base":
			half_b = e.alpha
	t.near(half_i, 0.5, 0.05, "halfway through the peek fade the interior is at half alpha")
	t.near(half_b, 0.5, 0.05, "and the exterior at half alpha")
	_wv._free(pair)


## A habitat with three awake and three sleeping beings, roof open. hide_sleeping: the manifest the view reads has the
## 16 sleeping poses hidden (file null, placeholder), which gives the rotated jumpsuit fallback.
func _sleepers_scene(hide_sleeping: bool) -> Array:
	var w := _world()
	for role in ["builder", "curious", "social"]:
		_inside(w, "habitat", role)
	for role in ["tender", "builder", "curious"]:
		_inside(w, "habitat", role, "sleep")
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	if hide_sleeping:
		var m: Dictionary = view.vm.man.duplicate(true)
		for id in m.entries:
			if String(id).begins_with("character.sleeping."):
				m.entries[id]["placeholder"] = true
				m.entries[id]["file"] = null
		view.vm.man = m
		view.ctx.man = m
	view.set_camera(4.0, Vector2(212, 36))
	var hab := _building(w, "habitat")
	_open_roof(view, hab)
	view.settle_view(1.0)
	return [w, pair, hab]


func test_interior_beings_scale_count_and_poses(t) -> void:
	# Fallback path: sleeping poses hidden, sleepers are the rotated jumpsuit.
	var sc := _sleepers_scene(true)
	var w: SimWorld = sc[0]
	var pair: Array = sc[1]
	var hab: Buildings.Building = sc[2]
	var view: Node2D = pair[1]
	var sp := _sprites(_layer(view, "entities").log)
	t.eq(sp.size(), 6, "six interior beings drawn")
	var art: Dictionary = view.art
	var s := float(art.colonist.height_px) * float(art.colonist.interior_scale) / float(art.pipeline.character_height_in_cell_px)
	var cell := float(view.lib.sheet("jumpsuit").cell_px)
	var sleepers := 0
	var rect: Rect2 = view.vm.interior_rect(hab.id)
	for e in sp:
		t.near((e.rect as Rect2).size.x, cell * s, 1e-3, "interior beings are drawn at 1.9x")
		t.eq(String(e.id).begins_with("character.jumpsuit."), true, "interior beings wear the jumpsuit")
		t.check(rect.grow(1.0).has_point(e.feet), "feet inside the interior rect")
		if absf(float(e.rot)) > 0.1:
			sleepers += 1
	t.eq(sleepers, 3, "three sleepers lie down (rotated sleeping fallback)")
	_check_bunks_and_frames(t, view, hab)
	# At most 25 per building.
	for i in 30:
		_inside(w, "habitat", "builder")
	_wv._frames(view, 5)
	var many := _sprites(_layer(view, "entities").log)
	t.eq(many.size(), int(art.interior.being_cap), "no more than %d interior beings per building" % int(art.interior.being_cap))
	_wv._free(pair)


func test_interior_real_sleeping_poses(t) -> void:
	# Real path: the shipped manifest carries the sleeping poses.
	var sc := _sleepers_scene(false)
	var pair: Array = sc[1]
	var hab: Buildings.Building = sc[2]
	var view: Node2D = pair[1]
	var art: Dictionary = view.art
	var sp := _sprites(_layer(view, "entities").log)
	t.eq(sp.size(), 6, "six interior beings drawn")
	var s := float(art.colonist.height_px) * float(art.colonist.interior_scale) / float(art.pipeline.character_height_in_cell_px)
	var cell := float(view.lib.sheet("jumpsuit").cell_px)
	var js_scale := float(view.lib.sheet("jumpsuit").scale)
	var rect: Rect2 = view.vm.interior_rect(hab.id)
	var model = view.vm.interior(hab.id)
	var sleepers := 0
	for e in sp:
		var id := String(e.id)
		t.check(rect.grow(1.0).has_point(e.feet), "feet inside the interior rect")
		if id.begins_with("character.sleeping."):
			sleepers += 1
			var parts := id.split(".")
			t.check(int(parts[3]) >= 0 and int(parts[3]) <= 3, "%s: pose number within 0..3" % id)
			var ent: Dictionary = view.lib.entry(id)
			var want := float(ent.w) * s * float(ent.scale) / js_scale
			t.near((e.rect as Rect2).size.x, want, 1e-3, "%s drawn at the manifest sleeping scale times 1.9" % id)
			t.check((e.rect as Rect2).size.x < float(ent.w) * s, "a shrunk pose is drawn smaller than at the jumpsuit scale")
			t.near(absf(float(e.rot)), 0.0, 1e-6, "a real sleeper is not rotated")
		else:
			t.near((e.rect as Rect2).size.x, cell * s, 1e-3, "awake interior beings stay at 1.9x of the jumpsuit cell")
			t.eq(id.begins_with("character.jumpsuit."), true, "awake beings wear the jumpsuit")
	t.eq(sleepers, 3, "three sleepers use the sleeping sheet")
	# Each sleeper is drawn on its slot (the centred image is anchored at the slot, no offset, no bob), and the pose is
	# stable per being id.
	for id in model.drawn_ids():
		var rec: Dictionary = view.vm.being(id)
		if String(rec.pose.sheet).begins_with("character.sleeping."):
			var p: Dictionary = BeingDraw.sprite_params(view.ctx, id, rec)
			t.eq(p.feet, rec.pos, "sleeper %d is drawn at its slot" % id)
			t.check(String(rec.pose.sheet).ends_with(".%d" % (id % 4)), "pose number is the being id mod 4")
			t.eq(model.slot_of(id).get("type", ""), "bunk", "sleeper %d lies on a bunk" % id)
	_wv._free(pair)


func _check_bunks_and_frames(t, view: Node2D, hab: Buildings.Building) -> void:
	# Sleepers rest on bunks: the interior model assigns bunk slots in id order.
	var model = view.vm.interior(hab.id)
	var bunks := 0
	for id in model.drawn_ids():
		if model.slot_of(id).get("type", "") == "bunk":
			bunks += 1
	t.eq(bunks, 3, "all three sleepers hold bunk slots")
	# The talk pose exists for jumpsuit beings pausing near each other (cosmetic): frames are valid cells.
	for id in model.drawn_ids():
		var pose: Dictionary = view.vm.being(id).pose
		t.check(view.lib.frame_rect("jumpsuit", pose.frame).size != Vector2.ZERO or String(pose.sheet).begins_with("character.sleeping"),
				"pose frame %s exists on the sheet" % pose.frame)


func test_outside_beings_sorted_with_buildings_by_y(t) -> void:
	var w := _world()
	var hab := _building(w, "habitat")
	var tile := float(SimData.buildings().tile_px)
	var base_y := float(hab.ty + hab.th) * tile
	var door_x := float(hab.tx + hab.tw / 2.0) * tile
	var north := _eva(w, "builder", door_x + 20.0, base_y - 1.0)
	var south := _eva(w, "builder", door_x - 20.0, base_y + 1.0)
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(door_x, base_y))
	_wv._frames(view, 3)
	var order: Array = []
	for e in _layer(view, "entities").log:
		var id := String(e.id)
		if id == "building.habitat.base":
			order.append("habitat")
		elif id.begins_with("character."):
			order.append("north" if (e.feet as Vector2).x > door_x else "south")
	t.check(order.find("north") < order.find("habitat"), "a being 1 px north of the bottom edge is drawn behind the building")
	t.check(order.find("south") > order.find("habitat"), "a being south of the bottom edge is drawn in front")
	t.eq(north.state, "eva", "setup")
	t.eq(south.state, "eva", "setup")
	_wv._free(pair)


# ---------------------------------------------------------------- never writes, cost

func test_full_view_leaves_the_seed_7_sim_hash_unchanged(t) -> void:
	# Beings, tunnels, footprints, selection and an open roof all drawn through two sols of seed 7.
	var plain := SimWorld.new(7)
	var seen := SimWorld.new(7)
	var pair := _wv._make(seen)
	var view: Node2D = pair[1]
	var steps := int(2.0 * plain.clock.sol_h / plain.fixed_step)
	for i in steps:
		plain.step()
		seen.step()
		if i % 3 == 0:
			view._process(DT)
		if i == steps / 2:
			view.apply_shot_view({"select": "habitat", "peek": true})
			view.set_camera(5.5, Vector2(100, 40))
		if i % 97 == 0:
			for id in view.LAYERS:
				view.draw_layer(WV.Recorder.new(), id)
	t.eq(_wv._sig(seen), _wv._sig(plain), "sim hash identical with and without the full view (seed 7, 2 sols)")
	t.eq(seen.rng._rng.state, plain.rng._rng.state, "rng state identical")
	_wv._free(pair)


func test_model_update_stays_under_budget_with_160_beings(t) -> void:
	var w := _world()
	var kinds := ["habitat", "comms", "workshop", "green_room", "reactor", "archive"]
	var roles := ["builder", "curious", "social", "tender"]
	for i in 160:
		var g: Being
		if i < 20:
			g = _eva(w, roles[i % 4], 40.0 + float(i) * 8.0, 100.0 + float(i % 3) * 6.0, i % 2 == 0)
		else:
			g = _inside(w, kinds[i % 6], roles[i % 4], "sleep" if i % 5 == 0 else "idle")
	var pair := _wv._make(w)
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(212, 36))
	_open_roof(view, _building(w, "habitat"))
	for i in 20:
		view._process(DT)
	var times: Array[float] = []
	for i in 200:
		for g in w.beings:
			if g.is_outside():
				g.x = float(g.x) + 0.2
		var t0 := Time.get_ticks_usec()
		view.vm.update(DT)
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var med := times[times.size() / 2]
	var budget := float(view.art.perf.model_update_ms_max)
	print("view model: 160 beings, one building open, update median %.3f ms (budget %.1f ms)" % [med, budget])
	t.check(med <= budget, "model update median %.3f ms within %.1f ms" % [med, budget])
	t.eq(int(view.vm.skipped), 0, "no being skipped")
	var d := _wv._draw_all(view)
	print("view draw: %d commands with 160 beings, 1 building open" % d.rec.cmds.size())
	t.check(d.rec.cmds.size() > 0, "the frame draws")
	_wv._free(pair)
