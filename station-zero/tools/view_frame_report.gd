extends SceneTree
## Task 4 step 8: the view-step frame measurement (docs/specs/relationships.md section 13, "View-step frame measurement").
## Needs a real renderer, never --headless:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
##     --script res://tools/view_frame_report.gd -- [--seed 42] [--pop 120] [--frames 600] [--warmup 60]
## Builds the seed world (module on, shipped data) until the population is above --pop, attaches res://view/main.tscn with the
## real autoload host (the host's own _process calls world.advance, as in the game), opens one roof, and per condition
## holds --frames frames (at least 300 by the spec):
##   a  pop above 120, camera still, 1x
##   b  pop above 120, camera panning and zooming continuously, 1x
##   c  pop above 120, fastest speed (1000x), after a warmup
##   d  catch-up: the game has no separate long-absence path, so this is the fastest speed right after an unpause
## Per frame: wall ms between consecutive frame_post_draw (process + render, llvmpipe is a CPU renderer: pessimistic),
## the sim steps the host ran in it and whether a relationships tick ran in it (`relationships.ticks` moved). Output is
## plain text; docs/perf/task-4-frame-report.md is written from it. Read-only on the sim: the host steps, this tool never does
## after the world is built.

var _world: SimWorld
var _host: Node
var _scene: Node
var _view: Node


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


static func _sorted(a: Array) -> Array:
	var s := a.duplicate()
	s.sort()
	return s


