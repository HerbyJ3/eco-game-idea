extends SceneTree
## Performance harness for the sprite view (docs/specs/sprite-view.md section 10, plan step 17). Needs a real renderer:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
##     --script res://tools/perf_run.gd -- [--seed 42] [--sols 300] [--frames 600] [--warmup 30] [--speed-frames 120]
## Builds the seed world to --sols (slow: the sim runs headless-fast but not free), attaches res://view/main.tscn, opens
## one roof (the first habitat, peek) and measures per scenario (zoom 0.6, 2, 6 by day, then by night):
##   - view-model update (vm.update with the camera rect set), median / p95 / max ms over --frames calls, sim paused;
##   - per real frame: draw calls (RENDER_TOTAL_DRAW_CALLS_IN_FRAME), node count (OBJECT_NODE_COUNT), process ms
##     (TIME_PROCESS), render cpu ms (viewport measured), wall frame ms, RENDER_TEXTURE_MEM_USED;
## then the model refresh with the sim stepping at 1x (same 60 Hz dt), and the 1000x sim step cost with the view attached
## (world.advance cap hit?). llvmpipe is a CPU renderer: absolute frame numbers are pessimistic.
## Output is plain text tables on stdout; docs/perf/task-2-report.md is written from them.

const ViewModel = preload("res://view/model/view_model.gd")

var _frames := 600
var _warm := 30
var _world: SimWorld
var _host: Node
var _scene: Node
var _view: Node
var _art: Dictionary
var _tex_base := 0.0
var _vid_base := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _args() -> Dictionary:
	var m := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--"):
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				m[a[i].substr(2)] = a[i + 1]
				i += 1
			else:
				m[a[i].substr(2)] = "true"
		i += 1
	return m


static func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return float(sorted[mini(sorted.size() - 1, int(floor(p * float(sorted.size()))))])


static func _med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return _pct(s, 0.5)


static func _mean(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, float(a.size()))


func _mb(bytes: float) -> float:
	return bytes / 1048576.0


func _run() -> void:
	var args := _args()
	var seed_n := int(args.get("seed", 42))
	var sols := int(args.get("sols", 300))
	_frames = int(args.get("frames", 600))
	_warm = int(args.get("warmup", 30))
	var speed_frames := int(args.get("speed-frames", 120))
	_art = SimData.load_json("art.json")
	var size := Vector2i(int(_art.shots.width_px), int(_art.shots.height_px))
	root.size = size
	get_root().get_window().size = size
	print("perf_run: renderer %s, adapter %s, seed %d, %d frames per scenario, viewport %dx%d" % [
			RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(), seed_n,
			_frames, size.x, size.y])
	print("perf_run: godot %s, cpus %d" % [Engine.get_version_info().string, OS.get_processor_count()])

	var t0 := Time.get_ticks_msec()
	_world = SimWorld.new(seed_n)
	while _world.sol() < sols:
		_world.step()
	print("perf_run: world built to sol %d in %.1f s (%d steps)" % [_world.sol(), (Time.get_ticks_msec() - t0) / 1000.0,
			_world.step_index])
	_world_facts()
	_texture_budget()

	await process_frame
	await RenderingServer.frame_post_draw
	_tex_base = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	_vid_base = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)

	_host = root.get_node_or_null("Sim")
	_scene = (load("res://view/main.tscn") as PackedScene).instantiate()
	if _host != null:
		_host.speed = 0.0
		_host.world = _world
		root.add_child(_scene)
	else:
		root.add_child(_scene)
		_scene.setup(_world)
	_view = _scene.get_node("WorldLayer/WorldView")
	_scene.apply_shot_view({"select": "habitat", "peek": true})
	_view.settle_view(1.0)  # the roof is fully open and the doors have eased
	var open_b := _selected_building()
	print("perf_run: open roof: building %d (%s)" % [open_b.id, open_b.kind])

	var rows: Array = []
	var colony := _colony_center()
	var open_c := _building_center(open_b)
	for phase in ["day", "night"]:
		_goto_hour(12.0 if phase == "day" else 0.0)
		for z in [0.6, 2.0, 6.0]:
			_scene.set_camera(z, colony if z < 1.0 else open_c)
			rows.append(await _scenario(phase, z))
	_print_rows(rows)
	if args.has("probe"):
		await _layer_probe(colony, open_c, int(args.get("probe-frames", 60)))

	await _sim_stepping_model(open_c)
	if speed_frames > 0:
		await _speed_1000(speed_frames, open_c)
	quit(0)


