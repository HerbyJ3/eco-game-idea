extends SceneTree
## Screenshot harness. Needs a real renderer, never --headless:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
##     --script res://tools/shot.gd -- --scene res://view/main.tscn --seed 42 --steps 0 --hour 12 \
##     --zoom 2 --center 100,80 --out /tmp/a.png [--size 1280x720] [--setup showcase]
## --steps S    fixed sim steps first (default 0)
## --until k=v[,k=v]   then keep stepping until every predicate holds (at most art.shots.max_steps more steps):
##              site_built_ge=F (the construction site has built >= F), crew_ge=N (beings working on it),
##              any_state=NAME (some being is in that state), footprints_ge=N. Runs after --steps.
## --hour H     then keep stepping until Clock.mars_hour(t) reaches H (never writes t; lands within +-0.025 h)
## --setup NAME a named setup of tools/shot_setups.gd, applied after all stepping so it is never undone. Blank
##              setups (the showcase) run on an empty world.
## --zoom Z / --center C   C is x,y in world px, a name of art.shots.centers, or symbolic: site (the construction
##              site), footprints (their mean), being_outside (the first being outside), colony (the layout centre).
##              Applied through the scene's set_camera(zoom, center), or zoom / center properties.
## --view k=v[,k=v]    view-side state for scenes with apply_shot_view: debug_map, select, peek, hud (true/false).
## --settle S   seconds of view time the scene advances before the capture (doors open, sparks fly), default 1.5, for
##              scenes with settle_view; the view model is then frozen so shots do not depend on frame timing.

const ShotSetups := preload("res://tools/shot_setups.gd")
const FRAMES_BEFORE_CAPTURE := 3


func _initialize() -> void:
	_run.call_deferred()


func _arg_map() -> Dictionary:
	var m := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--"):
			var key: String = a[i].substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				m[key] = a[i + 1]
				i += 1
			else:
				m[key] = "true"
		i += 1
	return m


func _fail(msg: String) -> void:
	printerr("shot: ", msg)
	quit(1)


