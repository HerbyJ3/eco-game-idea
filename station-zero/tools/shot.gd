extends SceneTree
## Screenshot harness. Needs a real renderer, never --headless:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
##     --script res://tools/shot.gd -- --scene res://view/main.tscn --seed 42 --steps 0 --hour 12 \
##     --zoom 2 --center 100,80 --out /tmp/a.png [--size 1280x720] [--setup founders]
## --steps S    fixed sim steps first (default 0)
## --hour H     then keep stepping until Clock.mars_hour(t) reaches H (never writes t)
## --zoom Z / --center x,y   applied only if the scene exposes set_camera(zoom, center),
##              or zoom / center properties; ignored otherwise.

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
	var size := Vector2i(1280, 720)
	if args.has("size"):
		var p: PackedStringArray = String(args.size).split("x")
		if p.size() != 2:
			return _fail("--size must be WxH")
		size = Vector2i(int(p[0]), int(p[1]))

	var world := SimWorld.new(seed_n)
	if args.has("setup") and not ShotSetups.apply(String(args.setup), world):
		return _fail("unknown --setup '%s'" % args.setup)
	for i in steps:
		world.step()
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

	_apply_camera(scene, args)

	for i in FRAMES_BEFORE_CAPTURE:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out: String = args.out
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	if err != OK:
		return _fail("save_png failed (%d)" % err)
	print("shot: %s  seed %d  sol %d  mars_hour %.2f  steps %d  %dx%d" % [out, seed_n,
			world.sol(), world.clock.mars_hour(world.t), world.step_index, img.get_width(), img.get_height()])
	quit(0)


func _wrap_diff(a: float, b: float) -> float:
	return fposmod(a - b + 12.0, 24.0) - 12.0


func _apply_camera(scene: Node, args: Dictionary) -> void:
	var has_zoom := args.has("zoom")
	var has_center := args.has("center")
	if not (has_zoom or has_center):
		return
	var z := float(args.get("zoom", 1.0))
	var c := Vector2.ZERO
	if has_center:
		var p: PackedStringArray = String(args.center).split(",")
		if p.size() == 2:
			c = Vector2(float(p[0]), float(p[1]))
	if scene.has_method("set_camera"):
		scene.set_camera(z, c)
		return
	for prop in scene.get_property_list():
		if has_zoom and prop.name == "zoom":
			scene.set("zoom", z)
		if has_center and prop.name == "center":
			scene.set("center", c)