func _selected_building() -> Buildings.Building:
	return _world.buildings.get_building(_view.vm.selection.selected)


func _building_center(b: Buildings.Building) -> Vector2:
	var tile := float(SimData.buildings().tile_px)
	return Rect2(b.tx * tile, b.ty * tile, b.tw * tile, b.th * tile).get_center()


func _colony_center() -> Vector2:
	var union := Rect2()
	for i in _world.buildings.list.size():
		var b: Buildings.Building = _world.buildings.list[i]
		var r := Rect2(_building_center(b) - Vector2(1, 1), Vector2(2, 2))
		union = r if i == 0 else union.merge(r)
	return union.get_center()


func _goto_hour(h: float) -> void:
	var guard := int(_world.clock.sol_h / _world.fixed_step) + 2
	while guard > 0 and absf(fposmod(_world.clock.mars_hour(_world.t) - h + 12.0, 24.0) - 12.0) > _world.fixed_step * 0.5:
		_world.step()
		guard -= 1
	print("perf_run: sim at sol %d, mars hour %.2f" % [_world.sol(), _world.clock.mars_hour(_world.t)])


func _world_facts() -> void:
	var outside := 0
	var inside_working := 0
	var states := {}
	for g in _world.beings:
		if g.is_outside():
			outside += 1
		states[g.state] = int(states.get(g.state, 0)) + 1
	print("world: sol %d, population %d (beings %d), outside %d, buildings %d, footprints %d, deaths %s" % [
			_world.sol(), _world.colony.pop(), _world.beings.size(), outside, _world.buildings.list.size(),
			_world.resources.footprints.size(), JSON.stringify(_world.stats.deaths)])
	print("world: being states %s" % JSON.stringify(states))


func _texture_budget() -> void:
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/processed/manifest.json"))
	var real := 0.0
	var withfile := 0.0
	var n_real := 0
	var n_ph := 0
	for id in man.entries:
		var e: Dictionary = man.entries[id]
		if e.get("file") != null:
			var b := float(e.w) * float(e.h) * 4.0
			withfile += b
			if e.get("placeholder", false):
				n_ph += 1
			else:
				real += b
				n_real += 1
	var k := float(_art.perf.mipmap_overhead)
	print("texture manifest: %d real entries %.2f MB, with %d placeholder files %.2f MB (x%.2f mipmaps; limit %s MB)" % [
			n_real, _mb(real * k), n_ph, _mb(withfile * k), k, str(_art.perf.texture_memory_mb_max)])


