extends RefCounted
## Task 2, steps 11 to 13: the sprite world view (terrain, buildings, doors, lights, construction, camera).
## Spec: docs/specs/sprite-view.md sections 4 to 6, 8, 10. The view is driven by hand (setup, _process) because nodes
## cannot be ready inside the runner's _init, and its layers are drawn into a Recorder that stands in for the canvas, so
## every textured draw is inspected without a renderer: its source rect, its destination rect, its alpha.

const DT := 1.0 / 60.0


## Stand-in for a CanvasItem: records every draw command as {cmd, ...} and does nothing else.
class Recorder extends RefCounted:
	var cmds: Array = []

	func draw_texture_rect(tex: Texture2D, rect: Rect2, _tile: bool = false, modulate: Color = Color.WHITE) -> void:
		cmds.append({"cmd": "tex", "tex": tex, "rect": rect, "alpha": modulate.a})

	func draw_texture_rect_region(tex: Texture2D, rect: Rect2, src: Rect2, modulate: Color = Color.WHITE) -> void:
		cmds.append({"cmd": "region", "tex": tex, "rect": rect, "src": src, "alpha": modulate.a})

	func draw_rect(rect: Rect2, color: Color, _filled: bool = true, _width: float = -1.0) -> void:
		cmds.append({"cmd": "rect", "rect": rect, "color": color})

	func draw_circle(pos: Vector2, radius: float, color: Color, _filled: bool = true, _width: float = -1.0,
			_aa: bool = false) -> void:
		cmds.append({"cmd": "circle", "pos": pos, "radius": radius, "color": color})

	func draw_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _aa: bool = false) -> void:
		cmds.append({"cmd": "line", "from": from, "to": to, "color": color, "width": width})

	func draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float = -1.0, _dash: float = 2.0,
			_aligned: bool = true, _aa: bool = false) -> void:
		cmds.append({"cmd": "dashed", "from": from, "to": to, "color": color, "width": width})

	func draw_colored_polygon(points: PackedVector2Array, color: Color) -> void:
		cmds.append({"cmd": "poly", "points": points, "color": color})

	func draw_primitive(points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array,
			tex: Texture2D = null) -> void:
		cmds.append({"cmd": "prim", "points": points, "colors": colors, "uvs": uvs, "tex": tex})

	func draw_style_box(_box: StyleBox, rect: Rect2) -> void:
		cmds.append({"cmd": "box", "rect": rect})

	func draw_set_transform(_pos: Vector2, _rot: float = 0.0, _scale: Vector2 = Vector2.ONE) -> void:
		pass

	func count(cmd: String) -> int:
		var n := 0
		for c in cmds:
			if c.cmd == cmd:
				n += 1
		return n


func _make(world: SimWorld) -> Array:
	var sim: Node = load("res://view/sim_host.gd").new()
	sim.world = world
	var view: Node2D = (load("res://view/world/world_view.tscn") as PackedScene).instantiate()
	view.setup(sim)
	return [sim, view]


func _free(pair: Array) -> void:
	pair[1].free()
	pair[0].free()


## Frames of the view with the world frozen: the model and the layers refresh, nothing else.
func _frames(view: Node2D, n: int, dt: float = DT) -> void:
	for i in n:
		view._process(dt)


## Draws every layer into one recorder with texture logging on; returns {rec, log, by_layer}.
func _draw_all(view: Node2D) -> Dictionary:
	view.ctx.record = true
	view.ctx.log.clear()
	var by_layer := {}
	var all := Recorder.new()
	for id in view.LAYERS:
		var rec := Recorder.new()
		view.draw_layer(rec, id)
		by_layer[id] = rec
		all.cmds.append_array(rec.cmds)
	return {"rec": all, "log": view.ctx.log.duplicate(), "by_layer": by_layer}


## Everything the view must never change: time, step, rng state, stocks, beings, buildings, resources, stats.
func _sig(w: SimWorld) -> String:
	var p: Array[String] = []
	p.append("%s|%d|%d|%d" % [str(w.t), w.step_index, w.rng._rng.state, w.rng.seed_value])
	p.append("%s|%s|%s|%s" % [str(w.colony.oxygen), str(w.colony.food), str(w.colony.ice), str(w.colony.regolith)])
	for b in w.beings:
		p.append("b%d|%s|%d|%s|%s|%s|%s|%s|%s|%d" % [b.id, b.state, b.building_id, str(b.x), str(b.y), str(b.heading),
				str(b.energy), str(b.wait_h), str(b.load), 1 if b.suit_up else 0])
	for b in w.buildings.list:
		p.append("B%d|%s|%s|%d" % [b.id, b.kind, str(b.built), 1 if b.offline else 0])
	p.append("fp%d" % w.resources.footprints.size())
	for s in w.resources.ice_fields:
		p.append("i%s,%s,%s" % [str(s.x), str(s.y), str(s.amount)])
	for s in w.resources.pits:
		p.append("p%s,%s,%s" % [str(s.x), str(s.y), str(s.dug)])
	p.append(JSON.stringify(w.stats))
	p.append(str(w.log.size()))
	return "\n".join(p).sha256_text()