func _run() -> void:
	var args := _args()
	var seed_n := int(args.get("seed", 42))
	var pop_min := int(args.get("pop", 120))
	var frames := int(args.get("frames", 600))
	var warm := int(args.get("warmup", 60))
	var art: Dictionary = SimData.load_json("art.json")
	var size := Vector2i(int(art.shots.width_px), int(art.shots.height_px))
	root.size = size
	get_root().get_window().size = size
	print("frame_report: renderer %s, adapter %s, seed %d, godot %s, cpus %d" % [
			RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name(), seed_n,
			Engine.get_version_info().string, OS.get_processor_count()])
	print("frame_report: viewport %dx%d, %d frames per condition, warmup %d" % [size.x, size.y, frames, warm])

	var t0 := Time.get_ticks_msec()
	_world = SimWorld.new(seed_n)
	while _world.colony.pop() <= pop_min and _world.sol() < 400:
		_world.step()
	print("frame_report: world built to sol %d, pop %d, %d steps, %d stored pairs, in %.1f s" % [_world.sol(),
			_world.colony.pop(), _world.step_index, _world.relationships.pairs.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	print("frame_report: relationships_enabled %s, advance_budget_ms %s, tick_h %s" % [str(_world.relationships_enabled),
			str(_world.advance_budget_ms), str(SimData.relationships().tick_h)])

	await process_frame
	_host = root.get_node_or_null("Sim")
	_scene = (load("res://view/main.tscn") as PackedScene).instantiate()
	if _host == null:
		print("frame_report: no Sim autoload; cannot measure the host path")
		quit(1)
		return
	_host.speed = 0.0
	_host.world = _world
	_host.set_process(false)
	root.add_child(_scene)
	_view = _scene.get_node("WorldLayer/WorldView")
	_scene.apply_shot_view({"select": "habitat", "peek": true})
	_view.settle_view(1.0)
	var open_b: Buildings.Building = _world.buildings.get_building(_view.vm.selection.selected)
	var tile := float(SimData.buildings().tile_px)
	var open_c := Rect2(open_b.tx * tile, open_b.ty * tile, open_b.tw * tile, open_b.th * tile).get_center()
	var colony := _colony_center()
	print("frame_report: open roof: building %d (%s), pop %d at start of measurement" % [open_b.id, open_b.kind,
			_world.colony.pop()])

	var rows: Array = []
	# a: camera still, 1x.
	_scene.set_camera(2.0, open_c)
	_host.speed = 1.0
	await _hold(warm, "")
	rows.append(await _hold(frames, "a  pop>%d, camera still, 1x" % pop_min))
	# b: camera panning and zooming continuously, 1x.
	rows.append(await _hold(frames, "b  pop>%d, camera panning and zooming, 1x" % pop_min, "pan", open_c, colony))
	# c: fastest speed, steady (after a warmup).
	_scene.set_camera(2.0, open_c)
	_host.speed = 1000.0
	await _hold(warm, "")
	rows.append(await _hold(frames, "c  pop>%d, camera still, 1000x (steady)" % pop_min))
	# d: catch-up = fastest speed right after an unpause (no separate long-absence path in the game).
	_host.speed = 0.0
	await _hold(warm, "")
	_host.speed = 1000.0
	rows.append(await _hold(frames, "d  pop>%d, camera still, 1000x right after an unpause (catch-up)" % pop_min))
	_print_rows(rows)
	quit(0)


func _colony_center() -> Vector2:
	var union := Rect2()
	var tile := float(SimData.buildings().tile_px)
	for i in _world.buildings.list.size():
		var b: Buildings.Building = _world.buildings.list[i]
		var r := Rect2(Vector2(b.tx * tile, b.ty * tile) + Vector2(b.tw * tile, b.th * tile) * 0.5 - Vector2(1, 1), Vector2(2, 2))
		union = r if i == 0 else union.merge(r)
	return union.get_center()


## Holds n frames and returns the condition's row. `mode` "pan" moves the camera every frame (sine pan over the colony
## and a zoom swing between 0.6 and 6, one slow loop per 300 frames).
func _hold(n: int, label: String, mode := "", a := Vector2.ZERO, b := Vector2.ZERO) -> Dictionary:
	var rel: Relationships = _world.relationships
	var tick_ms: Array = []
	var frames_tick: Array = []
	var frames_plain: Array = []
	var proc_tick: Array = []
	var proc_plain: Array = []
	var steps_tick: Array = []
	var steps_plain: Array = []
	var pairs: Array = []
	await RenderingServer.frame_post_draw
	var last := Time.get_ticks_usec()
	var last_ticks := rel.ticks
	var last_step := _world.step_index
	var hps := 1.0 / float(SimData.sim().real_seconds_per_hour_at_1x)
	var prev_delta := 1.0 / 60.0
	var last_dropped := _world.advance_dropped_h
	var dropped0 := last_dropped
	for i in n:
		if mode == "pan":
			var ph := float(i) / 300.0 * TAU
			var zoom := exp(lerpf(log(0.6), log(6.0), 0.5 + 0.5 * sin(ph)))
			_scene.set_camera(zoom, a.lerp(b, 0.5 + 0.5 * sin(ph * 0.7)))
		# The host's own _process is switched off for the run and replaced by this identical call (delta x speed x hours per
		# second into world.advance), so the sim's share of the frame is timed on its own.
		var a0 := Time.get_ticks_usec()
		_world.advance(prev_delta * float(_host.speed) * hps)
		var adv_ms := float(Time.get_ticks_usec() - a0) / 1000.0
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		prev_delta = float(now - last) / 1e6
		var ms := float(now - last) / 1000.0
		last = now
		var dt: int = rel.ticks - last_ticks
		var ds: int = _world.step_index - last_step
		last_ticks = rel.ticks
		last_step = _world.step_index
		var proc := adv_ms
		if dt > 0:
			proc_tick.append(proc)
			frames_tick.append(ms)
			steps_tick.append(ds)
			tick_ms.append(rel.last_tick_ms)
		else:
			proc_plain.append(proc)
			frames_plain.append(ms)
			steps_plain.append(ds)
		pairs.append(rel.pairs.size())
	if label == "":
		return {}
	return {"label": label, "n": n, "tick": _sorted(frames_tick), "plain": _sorted(frames_plain), "tick_ms": _sorted(tick_ms), "ptick": _sorted(proc_tick), "pplain": _sorted(proc_plain),
			"steps_tick": steps_tick, "steps_plain": steps_plain, "pairs": _sorted(pairs), "pop": _world.colony.pop(),
			"dropped_h": _world.advance_dropped_h - dropped0}


static func _mean_i(a: Array) -> float:
	var t := 0.0
	for v in a:
		t += float(v)
	return t / maxf(1.0, float(a.size()))


func _print_rows(rows: Array) -> void:
	print("")
	print("| condition | frames (tick / plain) | tick frames p95 / max ms | plain frames p95 / max ms | steps per frame (tick / plain, mean) | tick median / max ms | stored pairs median (min-max) | pop | sim hours dropped |")
	print("|---|---|---|---|---|---|---|---|---|")
	for r in rows:
		var t: Array = r.tick
		var p: Array = r.plain
		var tp := "n/a" if t.is_empty() else "%.1f / %.1f" % [_pct(t, 0.95), float(t[t.size() - 1])]
		var pp := "n/a" if p.is_empty() else "%.1f / %.1f" % [_pct(p, 0.95), float(p[p.size() - 1])]
		var tk: Array = r.tick_ms
		var tkm := "n/a" if tk.is_empty() else "%.2f / %.2f" % [_pct(tk, 0.5), float(tk[tk.size() - 1])]
		var pr: Array = r.pairs
		print("| %s | %d (%d / %d) | %s | %s | %.1f / %.1f | %s | %d (%d-%d) | %d | %.1f |" % [r.label, r.n, t.size(), p.size(), tp, pp,
				_mean_i(r.steps_tick), _mean_i(r.steps_plain), tkm, int(_pct(pr, 0.5)), int(pr[0]), int(pr[pr.size() - 1]),
				r.pop, r.dropped_h])
	print("")
	print("| condition | advance() ms (the sim's share, no render) tick frames p95 / max | plain frames p95 / max |")
	print("|---|---|---|")
	for r in rows:
		var t: Array = r.ptick
		var p: Array = r.pplain
		print("| %s | %s | %s |" % [r.label, "n/a" if t.is_empty() else "%.1f / %.1f" % [_pct(t, 0.95), float(t[t.size() - 1])],
				"n/a" if p.is_empty() else "%.1f / %.1f" % [_pct(p, 0.95), float(p[p.size() - 1])]])
	# Trigger verdicts (3a: tick-frame p95 over 16.7 ms with plain-frame p95 under 16.7; 3b: a tick frame over 33 ms with the
	# plain-frame max under 33). 16.7 and 33 are the spec's thresholds (relationships.md section 13), used here only to judge.
	print("")
	for r in rows:
		_verdict("wall", r, r.tick, r.plain)
	for r in rows:
		_verdict("advance ms", r, r.ptick, r.pplain)


func _verdict(kind: String, r: Dictionary, t: Array, p: Array) -> void:
	var p95_t := _pct(t, 0.95)
	var p95_p := _pct(p, 0.95)
	var max_t := 0.0 if t.is_empty() else float(t[t.size() - 1])
	var max_p := 0.0 if p.is_empty() else float(p[p.size() - 1])
	print("verdict (%s) %s: 3a tick p95 %.1f vs plain p95 %.1f -> %s; 3b tick max %.1f vs plain max %.1f -> %s" % [kind,
			String(r.label).substr(0, 1), p95_t, p95_p, "TRIPS" if (not t.is_empty() and p95_t > 16.7 and p95_p < 16.7) else "no",
			max_t, max_p, "TRIPS" if (max_t > 33.0 and max_p < 33.0) else "no"])