## One scenario: model update timing (sim paused), then live frames in the real renderer.
func _scenario(phase: String, zoom: float) -> Dictionary:
	var vm: ViewModel = _view.vm
	var dt := 1.0 / 60.0
	for i in _warm:
		await RenderingServer.frame_post_draw
	# 1. model update alone, camera rect set as the view does, sim paused.
	var upd: Array = []
	vm.camera_rect = _view._view_rect(_view._viewport_size())
	for i in _warm:
		vm.update(dt)
	for i in _frames:
		var t0 := Time.get_ticks_usec()
		vm.update(dt)
		upd.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	# 2. live frames.
	var calls: Array = []
	var nodes: Array = []
	var proc: Array = []
	var rcpu: Array = []
	var rgpu: Array = []
	var wall: Array = []
	var tex: Array = []
	var last := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	last = Time.get_ticks_usec()
	for i in _frames:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append(float(now - last) / 1000.0)
		last = now
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		nodes.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		tex.append(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
		var rid := root.get_viewport_rid()
		rcpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		rgpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	var us := upd.duplicate()
	us.sort()
	var cs := calls.duplicate()
	cs.sort()
	var ws := wall.duplicate()
	ws.sort()
	var outside := 0
	var interior_beings := 0
	for g in _world.beings:
		if g.is_outside():
			outside += 1
	for b in _world.buildings.list:
		var it = vm.interior(b.id)
		if it != null:
			interior_beings += 1
	var r := {
		"phase": phase, "zoom": zoom, "pop": _world.colony.pop(), "outside": outside,
		"open_interiors": interior_beings, "skipped": int(vm.skipped), "hour": _world.clock.mars_hour(_world.t),
		"upd_med": _pct(us, 0.5), "upd_p95": _pct(us, 0.95), "upd_max": float(us[us.size() - 1]), "upd_mean": _mean(upd),
		"calls_med": _pct(cs, 0.5), "calls_max": float(cs[cs.size() - 1]), "calls_min": float(cs[0]),
		"nodes_med": _med(nodes), "nodes_max": float(nodes.max()),
		"proc_med": _med(proc), "rcpu_med": _med(rcpu), "rgpu_med": _med(rgpu),
		"wall_med": _pct(ws, 0.5), "wall_p95": _pct(ws, 0.95), "wall_mean": _mean(wall),
		"tex_mb": _mb(_med(tex)),
	}
	print("scenario %s zoom %.1f: update median %.3f p95 %.3f max %.3f ms | calls %d | nodes %d | process %.2f ms | render cpu %.2f gpu %.2f ms | wall %.2f ms (p95 %.2f) | tex %.1f MB" % [
			phase, zoom, r.upd_med, r.upd_p95, r.upd_max, int(r.calls_med), int(r.nodes_med), r.proc_med, r.rcpu_med,
			r.rgpu_med, r.wall_med, r.wall_p95, r.tex_mb])
	return r


func _print_rows(rows: Array) -> void:
	print("")
	print("| scenario | pop | outside | model median ms | model p95 ms | model max ms | draw calls med (min-max) | nodes | process ms | render cpu ms | frame wall ms med (p95) | RENDER_TEXTURE_MEM_USED MB |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		print("| %s zoom %.1f | %d | %d | %.3f | %.3f | %.3f | %d (%d-%d) | %d | %.2f | %.2f | %.1f (%.1f) | %.1f |" % [
				r.phase, r.zoom, r.pop, r.outside, r.upd_med, r.upd_p95, r.upd_max, int(r.calls_med), int(r.calls_min),
				int(r.calls_max), int(r.nodes_max), r.proc_med, r.rcpu_med, r.wall_med, r.wall_p95, r.tex_mb])
	print("texture memory baseline before the scene (engine, root viewport): %.1f MB texture, %.1f MB video; delta of the view at its largest scenario: %.1f MB" % [
			_mb(_tex_base), _mb(_vid_base), float(rows.map(func(x): return x.tex_mb).max()) - _mb(_tex_base)])


## Per-layer cost probe (--probe): hides one world layer at a time and prints draw calls and wall ms per frame, at
## zoom 0.6 and 2 at the current hour (so run it with the hour you care about; it uses the last scenario's hour).
func _layer_probe(colony: Vector2, open_c: Vector2, frames: int) -> void:
	for z in [0.6, 2.0]:
		_scene.set_camera(z, colony if z < 1.0 else open_c)
		var hidden := ""
		var ids: Array = [""]
		ids.append_array(_view.layers.keys())
		for id in ids:
			if id != "":
				_view.layers[id].visible = false
			for i in 10:
				await RenderingServer.frame_post_draw
			var calls: Array = []
			var wall: Array = []
			var last := Time.get_ticks_usec()
			for i in frames:
				await RenderingServer.frame_post_draw
				var now := Time.get_ticks_usec()
				wall.append(float(now - last) / 1000.0)
				last = now
				calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			print("probe zoom %.1f hidden %-10s: draw calls %d, frame wall median %.2f ms" % [z, id if id != "" else "(none)", int(_med(calls)), _med(wall)])
			if id != "":
				_view.layers[id].visible = true