## A blank world with the art.json showcase buildings, all built and online.
func _showcase() -> SimWorld:
	var w := SimWorld.new(42, {"blank": true})
	var art: Dictionary = SimData.load_json("art.json")
	for s: Dictionary in art.showcase.buildings:
		w.buildings.add(String(s.kind), int(s.tx), int(s.ty), 1.0, int(s.tw), int(s.th))
	return w


func _set_hour(w: SimWorld, hour: float) -> void:
	while absf(fposmod(w.clock.mars_hour(w.t) - hour + 12.0, 24.0) - 12.0) > w.fixed_step * 0.5:
		w.step()


# ---------------------------------------------------------------- structure

func test_layers_in_spec_order_and_node_budget(t) -> void:
	var pair := _make(SimWorld.new(7))
	var view: Node2D = pair[1]
	_frames(view, 5)
	var names: Array[String] = []
	for c in view.get_children():
		names.append(c.layer_id)
	t.eq(names, view.LAYERS, "layers are children in the spec 6 order")
	t.eq(view.LAYERS, ["terrain", "footprints", "corridors", "transit", "shadows", "entities", "dust", "tint", "lights",
			"selection"] as Array[String], "terrain, footprints, tunnels, transit, shadows, entities, dust, tint, lights, selection")
	for id in view.layers:
		t.eq(view.layers[id].get_child_count(), 0, "layer %s has no per-object nodes" % id)
		t.eq(view.layers[id].texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, "%s uses mipmapped filtering" % id)
	var art: Dictionary = SimData.load_json("art.json")
	var nodes := 1 + view.get_child_count()
	t.check(nodes <= int(art.perf.node_count_max), "node count %d within the budget %d" % [nodes, int(art.perf.node_count_max)])
	t.eq((view.layers.lights.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_ADD, "lights are additive")
	t.eq((view.layers.tint.material as CanvasItemMaterial).blend_mode, CanvasItemMaterial.BLEND_MODE_MUL, "tint multiplies")
	_free(pair)


func test_every_layer_draws_something_or_is_reserved(t) -> void:
	var pair := _make(SimWorld.new(7))
	var view: Node2D = pair[1]
	_frames(view, 3)
	var d := _draw_all(view)
	for id in ["terrain", "corridors", "shadows", "entities", "tint", "lights"]:
		t.check(d.by_layer[id].cmds.size() > 0, "layer %s drew %d commands" % [id, d.by_layer[id].cmds.size()])
	for id in ["footprints", "transit", "selection"]:
		t.eq(d.by_layer[id].cmds.size(), 0, "layer %s is empty with no prints, no tunnel beings and no selection" % id)
	_free(pair)


# ---------------------------------------------------------------- sprites

func test_building_sprites_are_fitted_never_stretched(t) -> void:
	var w := _showcase()
	# A 10 x 10 footprint (aspect 1.0) next to the wide ones, and a site, so the limiting side changes.
	w.buildings.add("habitat", 60, 0, 1.0, 10, 10)
	var pair := _make(w)
	var view: Node2D = pair[1]
	view.set_camera(0.6, Vector2(212, 108))
	_frames(view, 3)
	var d := _draw_all(view)
	var bases := 0
	for e in d.log:
		var scale: Vector2 = (e.rect as Rect2).size / (e.src as Rect2).size
		t.near(scale.x, scale.y, 1e-4, "%s drawn with one scale for both axes" % e.id)
		if String(e.id).ends_with(".base"):
			bases += 1
	t.eq(bases, w.buildings.list.size(), "one base sprite per finished building")
	for b in w.buildings.list:
		var ext: Rect2 = view.vm.sprite_rect(b)
		var foot: Rect2 = view.vm.footprint_rect(b)
		var e: Dictionary = view.vm.man.entries["building.%s.base" % b.kind]
		t.near(ext.size.x / ext.size.y, float(e.w) / float(e.h), 1e-4, "%s keeps the sprite aspect" % b.kind)
		t.check(foot.grow(0.001).encloses(ext), "%s sprite stays inside its footprint" % b.kind)
		t.check(absf(ext.get_center().x - foot.get_center().x) <= foot.size.x * 0.01 + 0.001,
				"%s door x is the sim door x within the 1 percent clamp" % b.kind)
		t.near(ext.end.y, foot.end.y, 0.001, "%s sits on the footprint's bottom edge" % b.kind)
	_free(pair)


func test_mipmapped_textures_for_sprites(t) -> void:
	var pair := _make(SimWorld.new(7))
	var view: Node2D = pair[1]
	var tex: Texture2D = view.lib.texture("building.reactor.base")
	t.check(tex != null, "reactor base loads")
	t.check(tex.get_image().has_mipmaps(), "building textures carry mipmaps")
	_free(pair)


# ---------------------------------------------------------------- doors and lights

func test_door_leaves_follow_the_model(t) -> void:
	var w := _showcase()
	_set_hour(w, 12.0)
	var hab := w.buildings.list[1]
	var g := w.add_being(hab.id, "builder")
	g.state = "to_door"
	g.suit_up = true
	g.mine_intent = w.resources.add_pit(300.0, 200.0)
	var pair := _make(w)
	var view: Node2D = pair[1]
	var closed_w := 0.0
	var anim = view.vm.building(hab.id)
	t.eq(anim.door_open, 0.0, "the door starts closed")
	view.settle_view(0.0)
	var d0 := _draw_all(view)
	for e in d0.log:
		if e.id == "building.habitat.door":
			closed_w += (e.rect as Rect2).size.x
	var ext: Rect2 = view.vm.sprite_rect(hab)
	var door: Rect2 = view._buildings.door_world(view.ctx, "habitat", ext)
	t.near(closed_w, door.size.x, 0.01, "closed: the two leaf halves fill the door rect")
	view.settle_view(2.0)
	t.check(anim.door_open > 0.95, "the model opened the door (%.3f)" % anim.door_open)
	var d1 := _draw_all(view)
	var open_w := 0.0
	var inside := true
	for e in d1.log:
		if e.id == "building.habitat.door":
			open_w += (e.rect as Rect2).size.x
			inside = inside and door.grow(0.001).encloses(e.rect)
	t.check(open_w < closed_w * 0.2, "open: the leaves have slid out of the door rect (%.2f of %.2f px)" % [open_w, closed_w])
	t.check(inside, "leaves are clipped to the door rect")
	t.check(d1.rec.count("tex") + d1.rec.count("region") > 0, "the opened door draws")
	_free(pair)


func test_rollup_door_slides_up_clipped(t) -> void:
	var w := _showcase()
	_set_hour(w, 12.0)
	var shop: Buildings.Building = null
	for b in w.buildings.list:
		if b.kind == "workshop":
			shop = b
	var g := w.add_being(shop.id, "builder")
	g.state = "to_door"
	g.suit_up = true
	g.mine_intent = w.resources.add_pit(300.0, 200.0)
	var pair := _make(w)
	var view: Node2D = pair[1]
	var ext: Rect2 = view.vm.sprite_rect(shop)
	var door: Rect2 = view._buildings.door_world(view.ctx, "workshop", ext)
	view.settle_view(0.0)
	var shut := 0.0
	for e in _draw_all(view).log:
		if e.id == "building.workshop.door":
			shut += (e.rect as Rect2).size.y
	t.near(shut, door.size.y, 0.01, "closed roll-up fills the door height")
	view.settle_view(2.0)
	var up := 0.0
	for e in _draw_all(view).log:
		if e.id == "building.workshop.door":
			up += (e.rect as Rect2).size.y
			t.check(door.grow(0.001).encloses(e.rect), "roll-up panel stays inside the door rect")
	t.check(up < shut * 0.2, "open roll-up has slid up out of the rect (%.2f of %.2f px)" % [up, shut])
	_free(pair)


func test_lights_follow_day_and_night(t) -> void:
	var w := _showcase()
	_set_hour(w, 12.0)
	var pair := _make(w)
	var view: Node2D = pair[1]
	_frames(view, 3)
	var day := _draw_all(view)
	var night_w := _showcase()
	_set_hour(night_w, 23.0)
	var pair2 := _make(night_w)
	var view2: Node2D = pair2[1]
	_frames(view2, 3)
	var night := _draw_all(view2)
	var day_windows := 0
	var night_windows := 0
	var reactor_accent_day := 0.0
	var reactor_accent_night := 0.0
	for e in day.log:
		if String(e.id).contains("mask.windows"):
			day_windows += 1
		if e.id == "building.reactor.mask.accent" and reactor_accent_day == 0.0:
			reactor_accent_day = e.alpha
	for e in night.log:
		if String(e.id).contains("mask.windows"):
			night_windows += 1
		if e.id == "building.reactor.mask.accent" and reactor_accent_night == 0.0:
			reactor_accent_night = e.alpha
	t.eq(day_windows, 0, "no window glow at noon")
	t.check(night_windows >= 6, "window glow on the buildings at night (%d draws)" % night_windows)
	t.check(reactor_accent_night > reactor_accent_day, "accents are brighter at night")
	# Alphas are exactly the model's.
	var rid := w.buildings.list[0].id
	var want: Dictionary = view2.vm.building(rid).lights(view2.ctx.hour, view2.vm.real_time, 0.0)
	t.near(reactor_accent_night, want.accent, 1e-5, "accent alpha is the model's")
	# Tint: night multiplies much darker than day, noon barely tints.
	var tint_day: Color = view.tint_color()
	var tint_night: Color = view2.tint_color()
	t.check(tint_day.r > 0.8 and tint_day.b > 0.75, "day tint is a light warm multiply")
	t.check(tint_night.get_luminance() < tint_day.get_luminance() * 0.4, "night tint is far darker than day")
	t.check(day.by_layer.shadows.cmds.size() > 0, "building shadows at noon")
	t.eq(night.by_layer.shadows.cmds.size(), 0, "no building shadows at night")
	_free(pair)
	_free(pair2)


func test_offline_building_is_dark(t) -> void:
	var w := _showcase()
	var hab := w.buildings.list[1]
	w.set_offline(hab.id, true)
	_set_hour(w, 23.0)
	var pair := _make(w)
	var view: Node2D = pair[1]
	view.settle_view(2.0)
	var d := _draw_all(view)
	var lit := {}
	var dim := 0.0
	for e in d.log:
		var id := String(e.id)
		if id.begins_with("building.habitat.mask.accent") or id.begins_with("building.habitat.mask.windows"):
			lit[id] = true
		if id.begins_with("building.reactor.mask.accent"):
			lit["reactor"] = true
		if id == "building.habitat.mask.shadow":
			dim = e.alpha
	t.check(not lit.has("building.habitat.mask.accent") and not lit.has("building.habitat.mask.windows"),
			"an offline habitat has no accents or windows")
	t.check(lit.has("reactor"), "the online reactor still glows")
	var art: Dictionary = SimData.load_json("art.json")
	t.near(dim, float(art.offline.dim_alpha), 1e-4, "offline overlay is the dim alpha")
	# Sparks: the flicker emitter produces particles that the lights layer draws as discs.
	var flicks := 0
	for i in 600:
		view.vm.update(DT * 6.0)
		flicks += view.vm.particles.snapshot().size()
	t.check(flicks > 0, "an offline building flickers")
	_free(pair)


# ---------------------------------------------------------------- construction

func test_site_draws_by_phase(t) -> void:
	var art: Dictionary = SimData.load_json("art.json")
	var seen := {}
	for built in [0.0, 0.3, 0.6, 0.9]:
		var w := SimWorld.new(42, {"blank": true})
		var b := w.buildings.add("reactor", 0, 0, built, 12, 10)
		var site := Buildings.Site.new()
		site.building_id = b.id
		w.buildings.site = site
		var pair := _make(w)
		var view: Node2D = pair[1]
		_frames(view, 3)
		var d := _draw_all(view)
		var ids := {}
		for e in d.log:
			ids[e.id] = e
		seen[built] = ids
		var ext: Rect2 = view.vm.sprite_rect(b)
		t.check(ids.has("building.reactor.mask.ghost"), "built %.1f: the ghost is drawn" % built)
		t.eq(d.by_layer.shadows.cmds.size(), 0, "built %.1f: a site casts no shadow" % built)
		var ph: Dictionary = _phases(built, art)
		if float(ph.f) > 0.0:
			var gray: Dictionary = ids["building.reactor.mask.gray"]
			var top := ext.position.y + ext.size.y * (1.0 - float(ph.f))
			t.near((gray.rect as Rect2).position.y, top, 0.01, "built %.1f: gray wall top follows the wall reveal" % built)
			t.near((gray.rect as Rect2).end.y, ext.end.y, 0.01, "built %.1f: gray wall reaches the bottom" % built)
		else:
			t.check(not ids.has("building.reactor.mask.gray"), "built %.1f: no gray wall yet" % built)
		var line_cmds: int = d.by_layer.entities.count("line")
		t.eq(line_cmds > 0, float(ph.sa) > 0.0, "built %.1f: scaffolding lines iff the scaffold alpha is positive" % built)
		var stakes := 0
		for c in d.by_layer.entities.cmds:
			if c.cmd == "rect" and (c.rect as Rect2).size == Vector2(float(art.construction.survey.stake_w_px), float(art.construction.survey.stake_h_px)):
				stakes += 1
		t.eq(stakes, 4, "built %.1f: four survey stakes" % built)
		_free(pair)
	t.check(not seen[0.6].has("building.reactor.base"), "built 0.6: paint has not started")
	t.check(seen[0.9].has("building.reactor.base"), "built 0.9: the painted base catches up")
	var gray60: Rect2 = seen[0.6]["building.reactor.mask.gray"].rect
	var gray90: Rect2 = seen[0.9]["building.reactor.mask.gray"].rect
	t.check(gray90.size.y > gray60.size.y, "the gray wall rises between 0.6 and 0.9")


func _phases(built: float, art: Dictionary) -> Dictionary:
	return load("res://view/model/construction.gd").phases(built, art)


func test_welding_sparks_are_drawn_from_the_snapshot(t) -> void:
	var w := SimWorld.new(42, {"blank": true})
	var shop := w.buildings.add("workshop", 0, 20, 1.0, 12, 9)
	var b := w.buildings.add("reactor", 0, 0, 0.6, 12, 10)
	var site := Buildings.Site.new()
	site.building_id = b.id
	w.buildings.site = site
	for i in 2:
		var g := w.add_being(shop.id, "builder")
		g.state = "work"
		g.job = site
	var pair := _make(w)
	var view: Node2D = pair[1]
	for i in 30:
		view._process(0.05)
	var snap: Array = view.vm.particles.snapshot()
	t.check(snap.size() > 0, "the crew's seam emitter made sparks (%d)" % snap.size())
	var d := _draw_all(view)
	var lines := 0
	for c in d.by_layer.lights.cmds:
		if c.cmd == "line":
			lines += 1
	t.eq(lines, snap.size(), "one spark streak per live particle, drawn on the additive layer")
	var ext: Rect2 = view.vm.sprite_rect(b)
	for p in snap:
		t.check(p.y <= ext.end.y and p.x >= ext.position.x - 1.0 and p.x <= ext.end.x + 1.0, "sparks start on the building")
		break
	_free(pair)


# ---------------------------------------------------------------- terrain and tunnels

class NoDecalLib extends ArtLibrary:
	## The real manifest now carries the terrain decals; these tests are about the procedural fallback, so the decals are hidden.
	func has_art(id: String) -> bool:
		return false if id.begins_with("terrain.decal.") else super.has_art(id)

	func texture(id: String) -> Texture2D:
		return null if id.begins_with("terrain.decal.") else super.texture(id)


func test_terrain_and_tunnels_from_sim_data(t) -> void:
	var w := SimWorld.new(42)
	var pair := _make(w)
	var view: Node2D = pair[1]
	view.set_camera(1.0, Vector2(212, 108))
	view.lib = NoDecalLib.new()
	view.lib.load_manifest()
	view.ctx.lib = view.lib
	_frames(view, 3)
	var d := _draw_all(view)
	var terrain: Recorder = d.by_layer.terrain
	var art: Dictionary = SimData.load_json("art.json")
	t.eq(terrain.cmds[0].cmd, "rect", "the ground is drawn first")
	t.eq((terrain.cmds[0].color as Color).to_html(false), String(art.terrain.ground_color).trim_prefix("#"), "ground colour from art.json")
	var circles := terrain.count("circle")
	t.check(circles >= w.resources.ice_fields.size() * int(art.terrain.ice.blob_count), "ice blobs drawn for the ice fields (%d)" % circles)
	var tunnels := 0
	for b in w.buildings.list:
		if b.corridor != null:
			tunnels += 1
	var cor: Recorder = d.by_layer.corridors
	t.check(tunnels == 3 and cor.count("rect") >= tunnels * 4, "three founder tunnels drawn (%d rects)" % cor.count("rect"))
	_free(pair)


func test_unbuilt_tunnel_is_dashed_and_partial(t) -> void:
	var w := SimWorld.new(42)
	var core := w.buildings.list[0]
	var site := w.buildings.add_attached("habitat", core.id, "r", 12, 9, 9, 0.2)
	var s := Buildings.Site.new()
	s.building_id = site.id
	w.buildings.site = s
	var pair := _make(w)
	var view: Node2D = pair[1]
	_frames(view, 2)
	var d := _draw_all(view)
	var cor: Recorder = d.by_layer.corridors
	t.eq(cor.count("dashed"), 1, "the full path of the unfinished building is dashed")
	var art: Dictionary = SimData.load_json("art.json")
	var want := float(site.corridor.len) * 0.2 / float(art.construction.corridor_built_frac)
	var edge_len := 0.0
	for c in cor.cmds:
		if c.cmd == "rect" and (c.rect as Rect2).size.y == float(art.corridor.edge_half_px) * 2.0 \
				and absf((c.rect as Rect2).position.x - (site.corridor.p1 as Vector2).x) < 0.01:
			edge_len = (c.rect as Rect2).size.x
	t.near(edge_len, want, 0.01, "the revealed tunnel is built / 0.4 of the path")
	_free(pair)


# ---------------------------------------------------------------- camera and input

func test_camera_transform_and_set_camera(t) -> void:
	var pair := _make(SimWorld.new(7))
	var view: Node2D = pair[1]
	view.set_camera(4.0, Vector2(100, 60))
	t.eq(view.scale, Vector2(4.0, 4.0), "uniform camera scale")
	var size := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")),
			float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	t.near(view.position.x, size.x * 0.5 - 100.0 * 4.0, 1e-3, "centre maps to the middle of the screen (x)")
	t.near(view.position.y, size.y * 0.5 - 60.0 * 4.0, 1e-3, "centre maps to the middle of the screen (y)")
	view.set_camera(99.0, Vector2(1e6, -1e6))
	var art: Dictionary = SimData.load_json("art.json")
	t.eq(view.vm.camera.zoom, float(art.camera.zoom_max), "zoom clamps to the max")
	t.check(view.vm.camera.bounds().grow(0.001).has_point(view.vm.camera.center), "centre clamps inside the model's bounds")
	_free(pair)


func test_wheel_zoom_keeps_point_under_cursor_and_keys(t) -> void:
	var pair := _make(SimWorld.new(7))
	var view: Node2D = pair[1]
	view.set_camera(2.0, Vector2(100, 60))
	var size: Vector2 = view._viewport_size()
	var cursor := Vector2(900, 200)
	var before: Vector2 = view.vm.camera.screen_to_world(cursor, size)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP
	ev.pressed = true
	ev.position = cursor
	view._unhandled_input(ev)
	var art: Dictionary = SimData.load_json("art.json")
	t.near(view.vm.camera.zoom, 2.0 * float(art.camera.wheel_step), 1e-4, "one wheel notch zooms by wheel_step")
	var after: Vector2 = view.vm.camera.screen_to_world(cursor, size)
	t.near(after.x, before.x, 0.01, "the world point under the cursor stays put (x)")
	t.near(after.y, before.y, 0.01, "the world point under the cursor stays put (y)")
	# Keys: M toggles the debug map, Home resets, F follows.
	var m := InputEventKey.new()
	m.keycode = KEY_M
	m.pressed = true
	view._unhandled_input(m)
	t.check(view.vm.debug_map, "M switches to the debug map")
	view._unhandled_input(m)
	t.check(not view.vm.debug_map, "M switches back")
	var home := InputEventKey.new()
	home.keycode = KEY_HOME
	home.pressed = true
	view._unhandled_input(home)
	t.eq(view.vm.camera.zoom, float(art.camera.zoom_default), "Home resets the zoom")
	var codes: Array = view._keycodes.pan_left
	t.check(codes.size() == 2, "Left and A are bound to pan left")
	t.check(view._keycodes.zoom_in.size() == 2, "Equal and keypad plus are bound to zoom in")
	_free(pair)


func test_drag_pans_and_a_tap_selects(t) -> void:
	var pair := _make(_showcase())
	var view: Node2D = pair[1]
	view.set_camera(2.0, Vector2(212, 108))
	var c0: Vector2 = view.vm.camera.center
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(400, 300)
	view._unhandled_input(down)
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(500, 300)
	mv.relative = Vector2(100, 0)
	view._unhandled_input(mv)
	t.near(view.vm.camera.center.x, c0.x - 50.0, 1e-3, "a 100 px drag at zoom 2 moves the world 50 px")
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(500, 300)
	view._unhandled_input(up)
	t.eq(view.vm.selection.selected, 0, "a drag does not select")
	# A tap on the reactor (world 48,40 is at the screen position the camera maps it to).
	var size: Vector2 = view._viewport_size()
	var cam: Object = view.vm.camera
	var tap_at: Vector2 = size * 0.5 + (Vector2(48, 40) - cam.center) * cam.zoom
	down.position = tap_at
	view._unhandled_input(down)
	up.position = tap_at
	view._unhandled_input(up)
	t.eq(view.vm.selection.selected, view.vm.world.buildings.list[0].id, "a tap selects the building under it")
	_free(pair)


# ---------------------------------------------------------------- the view never touches the sim

func test_view_never_writes_the_sim(t) -> void:
	var w := SimWorld.new(7)
	for i in 600:
		w.step()
	var before := _sig(w)
	var pair := _make(w)
	var view: Node2D = pair[1]
	for i in 200:
		view._process(DT)
		if i % 20 == 0:
			_draw_all(view)
	view.set_camera(6.0, Vector2(48, 40))
	view.settle_view(1.0)
	view.apply_shot_view({"select": "habitat", "peek": true})
	_draw_all(view)
	t.eq(_sig(w), before, "sim signature unchanged after 200 frames, draws, camera moves and selection")
	_free(pair)


func test_sim_hash_unchanged_with_the_view_attached(t) -> void:
	# Seed 7, 10 sols (the Task 1 determinism length): one world alone, one with the view refreshing and drawing.
	var sols := 10
	var plain := SimWorld.new(7)
	var seen := SimWorld.new(7)
	var pair := _make(seen)
	var view: Node2D = pair[1]
	var steps := int(float(sols) * plain.clock.sol_h / plain.fixed_step)
	for i in steps:
		plain.step()
		seen.step()
		if i % 4 == 0:
			view._process(DT)
		if i % 400 == 0:
			_draw_all(view)
	t.eq(_sig(seen), _sig(plain), "sim state hash identical with and without the view (seed 7, %d steps)" % steps)
	t.eq(seen.rng._rng.state, plain.rng._rng.state, "rng state identical")
	t.eq(int(view.vm.skipped), 0, "no being skipped")
	t.check(plain.colony.pop() > 0, "the run had a population")
	var rows: Array[String] = []
	for row in [plain, seen]:
		rows.append("sol %d pop %d oxygen %.3f food %.3f ice %.3f regolith %.3f deaths %s births %d" % [row.sol(),
				row.colony.pop(), row.colony.oxygen, row.colony.food, row.colony.ice, row.colony.regolith,
				JSON.stringify(row.stats.deaths), int(row.stats.births)])
	t.eq(rows[0].sha256_text(), rows[1].sha256_text(), "balance row hash identical")
	print("world view sim hash (seed 7, %d sols): %s" % [sols, _sig(seen).substr(0, 16)])
	_free(pair)


func test_view_cost_and_draw_counts_are_printed(t) -> void:
	var w := SimWorld.new(42)
	for i in 4000:
		w.step()
	var pair := _make(w)
	var view: Node2D = pair[1]
	view.set_camera(0.6, Vector2(212, 108))
	_frames(view, 5)
	var times: Array[float] = []
	var cmds := 0
	for i in 60:
		var t0 := Time.get_ticks_usec()
		view._process(DT)
		var d := _draw_all(view)
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		cmds = d.rec.cmds.size()
	times.sort()
	var art: Dictionary = SimData.load_json("art.json")
	print("world view: %d buildings, %d draw commands per frame, update + record median %.3f ms (model budget %.1f ms)" % [
			w.buildings.list.size(), cmds, times[times.size() / 2], float(art.perf.model_update_ms_max)])
	t.check(cmds > 0, "frame draws commands")
	t.check(cmds < 4000, "draw commands stay small (%d)" % cmds)
	_free(pair)


## A blank world of 30 finished, online buildings (the six showcase kinds in a 6 x 5 grid).
func _grid30() -> SimWorld:
	var w := SimWorld.new(42, {"blank": true})
	var kinds: Array = SimData.load_json("art.json").showcase.buildings
	for i in 30:
		var s: Dictionary = kinds[i % kinds.size()]
		w.buildings.add(String(s.kind), (i % 6) * 20, (i / 6) * 18, 1.0, int(s.tw), int(s.th))
	return w


## Draw records of the entities layer that belong to buildings (base, door leaves, offline dim, interior), plus the
## style boxes and the visible finished count.
func _entity_building_draws(view: Node2D) -> Dictionary:
	view.ctx.record = true
	view.ctx.log.clear()
	var rec := Recorder.new()
	view.draw_layer(rec, "entities")
	var n := 0
	for e in view.ctx.log:
		if String(e.id).begins_with("building."):
			n += 1
	var seen := 0
	for b in view.vm.world.buildings.list:
		if b.finished() and view._buildings._visible(view.ctx, b):
			seen += 1
	return {"textured": n, "boxes": rec.count("box"), "visible": seen, "cmds": rec.cmds.size()}


func test_far_zoom_lod_draws_base_only(t) -> void:
	var w := _grid30()
	var pair := _make(w)
	var view: Node2D = pair[1]
	var art: Dictionary = SimData.load_json("art.json")
	var thr := float(art.lod.detail_min_zoom)
	var centre := Vector2(60.0, 40.0) * float(SimData.buildings().tile_px) * 3.0
	# Far: 0.5 clamps to the camera minimum, which is still below the threshold.
	view.set_camera(0.5, centre)
	_frames(view, 3)
	t.check(view.vm.camera.zoom < thr, "far zoom is below the detail threshold (%.2f < %.2f)" % [view.vm.camera.zoom, thr])
	t.check(not view.ctx.detail, "the context is in far mode")
	var far := _entity_building_draws(view)
	t.check(int(far.visible) >= 10, "far view sees many buildings (%d)" % int(far.visible))
	t.check(int(far.textured) <= 2 * int(far.visible), "far: at most 2 building draws per finished building (%d for %d)" % [
			int(far.textured), int(far.visible)])
	t.eq(int(far.boxes), 0, "far: no foundation pads")
	var l := _draw_all(view)
	var door_far := 0
	for e in l.log:
		if String(e.id).ends_with(".door"):
			door_far += 1
	t.eq(door_far, 0, "far: no door leaves")
	# Near: base + door leaves (2 halves, 1 for the rollup), with no rectangle behind the artwork.
	view.set_camera(2.0, Vector2(42.0, 40.0))
	_frames(view, 3)
	t.check(view.ctx.detail, "the context is in detail mode at zoom 2")
	var near := _entity_building_draws(view)
	t.check(int(near.visible) >= 1, "near view sees a building (%d)" % int(near.visible))
	t.eq(int(near.boxes), 0, "near: no translucent foundation rectangles")
	t.check(int(near.textured) >= 3 * int(near.visible) - int(near.visible) and int(near.textured) <= 3 * int(near.visible),
			"near: base plus door leaves per building (%d for %d)" % [int(near.textured), int(near.visible)])
	# Six visible buildings: 6 bases and 10 door leaf halves.
	t.eq(int(near.textured), 16, "near: building draw count unchanged from before the LOD")
	t.eq(int(near.cmds), 16, "near: only the building artwork and doors are drawn")
	_free(pair)


func test_open_interior_removes_exterior_shadow(t) -> void:
	var w := SimWorld.new(42, {"blank": true})
	var b := w.buildings.add("reactor", 0, 0, 1.0, 12, 10)
	_set_hour(w, 12.0)
	var pair := _make(w)
	var view: Node2D = pair[1]
	view.set_camera(2.0, Vector2(48, 40))
	_frames(view, 3)
	var closed := Recorder.new()
	view.draw_layer(closed, "shadows")
	t.eq(closed.cmds.size(), 1, "closed reactor casts its exterior shadow")
	var closed_alpha: float = closed.cmds[0].alpha
	view.vm.selection.selected = b.id
	view.vm.selection.peek = true
	_frames(view, 1, float(view.ctx.art.selection.roof_fade_s) * 0.5)
	var cut: float = view._buildings.roof_cut(view.ctx, b)
	t.check(cut > 0.0 and cut < 1.0, "roof is partway open")
	var fading := Recorder.new()
	view.draw_layer(fading, "shadows")
	t.eq(fading.cmds.size(), 1, "shadow remains during the transition")
	t.near(float(fading.cmds[0].alpha), closed_alpha * (1.0 - cut), 1e-5, "roof and shadow fade together")
	_frames(view, 30)
	var opened := Recorder.new()
	view.draw_layer(opened, "shadows")
	t.eq(opened.cmds.size(), 0, "open interior has no exterior silhouette around it")
	view.vm.selection.deselect()
	_frames(view, 30)
	var restored := Recorder.new()
	view.draw_layer(restored, "shadows")
	t.eq(restored.cmds.size(), 1, "closing the roof restores its normal shadow")
	_free(pair)