func _run() -> void:
	var args := _arg_map()
	if not args.has("out"):
		return _fail("--out is required")
	var scene_path: String = args.get("scene", "res://view/main.tscn")
	var seed_n := int(args.get("seed", SimData.sim().default_seed))
	var steps := int(args.get("steps", 0))
	var setup_name: String = args.get("setup", "")
	var art: Dictionary = SimData.load_json("art.json")
	var size := Vector2i(int(art.shots.width_px), int(art.shots.height_px))
	if args.has("size"):
		var p: PackedStringArray = String(args.size).split("x")
		if p.size() != 2:
			return _fail("--size must be WxH")
		size = Vector2i(int(p[0]), int(p[1]))
	if setup_name != "" and not ShotSetups.known(setup_name):
		return _fail("unknown --setup '%s'" % setup_name)

	var world := SimWorld.new(seed_n, {"blank": true} if ShotSetups.is_blank(setup_name) else {})
	for i in steps:
		world.step()
	if args.has("until") and not _step_until(world, _pairs(String(args.until)), int(art.shots.max_steps)):
		return _fail("--until %s not reached in %d steps" % [args.until, int(art.shots.max_steps)])
	if args.has("hour"):
		var target := fposmod(float(args.hour), 24.0)
		var guard := int(world.clock.sol_h / world.fixed_step) + 2
		var cur := world.clock.mars_hour(world.t)
		# Step until the hour is within half a step of the target (with wrap), at most one sol.
		while guard > 0 and absf(_wrap_diff(cur, target)) > world.fixed_step * 0.5:
			world.step()
			cur = world.clock.mars_hour(world.t)
			guard -= 1
		if guard <= 0:
			return _fail("could not reach hour %s" % args.hour)
	if setup_name != "" and not ShotSetups.apply(setup_name, world):
		return _fail("setup '%s' failed" % setup_name)

	root.size = size
	get_root().get_window().size = size
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	var host := root.get_node_or_null("Sim")
	if host != null:
		host.speed = 0.0
		host.world = world
		root.add_child(scene)
	else:
		root.add_child(scene)
		if scene.has_method("setup"):
			scene.setup(world)

	if args.has("view") and scene.has_method("apply_shot_view"):
		scene.apply_shot_view(_pairs(String(args.view)))
	_apply_camera(scene, args, world, art)
	if scene.has_method("settle_view"):
		scene.settle_view(float(args.get("settle", 1.5)))

	for i in FRAMES_BEFORE_CAPTURE:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out: String = args.out
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	if err != OK:
		return _fail("save_png failed (%d)" % err)
	print("shot: %s  seed %d  sol %d  mars_hour %.2f  steps %d  %dx%d  draw_calls %d  nodes %d" % [out, seed_n,
			world.sol(), world.clock.mars_hour(world.t), world.step_index, img.get_width(), img.get_height(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			get_node_count()])
	quit(0)


## "a=1,b=x" -> {a: 1.0, b: "x"}; true and false become booleans, numbers floats.
func _pairs(text: String) -> Dictionary:
	var out := {}
	for part in text.split(",", false):
		var kv := part.split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else "true"
		if v == "true" or v == "false":
			out[kv[0]] = v == "true"
		elif v.is_valid_float():
			out[kv[0]] = float(v)
		else:
			out[kv[0]] = v
	return out


## Steps until every predicate holds, at most max_steps. True when they hold (also when they hold at once).
func _step_until(world: SimWorld, preds: Dictionary, max_steps: int) -> bool:
	for i in max_steps:
		if _until_met(world, preds):
			return true
		world.step()
	return _until_met(world, preds)


func _until_met(world: SimWorld, preds: Dictionary) -> bool:
	for key in preds:
		var v: Variant = preds[key]
		match key:
			"site_built_ge":
				var site := world.buildings.site
				if site == null or world.buildings.get_building(site.building_id).built < float(v):
					return false
			"crew_ge":
				if _crew(world) < int(v):
					return false
			"any_state":
				var found := false
				for g in world.beings:
					if g.state == String(v):
						found = true
						break
				if not found:
					return false
			"footprints_ge":
				if world.resources.footprints.size() < int(v):
					return false
			_:
				push_error("shot: unknown --until predicate '%s'" % key)
				return false
	return true


func _crew(world: SimWorld) -> int:
	var site := world.buildings.site
	var n := 0
	if site != null:
		for g in world.beings:
			if g.state == "work" and g.job == site:
				n += 1
	return n


func _wrap_diff(a: float, b: float) -> float:
	return fposmod(a - b + 12.0, 24.0) - 12.0


func _apply_camera(scene: Node, args: Dictionary, world: SimWorld, art: Dictionary) -> void:
	var has_zoom := args.has("zoom")
	var has_center := args.has("center")
	if not (has_zoom or has_center):
		return
	var z := float(args.get("zoom", art.camera.zoom_default))
	var c := Vector2.ZERO
	if has_center:
		c = _resolve_center(String(args.center), world, art)
	if scene.has_method("set_camera"):
		scene.set_camera(z, c)
		return
	for prop in scene.get_property_list():
		if has_zoom and prop.name == "zoom":
			scene.set("zoom", z)
		if has_center and prop.name == "center":
			scene.set("center", c)


## x,y; a name from art.shots.centers; or site, footprints, being_outside, colony (resolved from the world).
func _resolve_center(text: String, world: SimWorld, art: Dictionary) -> Vector2:
	var tile := float(SimData.buildings().tile_px)
	var p: PackedStringArray = text.split(",")
	if p.size() == 2:
		return Vector2(float(p[0]), float(p[1]))
	if art.shots.centers.has(text):
		var n: Array = art.shots.centers[text]
		return Vector2(float(n[0]), float(n[1]))
	match text:
		"site":
			var site := world.buildings.site
			if site != null:
				var b := world.buildings.get_building(site.building_id)
				return Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile).get_center()
		"footprints":
			var fp := world.resources.footprints
			if not fp.is_empty():
				var sum := Vector2.ZERO
				for f in fp:
					sum += Vector2(f.x, f.y)
				return sum / float(fp.size())
		"being_outside":
			for g in world.beings:
				if g.is_outside() and g.x != null:
					return Vector2(float(g.x), float(g.y))
		"colony":
			var union := Rect2()
			for i in world.buildings.list.size():
				var b: Buildings.Building = world.buildings.list[i]
				var r := Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile)
				union = r if i == 0 else union.merge(r)
			return union.get_center()
	push_error("shot: cannot resolve --center '%s' for this world, using the origin" % text)
	return Vector2.ZERO