## Model refresh while the sim steps at 1x (20 steps per sol hour, so one step every third 60 Hz frame).
func _sim_stepping_model(center: Vector2) -> void:
	_scene.set_camera(2.0, center)
	var vm: ViewModel = _view.vm
	var hps := 1.0 / float(SimData.sim().real_seconds_per_hour_at_1x)
	var dt := 1.0 / 60.0
	var upd: Array = []
	var adv: Array = []
	vm.camera_rect = _view._view_rect(_view._viewport_size())
	for i in _frames:
		var a0 := Time.get_ticks_usec()
		_world.advance(dt * hps)
		adv.append(float(Time.get_ticks_usec() - a0) / 1000.0)
		var t0 := Time.get_ticks_usec()
		vm.update(dt)
		upd.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var us := upd.duplicate()
	us.sort()
	var asd := adv.duplicate()
	asd.sort()
	print("sim stepping at 1x, zoom 2, %d frames at dt 1/60: model update median %.3f p95 %.3f max %.3f ms; world.advance median %.3f p95 %.3f max %.3f ms" % [
			_frames, _pct(us, 0.5), _pct(us, 0.95), us[us.size() - 1], _pct(asd, 0.5), _pct(asd, 0.95), asd[asd.size() - 1]])


## 1000x with the view attached: world.advance every real frame with the real frame delta (as sim_host does), the view
## live in the same frames.
func _speed_1000(frames: int, center: Vector2) -> void:
	_scene.set_camera(2.0, center)
	var hps := 1.0 / float(SimData.sim().real_seconds_per_hour_at_1x)
	var cap := _world.max_steps_per_advance
	var steps_a: Array = []
	var adv: Array = []
	var upd_frame: Array = []
	var wall: Array = []
	var capped := 0
	var dropped_h := 0.0
	var step0 := _world.step_index
	var t_start := Time.get_ticks_usec()
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var delta := float(now - last) / 1e6
		last = now
		var a0 := Time.get_ticks_usec()
		var n := _world.advance(delta * 1000.0 * hps)
		adv.append(float(Time.get_ticks_usec() - a0) / 1000.0)
		steps_a.append(n)
		if n >= cap:
			capped += 1
			dropped_h += maxf(0.0, delta * 1000.0 * hps - float(n) * _world.fixed_step)
		wall.append(delta * 1000.0)
	var asd := adv.duplicate()
	asd.sort()
	var ws := wall.duplicate()
	ws.sort()
	var total_s := float(Time.get_ticks_usec() - t_start) / 1e6
	var steps_total := _world.step_index - step0
	var per_step: Array = []
	for i in adv.size():
		if steps_a[i] > 0:
			per_step.append(adv[i] / float(steps_a[i]))
	print("1000x, view attached, zoom 2, %d frames over %.2f s: cap max_steps_per_frame %d; advance steps per frame median %d max %d; cap hit in %d of %d frames; sim hours dropped by the cap %.1f; advance() ms median %.2f p95 %.2f max %.2f; ms per step median %.3f; frame wall median %.1f ms; total steps %d (%.0f steps/s, %.1f sim hours per real second against %.0f requested)" % [
			frames, total_s, cap, int(_med(steps_a)), int(steps_a.max()), capped, frames, dropped_h, _pct(asd, 0.5),
			_pct(asd, 0.95), asd[asd.size() - 1], _med(per_step), _pct(ws, 0.5), steps_total, steps_total / total_s,
			float(steps_total) * _world.fixed_step / total_s, 1000.0 * hps])
	# What a 60 Hz machine would ask per frame: 1000 x hps / 60 hours = N steps against the cap.
	var want := int(ceil(1000.0 * hps / 60.0 / _world.fixed_step))
	print("1000x at a steady 60 Hz would ask %d steps per frame against the cap %d" % [want, cap])
	var sp: Array = []
	for i in 60:
		var a0 := Time.get_ticks_usec()
		_world.advance(1.0 / 60.0 * 1000.0 * hps)
		sp.append(float(Time.get_ticks_usec() - a0) / 1000.0)
	var ss := sp.duplicate()
	ss.sort()
	print("1000x advance() at a fixed 1/60 s delta (view idle between calls), 60 calls: median %.2f p95 %.2f max %.2f ms" % [
			_pct(ss, 0.5), _pct(ss, 0.95), ss[ss.size() - 1]])
