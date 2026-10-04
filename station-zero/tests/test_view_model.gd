extends RefCounted
## Task 2, step 10: the view model (no drawing). Spec: docs/specs/sprite-view.md sections 4 to 7 and 9, test list
## "View model (Godot, tests/test_view_model.gd)" (T-F1 .. T-PERF), plan docs/tasks/task-2-plan.md step 10.
##
## Architecture under test: animation state lives only in res://view/model/ (RefCounted, no Node, no drawing). It
## reads the sim and never writes it, and it uses its own RandomNumberGenerator, never SimRng. Every script is loaded
## with load() (as tests/balance_lib.gd is), so a missing or unparsable file fails one test cleanly ("missing or
## unparsable ...") instead of aborting the suite. Numbers come from data/art.json (SimData.load_json("art.json"),
## the top-level keys are the groups: art.fit is the key "fit") and the real assets/processed/manifest.json (parsed
## here as plain JSON; the parallel ArtLibrary is not used).
##
## API ASSUMED (names are the contract the godot-engineer implements; `art` is the art.json Dictionary, `man` the
## manifest Dictionary {"schema", "entries": {id: {w, h, pivot, placeholder, file, ...}}}). Files are in view/model/:
##  fit.gd (static)
##   fit_sprite(footprint: Rect2, sprite_size: Vector2, pivot_norm: Vector2, art) -> {rect: Rect2, scale: float,
##     door: Vector2}   door = where the pivot lands (bottom edge centre, shifted only by the inside clamp).
##  light.gd (static; h = Mars hour)
##   night(h, art) N; daylight(h, art) L; dusk(h, art); tint_alphas(h, art) -> {day, dusk, night} (final alphas);
##   shadow_dx(h, art); lamp_target(h, outside: bool, lamp_on: bool, art) -> float;
##   lamp_glow(suit_kind: String, level: float, art) -> {on: bool, outer_alpha, core_alpha, ground_alpha};
##   pulse(real_time, building_id, kind, art) -> 0..1; accent_alpha(h, pulse, vis, art); window_alpha(h, vis, art).
##  facing_pose.gd (static)
##   facing(heading_rad, art) -> {dir: "front"|"back"|"side", mirror: bool}; facing_vec(v: Vector2, art) (same);
##   transit_facing(p1, p2, from_a: bool, art) (direction p1->p2 if from_a else p2->p1);
##   walk_frame(phase, art) -> int 0..3 = floor(phase / TAU x frames) mod 4;
##   resolve_frame(sheet: "jumpsuit"|"eva"|"construction", frame: String, art) -> frame name, "idle_front" if the
##     sheet lacks it (construction has no idle_side);
##   height_px(earth_born: bool, interior: bool, art) -> world px (7.6, x1.1 Mars-born, x1.9 interior);
##   pose_frame(d: Dictionary, art, man) -> {sheet: manifest id, frame: String, mirror: bool, rotate_deg: float}
##     d keys: state, suit_kind, role, id, load, wait_h, after, returning, moving, facing {dir, mirror}, face (+1/-1,
##     the last horizontal sign), real_time, walk_frame (int k), talking (interior pause next to another being),
##     speaks_first (lower id). sheet ids: "character.jumpsuit.<role>", "character.eva", "character.construction",
##     "character.sleeping.<role>.<id mod 4>" (only when that manifest entry is real: placeholder false). Weld frame
##     = weld_1 when floor(real_time x 2 x weld_hz) is even, else weld_2; dig the same with "dig"/"idle_side" at dig_hz;
##     talk = "talk" when floor(real_time / talk_phase_s) is even for the one who speaks first, else "idle_front".
##  being_anim.gd (instance; one per being)
##   new(art, id); push_sample(pos: Vector2, real_time) once per refresh (the first sample sets both samples);
##   phase: float (rad); moving_at(real_time) -> bool; frame_index() -> int; render_pos(real_time) -> Vector2
##   (lerp from the previous to the newest sample: alpha = clamp((rt - t_new) / clamp(t_new - t_old, 0.016, 0.5),
##   0, 1), so it holds the newest sample once nothing new arrives); lamp_level: float; update_lamp(dt, target).
##  doors.gd (static)
##   want_open(b: Buildings.Building, beings: Array[Being], tile_px, art) -> bool; ease_open(open, want: bool, dt, art);
##   leaf_offsets(open, mode: "split"|"rollup", door_size: Vector2, art) -> split {left: Vector2, right: Vector2,
##   clip: Rect2}, rollup {panel: Vector2, clip: Rect2}; clip = Rect2(Vector2.ZERO, door_size).
##  building_anim.gd (instance; one per building)
##   new(art, id, kind); update(dt_real, want_door: bool, offline: bool); door_open: float; power: float;
##   lights(h, real_time, cut) -> {accent, windows, strip, door_glow, dim} (final alphas, vis = 1 - cut).
##  construction.gd (static)
##   phases(built, art) -> {p, f, g, sa}; corridor_frac(built, art); draw_list(built, rect: Rect2, art) ->
##   Array[{layer: "stakes"|"ghost"|"tunnel"|"slab"|"gray"|"paint"|"scaffold", clip_top: float (gray, paint; the
##   unpadded y)}]; empty when built >= 1.
##  particles.gd (instance)
##   new(art, seed_salt: int); update(dt_real, sources: Array[Dictionary]); count() -> int (live); dropped: int;
##   emitted(key) -> int and emitted_kind(kind) -> int (accumulator emissions, accepted plus dropped);
##   snapshot() -> Array[{kind, x, y, vx, vy, life, max_life}] (life = remaining; a particle emitted by an update call
##   is not aged in that call). Sources: {key, kind: "weld_hand"|"dig", feet: Vector2, face: int, scale: float,
##   ice: bool}; {key, kind: "weld_seam", rect: Rect2 (sprite rect), f: float, crew: int}; {key, kind: "flicker",
##   rect: Rect2 (footprint)}. A source present in the array this call emits; dt is clamped to door.max_dt_s.
##  footprints.gd (static)
##   age_of(fp: Resources.Footprint, world: SimWorld) -> float; alpha(age, heavy, art) -> float (0 at age >= 1);
##   drawn(world, rect: Rect2, art) -> Array[{x, y, heading, alpha, heavy}].
##  zsort.gd (static)
##   layer(e: Dictionary) -> String ("L4" for a being in state transit, else "L6"); sorted(entities) -> Array of the L6 entities
##   in draw order. Entity: {type: "building"|"being", id, base_y, state, built, rect: Rect2 (building footprint),
##   pos: Vector2 (being feet)}.
##  interior_slots.gd (instance; one per open building)
##   new(art, building_id, kind, size_px: Vector2); update(dt_real, inside: Array[{id, state, suit_up}]);
##   drawn_ids() -> Array (ascending); positions() -> {id: Vector2 normalized to the interior image};
##   slot_of(id) -> {id, type} or {}; slots() -> Array (the slots of art.interiors.<kind> or .default).
##  selection.gd (instance)
##   new(art); selected: int (0 none); peek: bool; peek_cut: float; tap(world_pt: Vector2, world: SimWorld);
##   is_tap(press: Vector2, release: Vector2) -> bool (screen px); update(dt_real, zoom, world); cut(building_id, zoom)
##   -> float; static zoom_cut(zoom, art); static outline_source(cut, art) -> "exterior"|"interior";
##   static pulse(real_time, art).
##  camera.gd (instance)
##   new(art, footprint_union: Rect2); zoom; center: Vector2; follow: bool; follow_target: Vector2; bounds() -> Rect2
##   (union grown by pan_margin_px); screen_to_world(p, viewport) = center + (p - viewport/2) / zoom;
##   wheel(notches: int, cursor: Vector2, viewport: Vector2); zoom_key(dir: int, dt); pan(screen_dir: Vector2, dt);
##   reset(centroid: Vector2); update(dt); follow_done() -> bool; action_for_key(key_name) -> String ("" if none).
##  view_model.gd (instance, the facade)
##   new(world: SimWorld, art, man); update(dt_real) (one refresh; reads the sim, writes only view state);
##   real_time: float; camera: camera.gd; selection: selection.gd; particles: particles.gd; debug_map: bool;
##   press_key(key_name); camera_rect: Rect2 (culls interiors; the default Rect2() means no culling); skipped: int;
##   building(id) -> building_anim.gd; being(id) -> {pos: Vector2 (feet, render position), height_px, phase, moving,
##   lamp_level, visible, inside}; interior(building_id) -> interior_slots.gd or null (non-null while cut > 0 and the
##   building is inside camera_rect); signature() -> String (hash of all view state, for equality checks).
##
## Spec slips found while writing these tests (also in the report): T-A1 says the night accent maximum is 0.83 but the
## 5.3 formula gives 1.05 at N = 1 (the test asserts 1.05); T-C2 asks for "7 irregular frames" over 10 s although dt is
## clamped to 0.1 s (the test uses frames of at most 0.1 s and tests the clamp separately); 7.3 says no two beings share a
## slot but allows 25 beings while a kind has 6 or 15 slots (no-sharing is tested up to the slot count); 5.5 says the
## clip rect is padded 2 px while T-C1 gives the unpadded clip top (the test asserts the unpadded value, the pad is a
## draw detail); T-DATA says "view/**" but the existing HUD scripts (view/main.gd, debug_map.gd) contain literals, so the
## literal scan covers view/model/ only; T-PERF node count, pool overflow and draw calls need the world view (steps 11+).

const VM_DIR := "res://view/model/"
const SPEC_PATH := "res://docs/specs/sprite-view.md"
## T-DATA literal scan: numbers other than 0, 1, 2 and array indices that view/model may contain (spec formulas use
## "half" and "60 Hz frame"; nothing else may be hard-coded).
const LITERAL_EXCEPTIONS := ["0.5", "60.0"]
const KINDS := ["reactor", "habitat", "workshop", "green_room", "archive", "comms"]


# ---------------------------------------------------------------- helpers

func _art() -> Dictionary:
	return SimData.load_json("art.json")


func _manifest() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://assets/processed/manifest.json"))
	return m if m is Dictionary else {"schema": 1, "entries": {}}


## The real manifest with the 16 sleeping poses flipped to real entries (presence rule, spec 3.10).
func _manifest_sleeping_real() -> Dictionary:
	var m := _manifest().duplicate(true)
	for id in m.entries:
		if String(id).begins_with("character.sleeping."):
			m.entries[id]["placeholder"] = false
			m.entries[id]["file"] = "characters/sleeping_x.png"
			m.entries[id]["w"] = 160
			m.entries[id]["h"] = 160
	return m


## The real manifest with the 16 sleeping poses hidden (file null, placeholder): the rotated jumpsuit fallback.
func _manifest_sleeping_hidden() -> Dictionary:
	var m := _manifest().duplicate(true)
	for id in m.entries:
		if String(id).begins_with("character.sleeping."):
			m.entries[id]["placeholder"] = true
			m.entries[id]["file"] = null
	return m


## Loads every named view/model script; fails once and returns {} when one is missing or does not parse.
func _need(t, names: Array) -> Dictionary:
	var out := {}
	for n in names:
		var path: String = VM_DIR + String(n) + ".gd"
		var s: Variant = null
		if ResourceLoader.exists(path):
			s = load(path)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			t.check(false, "missing or unparsable " + path)
			return {}
		out[n] = s
	return out


func _world(seed_in: int = 1) -> SimWorld:
	return SimWorld.new(seed_in, {"blank": true})


func _outside(w: SimWorld, bid: int, x: float, y: float, state: String = "eva", earth: bool = true) -> Being:
	var b := w.add_being(bid, "builder")
	b.state = state
	b.x = x
	b.y = y
	b.heading = 0.0
	b.air_h = 30.0
	b.earth_born = earth
	return b


func _f(v: Variant) -> String:
	return "-" if v == null else String.num(float(v), 9)


## Everything the view must never change: time, step, rng state, stocks, beings, buildings, footprints, stats.
func _sig(w: SimWorld) -> String:
	var p: Array[String] = []
	p.append("%s|%d|%d|%d" % [_f(w.t), w.step_index, w.rng._rng.state, w.rng.seed_value])
	p.append("%s|%s|%s|%s" % [_f(w.colony.oxygen), _f(w.colony.food), _f(w.colony.ice), _f(w.colony.regolith)])
	for b in w.beings:
		p.append("b%d|%s|%d|%s|%s|%s|%s|%s|%s|%s|%d|%s" % [b.id, b.state, b.building_id, _f(b.x), _f(b.y),
				_f(b.heading), _f(b.energy), _f(b.wait_h), _f(b.load), _f(b.air_h), 1 if b.suit_up else 0,
				_f(b.transit_t)])
	for b in w.buildings.list:
		p.append("B%d|%s|%s|%d" % [b.id, b.kind, _f(b.built), 1 if b.offline else 0])
	p.append("fp%d" % w.resources.footprints.size())
	for f in w.resources.footprints:
		p.append("%s,%s,%s" % [_f(f.x), _f(f.y), _f(f.t)])
	for s in w.resources.ice_fields:
		p.append("i%s,%s,%s" % [_f(s.x), _f(s.y), _f(s.amount)])
	for s in w.resources.pits:
		p.append("p%s,%s,%s" % [_f(s.x), _f(s.y), _f(s.dug)])
	p.append(JSON.stringify(w.stats))
	p.append(str(w.log.size()))
	return "\n".join(p).sha256_text()


func _expected_frame(phase: float) -> int:
	return int(floor(phase / TAU * 4.0)) % 4


# ---------------------------------------------------------------- T-F1, T-F2: fit

func test_fit_f1_inside_footprint_bottom_anchored(t) -> void:
	var M := _need(t, ["fit"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	var eps := float(art.fit.epsilon_px)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 100:
		var tw := rng.randi_range(10, 14)
		var th := rng.randi_range(8, 10)
		var f := Rect2(rng.randi_range(-20, 60) * 8, rng.randi_range(-20, 60) * 8, tw * 8, th * 8)
		for k in KINDS:
			var e: Dictionary = man.entries["building.%s.base" % k]
			var size := Vector2(e.w, e.h)
			var piv := Vector2(e.pivot[0], e.pivot[1])
			var r: Dictionary = M.fit.fit_sprite(f, size, piv, art)
			var rect: Rect2 = r.rect
			var tag := "%s %dx%d" % [k, tw, th]
			t.check(rect.position.x >= f.position.x - eps and rect.end.x <= f.end.x + eps, tag + " inside x")
			t.check(rect.position.y >= f.position.y - eps and rect.end.y <= f.end.y + eps, tag + " inside y")
			t.near(rect.size.x / size.x, rect.size.y / size.y, 1e-5, tag + " one scale for both axes")
			t.near(float(r.scale), rect.size.x / size.x, 1e-5, tag + " scale value")
			t.near(rect.end.y, f.end.y, eps, tag + " bottom edge on the footprint bottom")
			var sim_door_x := f.position.x + f.size.x / 2.0
			t.check(absf(float(r.door.x) - sim_door_x) <= 0.01 * f.size.x + 1e-6, tag + " door x within the clamp")
			t.near(rect.position.x + piv.x * rect.size.x, float(r.door.x), eps, tag + " door is the pivot point")
	# The spec example: habitat 13x9 tiles, 384x244.
	var f2 := Rect2(80, 160, 104, 72)
	var h: Dictionary = M.fit.fit_sprite(f2, Vector2(384, 244), Vector2(0.5, 1.0), art)
	t.near(float(h.scale), 104.0 / 384.0, 1e-4, "habitat 13x9 scale 0.2708")
	t.near((h.rect as Rect2).size.x, 104.0, 0.1, "habitat drawn width 104")
	t.near((h.rect as Rect2).size.y, 66.0, 0.1, "habitat drawn height 66")
	t.near(f2.size.y - (h.rect as Rect2).size.y, 6.0, 0.1, "6 px of pad above")
	# A 10x10 footprint: width limited 80 x 51 (spec side effect 1).
	var sq: Dictionary = M.fit.fit_sprite(Rect2(0, 0, 80, 80), Vector2(384, 244), Vector2(0.5, 1.0), art)
	t.near((sq.rect as Rect2).size.x, 80.0, 0.1, "10x10 drawn width 80")
	t.near((sq.rect as Rect2).size.y, 50.8, 0.2, "10x10 drawn height about 51")
	# clamp_inside: a pivot far from the centre still leaves the sprite inside the footprint.
	var off: Dictionary = M.fit.fit_sprite(f2, Vector2(384, 244), Vector2(0.2, 1.0), art)
	var off_r: Rect2 = off.rect
	t.check(off_r.position.x >= f2.position.x - eps and off_r.end.x <= f2.end.x + eps, "off-centre pivot is clamped inside the footprint")
	# Interior fits inside the exterior sprite rect, pivot (door x, 1.0) at its bottom centre.
	var ie: Dictionary = man.entries["building.habitat.interior"]
	var ext: Rect2 = h.rect
	var inr: Dictionary = M.fit.fit_sprite(ext, Vector2(ie.w, ie.h), Vector2(ie.pivot[0], 1.0), art)
	var ir: Rect2 = inr.rect
	t.check(ir.position.x >= ext.position.x - eps and ir.end.x <= ext.end.x + eps, "interior inside exterior x")
	t.check(ir.position.y >= ext.position.y - eps and ir.end.y <= ext.end.y + eps, "interior inside exterior y")
	t.near(ir.end.y, ext.end.y, eps, "interior bottom on exterior bottom")
	t.near(ir.size.x / ir.size.y, float(ie.w) / float(ie.h), 1e-6, "interior not stretched")


func test_fit_f2_no_stretch(t) -> void:
	var M := _need(t, ["fit"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in 40:
		var f := Rect2(0, 0, rng.randi_range(10, 14) * 8, rng.randi_range(8, 10) * 8)
		for k in KINDS:
			var e: Dictionary = man.entries["building.%s.base" % k]
			var r: Dictionary = M.fit.fit_sprite(f, Vector2(e.w, e.h), Vector2(e.pivot[0], e.pivot[1]), art)
			var rect: Rect2 = r.rect
			t.near(rect.size.x / rect.size.y, float(e.w) / float(e.h), 1e-6, "%s aspect %s" % [k, str(f.size)])


# ---------------------------------------------------------------- T-FA: facing

func test_facing_fa(t) -> void:
	var M := _need(t, ["facing_pose"])
	if M.is_empty():
		return
	var art := _art()
	var fp = M.facing_pose
	var r0: Dictionary = fp.facing(0.0, art)
	t.eq(r0.dir, "side", "0 deg side")
	t.eq(r0.mirror, false, "0 deg not mirrored")
	t.eq(fp.facing(deg_to_rad(90.0), art).dir, "front", "90 deg front (y down)")
	var r180: Dictionary = fp.facing(deg_to_rad(180.0), art)
	t.eq(r180.dir, "side", "180 deg side")
	t.eq(r180.mirror, true, "180 deg mirrored")
	t.eq(fp.facing(deg_to_rad(270.0), art).dir, "back", "270 deg back")
	t.eq(fp.facing(deg_to_rad(60.0), art).dir, "front", "60 deg: |vy|/|vx| 1.73 > 1.25 is front")
	t.eq(fp.facing(deg_to_rad(45.0), art).dir, "side", "45 deg is side")
	t.eq(fp.facing(deg_to_rad(50.0), art).dir, "side", "50 deg: ratio 1.19 < 1.25 is side")
	t.eq(fp.facing(deg_to_rad(55.0), art).dir, "front", "55 deg: ratio 1.43 > 1.25 is front")
	t.eq(fp.facing(deg_to_rad(-45.0), art).dir, "side", "-45 deg is side")
	t.eq(fp.facing(deg_to_rad(135.0), art).mirror, true, "135 deg side mirrored")
	t.eq(fp.facing(deg_to_rad(-120.0), art).dir, "back", "-120 deg back")
	# Idle (not moving) uses the front pose.
	var d := {"state": "idle", "suit_kind": "none", "role": "social", "id": 3, "load": 0.0, "wait_h": 0.0,
			"after": null, "returning": false, "moving": false, "facing": {"dir": "side", "mirror": true},
			"face": -1, "real_time": 0.0, "walk_frame": 1, "talking": false, "speaks_first": true}
	var p: Dictionary = fp.pose_frame(d, art, _manifest())
	t.eq(p.frame, "idle_front", "idle uses front")
	# Tunnel transit: p1 -> p2 when from_a, else p2 -> p1.
	var a: Dictionary = fp.transit_facing(Vector2(0, 0), Vector2(40, 0), true, art)
	t.eq(a.dir, "side", "horizontal tunnel from_a is side")
	t.eq(a.mirror, false, "from_a walks right")
	var b: Dictionary = fp.transit_facing(Vector2(0, 0), Vector2(40, 0), false, art)
	t.eq(b.mirror, true, "not from_a walks left (mirrored)")
	t.eq(fp.transit_facing(Vector2(0, 0), Vector2(0, 40), true, art).dir, "front", "vertical from_a walks down: front")
	t.eq(fp.transit_facing(Vector2(0, 0), Vector2(0, 40), false, art).dir, "back", "vertical not from_a: back")


# ---------------------------------------------------------------- T-W1, T-W2: walk phase and interpolation

func test_walk_phase_w1(t) -> void:
	var M := _need(t, ["being_anim"])
	if M.is_empty():
		return
	var art := _art()
	var per_px := float(art.walk.phase_per_px)
	var cap := float(art.walk.max_advance_px_per_refresh)
	var rt := 0.0
	# 10 px and 30 px in one refresh both advance by 8 x 1.25 (clamped), moving stays true, frame follows the phase.
	for d in [10.0, 30.0, 8.0]:
		var a = M.being_anim.new(art, 1)
		a.push_sample(Vector2.ZERO, rt)
		a.push_sample(Vector2(d, 0), rt + 1.0 / 60.0)
		t.near(float(a.phase), cap * per_px, 1e-9, "%s px advances 10 rad" % str(d))
		t.check(a.moving_at(rt + 1.0 / 60.0), "%s px: moving stays true" % str(d))
		t.eq(a.frame_index(), _expected_frame(float(a.phase)), "%s px: frame from the phase, no special case" % str(d))
	var a2 = M.being_anim.new(art, 1)
	a2.push_sample(Vector2.ZERO, 0.0)
	a2.push_sample(Vector2(2, 0), 0.016)
	t.near(float(a2.phase), 2.5, 1e-9, "2 px advances 2.5")
	# Zero distance: zero advance, however many refreshes.
	var a3 = M.being_anim.new(art, 2)
	a3.push_sample(Vector2(5, 5), 0.0)
	for i in 100:
		a3.push_sample(Vector2(5, 5), 0.016 * (i + 1))
	t.eq(float(a3.phase), 0.0, "zero distance gives zero advance (never per frame)")
	# 6 px in one refresh or in 100 equal refreshes: the same phase, 7.5 rad.
	var one = M.being_anim.new(art, 3)
	one.push_sample(Vector2.ZERO, 0.0)
	one.push_sample(Vector2(6, 0), 0.016)
	var many = M.being_anim.new(art, 3)
	many.push_sample(Vector2.ZERO, 0.0)
	for i in 100:
		many.push_sample(Vector2(0.06 * (i + 1), 0), 0.016 * (i + 1))
	t.near(float(one.phase), 7.5, 1e-9, "6 px in 1 refresh: 7.5 rad")
	t.near(float(many.phase), 7.5, 1e-6, "6 px in 100 refreshes: 7.5 rad")
	# Simulated 1000x: 30 px per refresh for 100 refreshes, the frame index changes every refresh.
	var fast = M.being_anim.new(art, 4)
	fast.push_sample(Vector2.ZERO, 0.0)
	var prev := int(fast.frame_index())
	var changed := 0
	for i in 100:
		fast.push_sample(Vector2(30.0 * (i + 1), 0), (i + 1) / 60.0)
		var fi := int(fast.frame_index())
		if fi != prev:
			changed += 1
		prev = fi
		t.check(fast.moving_at((i + 1) / 60.0), "1000x: still moving at refresh %d" % i)
	t.eq(changed, 100, "1000x: frame index changes every refresh")
	t.near(float(fast.phase), 100.0 * cap * per_px, 1e-6, "1000x: phase is 100 clamped advances")
	# One cycle: 0.1 px steps cover frames 0, 1, 2, 3 in order, then wrap.
	var cyc = M.being_anim.new(art, 5)
	cyc.push_sample(Vector2.ZERO, 0.0)
	var seen: Array = []
	var x := 0.0
	for i in 60:
		x += 0.1
		cyc.push_sample(Vector2(x, 0), (i + 1) / 60.0)
		var fi := int(cyc.frame_index())
		t.between(float(fi), 0.0, 3.0, "frame index in 0..3")
		t.eq(fi, _expected_frame(per_px * x), "frame follows floor(phase / 2pi x 4) mod 4 at %.1f px" % x)
		if seen.is_empty() or seen[seen.size() - 1] != fi:
			seen.append(fi)
	t.eq(seen.slice(0, 5), [0, 1, 2, 3, 0], "frames cycle 0,1,2,3,0")
	# moving: a step of 0.004 px or more within the last 0.15 s of real time.
	var mv = M.being_anim.new(art, 6)
	mv.push_sample(Vector2.ZERO, 1.0)
	mv.push_sample(Vector2(0.003, 0), 1.02)
	t.check(not mv.moving_at(1.02), "0.003 px is below min_move_px")
	mv.push_sample(Vector2(1.0, 0), 1.04)
	t.check(mv.moving_at(1.04), "moved 1 px: moving")
	t.check(mv.moving_at(1.04 + 0.14), "still moving inside the 0.15 s hold")
	t.check(not mv.moving_at(1.04 + 0.2), "not moving after the 0.15 s hold")


func test_walk_interpolation_w2(t) -> void:
	var M := _need(t, ["being_anim"])
	if M.is_empty():
		return
	var art := _art()
	var a = M.being_anim.new(art, 1)
	a.push_sample(Vector2(0, 0), 0.0)
	a.push_sample(Vector2(10, 20), 0.1)
	var p: Vector2 = a.render_pos(0.1)
	t.near(p.x, 0.0, 1e-9, "at the new sample time the render is still the old sample (x)")
	t.near(p.y, 0.0, 1e-9, "same (y)")
	var mid: Vector2 = a.render_pos(0.15)
	t.near(mid.x, 5.0, 1e-9, "halfway over the 0.1 s between samples (x)")
	t.near(mid.y, 10.0, 1e-9, "halfway (y)")
	var end: Vector2 = a.render_pos(0.2)
	t.near(end.x, 10.0, 1e-9, "after the interval it is the newest sample")
	var held: Vector2 = a.render_pos(5.0)
	t.near(held.x, 10.0, 1e-9, "with no new sample it holds the last (x)")
	t.near(held.y, 20.0, 1e-9, "with no new sample it holds the last (y)")
	# Interval clamps to [0.016, 0.5].
	var b = M.being_anim.new(art, 2)
	b.push_sample(Vector2(0, 0), 0.0)
	b.push_sample(Vector2(16, 0), 0.001)
	t.near((b.render_pos(0.001 + 0.008) as Vector2).x, 8.0, 1e-9, "tiny gap clamps to 0.016 s")
	var c = M.being_anim.new(art, 3)
	c.push_sample(Vector2(0, 0), 0.0)
	c.push_sample(Vector2(10, 0), 5.0)
	t.near((c.render_pos(5.25) as Vector2).x, 5.0, 1e-9, "long gap clamps to 0.5 s")
	# A first sample shows at once.
	var d = M.being_anim.new(art, 4)
	d.push_sample(Vector2(7, 8), 3.0)
	t.near((d.render_pos(3.0) as Vector2).x, 7.0, 1e-9, "first sample is where the being is")


# ---------------------------------------------------------------- T-P1, T-P2: pose, scale

func _pose(M: Dictionary, art: Dictionary, man: Dictionary, over: Dictionary) -> Dictionary:
	var d := {"state": "idle", "suit_kind": "none", "role": "builder", "id": 1, "load": 0.0, "wait_h": 0.0,
			"after": null, "returning": false, "moving": false, "facing": {"dir": "front", "mirror": false},
			"face": 1, "real_time": 0.0, "walk_frame": 0, "talking": false, "speaks_first": true}
	d.merge(over, true)
	return M.facing_pose.pose_frame(d, art, man)


func test_pose_table_p1(t) -> void:
	var M := _need(t, ["facing_pose"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	var real_sleep := _manifest_sleeping_real()
	# Sleep: a real sleeping pose, unrotated; else idle_front rotated -90.
	var s1 := _pose(M, art, real_sleep, {"state": "sleep", "role": "social", "id": 6})
	t.eq(s1.sheet, "character.sleeping.social.2", "real sleeping pose: role social, id 6 mod 4 = 2")
	t.eq(float(s1.rotate_deg), 0.0, "real sleeping pose is not rotated")
	var s2 := _pose(M, art, real_sleep, {"state": "sleep", "role": "tender", "id": 7})
	t.eq(s2.sheet, "character.sleeping.tender.3", "id 7 mod 4 = 3")
	var odd := _manifest_sleeping_real()
	odd.entries["character.sleeping.social.2"]["placeholder"] = true
	var s4 := _pose(M, art, odd, {"state": "sleep", "role": "social", "id": 6})
	t.eq(s4.sheet, "character.jumpsuit.social", "a placeholder entry is not used even if it names a file")
	t.eq(float(s4.rotate_deg), float(art.colonist.sleeper_rotation_deg), "and the rotated fallback applies")
	var hidden := _manifest_sleeping_hidden()
	var s3 := _pose(M, art, hidden, {"state": "sleep", "role": "builder", "id": 6})
	t.eq(s3.sheet, "character.jumpsuit.builder", "placeholder sleeping: the jumpsuit sheet")
	t.eq(s3.frame, "idle_front", "placeholder sleeping: idle_front")
	t.eq(float(s3.rotate_deg), float(art.colonist.sleeper_rotation_deg), "placeholder sleeping rotated -90")
	# The shipped manifest has real poses: sleeping sheet, frame "sleep", unrotated, n stable per id and within 0..3.
	for role in ["builder", "curious", "social", "tender"]:
		for id in [0, 1, 5, 6, 7, 12, 1001]:
			var r1 := _pose(M, art, man, {"state": "sleep", "role": role, "id": id})
			var r2 := _pose(M, art, man, {"state": "sleep", "role": role, "id": id})
			t.eq(r1.sheet, "character.sleeping.%s.%d" % [role, id % 4], "real manifest: %s id %d picks pose id mod 4" % [role, id])
			t.eq(r1.sheet, r2.sheet, "the pose is stable per being id")
			t.eq(r1.frame, "sleep", "real sleeping frame is 'sleep'")
			t.eq(float(r1.rotate_deg), 0.0, "real sleeping pose is not rotated")
			t.check(man.entries.has(r1.sheet) and man.entries[r1.sheet].get("file") != null, "%s exists with a file" % r1.sheet)
	# Construction welding: weld_1 / weld_2 at 6 Hz, side view.
	var w0 := _pose(M, art, man, {"state": "work", "suit_kind": "construction", "wait_h": 1.0, "real_time": 0.0})
	var w1 := _pose(M, art, man, {"state": "work", "suit_kind": "construction", "wait_h": 1.0, "real_time": 0.09})
	var w2 := _pose(M, art, man, {"state": "work", "suit_kind": "construction", "wait_h": 1.0, "real_time": 0.17})
	t.eq(w0.sheet, "character.construction", "weld sheet")
	t.eq(w0.frame, "weld_1", "weld at t = 0")
	t.eq(w1.frame, "weld_2", "weld at t = 1/12 s differs")
	t.eq(w2.frame, "weld_1", "weld alternates back after 1/6 s")
	var wl := _pose(M, art, man, {"state": "work", "suit_kind": "construction", "wait_h": 1.0, "face": -1})
	t.eq(wl.mirror, true, "weld faces the last horizontal sign (left)")
	# wait_h at or below STEP_EPS is not a pause: the being walks.
	var wm := _pose(M, art, man, {"state": "work", "suit_kind": "construction", "wait_h": 1e-10, "moving": true,
			"facing": {"dir": "side", "mirror": true}, "walk_frame": 2})
	t.eq(wm.frame, "walk_side_2", "wait_h 1e-10 moves: walk_side_2")
	t.eq(wm.mirror, true, "walk side mirrored from the facing")
	# EVA digging: dig and idle_side at 2 Hz.
	var d0 := _pose(M, art, man, {"state": "mining", "suit_kind": "eva", "wait_h": 1.0, "real_time": 0.0})
	var d1 := _pose(M, art, man, {"state": "mining", "suit_kind": "eva", "wait_h": 1.0, "real_time": 0.3})
	var d2 := _pose(M, art, man, {"state": "mining", "suit_kind": "eva", "wait_h": 1.0, "real_time": 0.55})
	t.eq(d0.sheet, "character.eva", "dig sheet")
	t.eq(d0.frame, "dig", "dig at t = 0")
	t.eq(d1.frame, "idle_side", "idle_side at t = 0.3 s (2 Hz)")
	t.eq(d2.frame, "dig", "dig at t = 0.55 s")
	# Carry: eva with a load (also regolith), construction outbound with a beam.
	var c1 := _pose(M, art, man, {"state": "eva", "suit_kind": "eva", "load": 5.0, "moving": true,
			"facing": {"dir": "side", "mirror": false}})
	t.eq(c1.frame, "carry", "eva with a load carries")
	var c2 := _pose(M, art, man, {"state": "eva", "suit_kind": "construction", "after": "work", "returning": false,
			"moving": true, "facing": {"dir": "side", "mirror": false}})
	t.eq(c2.sheet, "character.construction", "beam sheet")
	t.eq(c2.frame, "carry", "outbound builder carries a beam")
	var c3 := _pose(M, art, man, {"state": "eva", "suit_kind": "construction", "after": "enter", "returning": true,
			"moving": true, "facing": {"dir": "side", "mirror": false}, "walk_frame": 3})
	t.eq(c3.frame, "walk_side_3", "returning builder walks, no beam")
	var c4 := _pose(M, art, man, {"state": "eva", "suit_kind": "construction", "after": "work", "returning": true,
			"moving": true, "facing": {"dir": "side", "mirror": false}, "walk_frame": 1})
	t.eq(c4.frame, "walk_side_1", "a builder with returning set carries nothing even if after is still work")
	# Interior talk: talk and idle_front every 0.45 s, the lower id speaks first.
	var k0 := _pose(M, art, man, {"state": "idle", "talking": true, "speaks_first": true, "real_time": 0.0})
	var k1 := _pose(M, art, man, {"state": "idle", "talking": true, "speaks_first": true, "real_time": 0.5})
	var k2 := _pose(M, art, man, {"state": "idle", "talking": true, "speaks_first": false, "real_time": 0.0})
	var k3 := _pose(M, art, man, {"state": "idle", "talking": true, "speaks_first": false, "real_time": 0.5})
	t.eq(k0.frame, "talk", "first speaker talks at t = 0")
	t.eq(k1.frame, "idle_front", "first speaker listens at 0.5 s")
	t.eq(k2.frame, "idle_front", "second speaker listens at t = 0")
	t.eq(k3.frame, "talk", "second speaker talks at 0.5 s")
	# Moving: walk_front / walk_back / walk_side by facing, k from the phase.
	var m1 := _pose(M, art, man, {"moving": true, "facing": {"dir": "front", "mirror": false}, "walk_frame": 1})
	t.eq(m1.frame, "walk_front_1", "walk front")
	t.eq(m1.sheet, "character.jumpsuit.builder", "jumpsuit sheet by role")
	var m2 := _pose(M, art, man, {"moving": true, "facing": {"dir": "back", "mirror": false}, "walk_frame": 3,
			"role": "tender"})
	t.eq(m2.frame, "walk_back_3", "walk back")
	t.eq(m2.sheet, "character.jumpsuit.tender", "tender jumpsuit")
	var m3 := _pose(M, art, man, {"moving": true, "facing": {"dir": "side", "mirror": true}, "walk_frame": 0,
			"suit_kind": "eva", "state": "eva"})
	t.eq(m3.frame, "walk_side_0", "eva walk side")
	t.eq(m3.mirror, true, "left is mirrored")
	t.eq(m3.sheet, "character.eva", "eva sheet")
	# Otherwise idle_front (the construction suit has its own idle_front).
	var i1 := _pose(M, art, man, {})
	t.eq(i1.frame, "idle_front", "idle")
	var i2 := _pose(M, art, man, {"state": "eva", "suit_kind": "construction"})
	t.eq(i2.frame, "idle_front", "construction idle_front")
	t.eq(i2.sheet, "character.construction", "construction idle sheet")
	# Missing idle_side on the construction sheet falls back to idle_front.
	t.eq(M.facing_pose.resolve_frame("construction", "idle_side", art), "idle_front", "construction has no idle_side")
	t.eq(M.facing_pose.resolve_frame("eva", "idle_side", art), "idle_side", "eva has idle_side")
	t.eq(M.facing_pose.resolve_frame("jumpsuit", "talk", art), "talk", "jumpsuit talk exists")
	t.eq(M.facing_pose.resolve_frame("construction", "weld_2", art), "weld_2", "weld_2 exists")


func test_scale_p2(t) -> void:
	var M := _need(t, ["facing_pose", "view_model"])
	if M.is_empty():
		return
	var art := _art()
	var earth := float(M.facing_pose.height_px(true, false, art))
	var mars := float(M.facing_pose.height_px(false, false, art))
	t.near(earth, 7.6, 1e-9, "Earth-born 7.6 px")
	t.near(mars, 7.6 * 1.1, 1e-9, "Mars-born 8.36 px")
	t.near(mars / earth, 1.1, 1e-12, "Mars-born is exactly 1.1x")
	t.near(float(M.facing_pose.height_px(true, true, art)) / earth, 1.9, 1e-12, "interior scale 1.9x")
	t.near(float(M.facing_pose.height_px(false, true, art)) / mars, 1.9, 1e-12, "interior scale 1.9x (Mars-born)")
	# Through the model: two beings on the same spot, the feet do not move.
	var w := _world()
	var hab := w.add_building("habitat", 10, 10)
	var a := _outside(w, hab, 120.0, 130.0, "eva", true)
	var b := _outside(w, hab, 120.0, 130.0, "eva", false)
	var vm = M.view_model.new(w, art, _manifest())
	vm.update(1.0 / 60.0)
	vm.update(1.0 / 60.0)
	var va = vm.being(a.id)
	var vb = vm.being(b.id)
	t.near(float(vb.height_px) / float(va.height_px), 1.1, 1e-9, "model: Mars-born 1.1x")
	t.near(float(va.height_px), 7.6, 1e-9, "model: Earth-born 7.6")
	t.near((vb.pos as Vector2).x, (va.pos as Vector2).x, 1e-9, "feet x unchanged")
	t.near((vb.pos as Vector2).y, (va.pos as Vector2).y, 1e-9, "feet y unchanged")
	t.near((va.pos as Vector2).x, 120.0, 1e-6, "feet are on the sim position")


# ---------------------------------------------------------------- T-LAMP

func test_lamp_levels(t) -> void:
	var M := _need(t, ["light", "being_anim"])
	if M.is_empty():
		return
	var art := _art()
	var night: Dictionary = SimData.beings().night
	var want := {18.99: 0.0, 19.0: 0.3, 20.25: 0.65, 21.0: 0.86, 21.5: 1.0, 23.0: 1.0, 2.0: 1.0, 5.5: 1.0,
			6.25: 0.5, 7.0: 0.0, 12.0: 0.0}
	for h in want:
		var on: bool = h >= float(night.start_hour) or h < float(night.end_hour)
		var got := float(M.light.lamp_target(h, true, on, art))
		t.near(got, float(want[h]), 1e-6, "outside lamp target at %s" % str(h))
		t.near(float(M.light.lamp_target(h, false, on, art)), 0.0, 1e-9, "inside lamp target at %s" % str(h))
	# lamp_on as the sim defines it agrees with the rule used above (away from the exact edges).
	var w := _world()
	var hab := w.add_building("habitat", 0, 0)
	var being := _outside(w, hab, 5.0, 5.0)
	for h in [2.0, 5.4, 12.0, 21.4, 23.0]:
		w.t = w.clock.sol_h * (3.0 + h / w.clock.clock_hours)
		var rule_on: bool = h >= float(night.start_hour) or h < float(night.end_hour)
		t.eq(being.lamp_on(w), rule_on, "sim lamp_on agrees with the 21.5 / 5.5 rule at %s" % str(h))
	# Easing: reaches the target within 1% after 2 s, never overshoots, both directions.
	var a = M.being_anim.new(art, 1)
	var level := 0.0
	var prev := 0.0
	var ok := true
	for i in 120:
		a.update_lamp(1.0 / 60.0, 1.0)
		level = float(a.lamp_level)
		ok = ok and level <= 1.0 + 1e-12 and level >= prev - 1e-12
		prev = level
	t.check(ok, "lamp level rises monotonically and never overshoots")
	t.check(level >= 0.99, "lamp level within 1%% of 1.0 after 2 s (got %f)" % level)
	for i in 120:
		a.update_lamp(1.0 / 60.0, 0.3)
		level = float(a.lamp_level)
		ok = ok and level >= 0.3 - 1e-12
	t.check(ok, "lamp level does not undershoot the 0.3 target")
	t.near(level, 0.3, 0.01, "lamp level settles on 0.3 (within 1% of the 0..1 scale)")
	# Glow only for eva or construction suits; alpha scales with the level.
	var g_none: Dictionary = M.light.lamp_glow("none", 1.0, art)
	t.eq(g_none.on, false, "no glow for the jumpsuit")
	for sk in ["eva", "construction"]:
		var g1: Dictionary = M.light.lamp_glow(sk, 1.0, art)
		var g5: Dictionary = M.light.lamp_glow(sk, 0.5, art)
		t.eq(g1.on, true, sk + " glow on")
		t.near(float(g1.outer_alpha), 0.22, 1e-9, sk + " outer alpha at level 1")
		t.near(float(g1.core_alpha), 0.95, 1e-9, sk + " core alpha at level 1")
		t.near(float(g1.ground_alpha), 0.07, 1e-9, sk + " ground alpha at level 1")
		t.near(float(g5.outer_alpha), 0.11, 1e-9, sk + " outer alpha scales with the level")
		t.near(float(g5.core_alpha), 0.475, 1e-9, sk + " core alpha scales with the level")
	t.eq(M.light.lamp_glow("eva", 0.0, art).on, false, "no glow at level 0")


# ---------------------------------------------------------------- T-L1: light curve

func test_light_curve_l1(t) -> void:
	var M := _need(t, ["light"])
	if M.is_empty():
		return
	var art := _art()
	var L = M.light
	# h, N, L, dusk (spec 5.1 table)
	var rows := [[3.0, 1.0, 0.0, 0.0], [5.5, 1.0, 0.0, 0.0], [6.0, 2.0 / 3.0, 1.0 / 3.0, 0.888889],
			[6.25, 0.5, 0.5, 1.0], [7.0, 0.0, 1.0, 0.0], [12.0, 0.0, 1.0, 0.0], [18.99, 0.0, 1.0, 0.0],
			[19.0, 0.0, 1.0, 0.0], [20.25, 0.5, 0.5, 1.0], [21.0, 0.8, 0.2, 0.64], [21.5, 1.0, 0.0, 0.0],
			[23.0, 1.0, 0.0, 0.0]]
	for r in rows:
		var h: float = r[0]
		t.near(float(L.night(h, art)), float(r[1]), 1e-6, "N at %s" % str(h))
		t.near(float(L.daylight(h, art)), float(r[2]), 1e-6, "L at %s" % str(h))
		t.near(float(L.dusk(h, art)), float(r[3]), 1e-6, "dusk at %s" % str(h))
		var ta: Dictionary = L.tint_alphas(h, art)
		t.near(float(ta.night), 0.86 * float(r[1]), 1e-6, "night tint alpha at %s" % str(h))
		t.near(float(ta.day), 0.18 * float(r[2]), 1e-6, "day tint alpha at %s" % str(h))
		t.near(float(ta.dusk), 0.42 * float(r[3]), 1e-6, "dusk tint alpha at %s" % str(h))
	t.eq(float(L.night(18.99, art)), 0.0, "full day at 18.99")
	t.eq(float(L.night(7.0, art)), 0.0, "full day at 7.0")
	t.near(float(L.night(19.01, art)), 0.004, 1e-6, "the ramp starts after 19.0: N(19.01) = 0.004")
	t.eq(float(L.night(21.5, art)), 1.0, "full dark at 21.5")
	t.eq(float(L.night(5.5, art)), 1.0, "full dark at 5.5")
	var prev := -1.0
	var ok_up := true
	var h := 19.0
	while h <= 21.5 + 1e-9:
		var n := float(L.night(h, art))
		ok_up = ok_up and n >= prev - 1e-12
		prev = n
		h += 0.01
	t.check(ok_up, "N non-decreasing over 19 to 21.5")
	prev = 2.0
	var ok_down := true
	h = 5.5
	while h <= 7.0 + 1e-9:
		var n := float(L.night(h, art))
		ok_down = ok_down and n <= prev + 1e-12
		prev = n
		h += 0.01
	t.check(ok_down, "N non-increasing over 5.5 to 7")
	# Window glow: same N, so half at 20.25 of its value at 23; off at night <= 0.05.
	t.near(float(L.window_alpha(20.25, 1.0, art)), 0.5 * float(L.window_alpha(23.0, 1.0, art)), 1e-9, "window alpha at 20.25 is half of 23")
	t.near(float(L.window_alpha(23.0, 1.0, art)), 0.85, 1e-9, "window alpha 0.85 at full dark")
	t.eq(float(L.window_alpha(12.0, 1.0, art)), 0.0, "no window glow by day")
	t.eq(float(L.window_alpha(19.1, 1.0, art)), 0.0, "no window glow at N = 0.04 (<= 0.05)")
	t.near(float(L.window_alpha(23.0, 0.5, art)), 0.425, 1e-9, "window alpha scales with vis")
	# Shadow dx: 12, 6, 18, 4, 3 -> 0, -9, 9, -12.0, -12.6 (the clamp case).
	for pair in [[12.0, 0.0], [6.0, -9.0], [18.0, 9.0], [4.0, -12.0], [3.0, -12.6], [5.0, -10.5], [21.0, 12.6]]:
		t.near(float(L.shadow_dx(pair[0], art)), float(pair[1]), 1e-9, "shadow dx at %s" % str(pair[0]))


# ---------------------------------------------------------------- T-D1, T-D2: doors

func test_doors_d1(t) -> void:
	var M := _need(t, ["doors", "view_model"])
	if M.is_empty():
		return
	var art := _art()
	var D = M.doors
	var w := _world()
	var hab := w.buildings.add("habitat", 10, 10, 1.0, 13, 9)
	var other := w.buildings.add("workshop", 40, 10, 1.0, 12, 9)
	var door := hab.door(8.0)
	t.check(not D.want_open(hab, w.beings, 8.0, art), "no being: want 0")
	# (a) a miner suiting up inside.
	var miner := w.add_being(hab.id, "builder")
	miner.state = "to_door"
	miner.suit_up = true
	miner.mine = {"home_id": hab.id}
	t.check(D.want_open(hab, w.beings, 8.0, art), "miner in to_door with suit_up: want 1")
	t.check(not D.want_open(other, w.beings, 8.0, art), "another building: want 0")
	w.beings.clear()
	# A builder with a job doing the same does not open the door.
	var builder := w.add_being(hab.id, "builder")
	builder.state = "to_door"
	builder.suit_up = true
	builder.job = RefCounted.new()
	t.check(not D.want_open(hab, w.beings, 8.0, art), "builder suiting up (job set): want 0")
	builder.mine_intent = RefCounted.new()
	t.check(not D.want_open(hab, w.beings, 8.0, art), "a to_door + suit_up being with a job is excluded even with a leftover mine_intent")
	w.beings.clear()
	# (b) an eva being near the door of the building it left from.
	var near_b := _outside(w, hab.id, door.x + 17.9, door.y)
	near_b.mine = null
	t.check(D.want_open(hab, w.beings, 8.0, art), "eva at 17.9 px: want 1 (mine is null on the return trip)")
	near_b.x = door.x + 18.1
	t.check(not D.want_open(hab, w.beings, 8.0, art), "eva at 18.1 px: want 0")
	near_b.x = door.x
	near_b.y = door.y - 17.0
	t.check(D.want_open(hab, w.beings, 8.0, art), "eva above the door at 17 px: want 1 (distance, not x)")
	t.check(not D.want_open(other, w.beings, 8.0, art), "eva at hab's door does not open the other building's door")
	# A construction-suit builder never opens it (state eva with the suit kept, or work with a job).
	near_b.x = door.x
	near_b.y = door.y
	near_b.construction_suit = true
	t.check(not D.want_open(hab, w.beings, 8.0, art), "construction_suit builder at the door: want 0")
	near_b.construction_suit = false
	near_b.state = "work"
	near_b.job = RefCounted.new()
	t.check(not D.want_open(hab, w.beings, 8.0, art), "builder in work with a job at the door: want 0")
	w.beings.clear()
	# Only finished buildings animate doors; offline ones still do.
	var site := w.buildings.add("archive", 70, 10, 0.5, 12, 9)
	var s_miner := w.add_being(site.id, "builder")
	s_miner.state = "to_door"
	s_miner.suit_up = true
	s_miner.mine = {}
	t.check(not D.want_open(site, w.beings, 8.0, art), "built < 1: no door")
	w.beings.clear()
	hab.offline = true
	var m2 := w.add_being(hab.id, "builder")
	m2.state = "to_door"
	m2.suit_up = true
	m2.mine = {}
	t.check(D.want_open(hab, w.beings, 8.0, art), "offline building still opens its door (manual)")
	hab.offline = false
	# Easing per 1/60 s frame: at least 0.95 within 44 frames, back below 0.05 within 44 frames.
	var open := 0.0
	var frames_up := 0
	while open < 0.95 and frames_up < 200:
		open = float(D.ease_open(open, true, 1.0 / 60.0, art))
		frames_up += 1
	t.check(frames_up <= 44, "door reaches 0.95 within 44 frames (took %d)" % frames_up)
	var frames_down := 0
	while open >= 0.05 and frames_down < 200:
		open = float(D.ease_open(open, false, 1.0 / 60.0, art))
		frames_down += 1
	t.check(frames_down <= 44, "door returns below 0.05 within 44 frames (took %d)" % frames_down)
	# Stays in [0, 1]; dt above 0.1 is clamped (so dt 5.0 equals dt 0.1); depends only on dt.
	t.near(float(D.ease_open(0.0, true, 5.0, art)), float(D.ease_open(0.0, true, 0.1, art)), 1e-12, "dt clamped to 0.1")
	t.near(float(D.ease_open(0.0, true, 0.1, art)), 0.4, 1e-12, "one 0.1 s step from 0 gives 0.4")
	t.check(float(D.ease_open(1.0, true, 0.1, art)) <= 1.0, "never above 1")
	t.check(float(D.ease_open(0.0, false, 0.1, art)) >= 0.0, "never below 0")
	t.eq(float(D.ease_open(0.0, false, 1.0 / 60.0, art)), 0.0, "open 0 with no want stays 0")
	# Through the model: the same fixture at two sim times gives the same door series (depends only on dt).
	var series: Array = []
	for t_offset in [0.0, 24000.0]:
		var w2 := _world()
		var h2 := w2.add_building("habitat", 10, 10)
		var m3 := w2.add_being(h2, "builder")
		m3.state = "to_door"
		m3.suit_up = true
		m3.mine = {}
		w2.t += t_offset
		var vm = M.view_model.new(w2, art, _manifest())
		var vals: Array = []
		for i in 44:
			vm.update(1.0 / 60.0)
			vals.append(float(vm.building(h2).door_open))
		series.append(vals)
	t.eq(series[0], series[1], "door series independent of sim time")
	t.check(float(series[0][43]) >= 0.95, "model door reaches 0.95 in 44 frames")


func test_door_geometry_d2(t) -> void:
	var M := _need(t, ["doors"])
	if M.is_empty():
		return
	var art := _art()
	var size := Vector2(48, 44)
	var s: Dictionary = M.doors.leaf_offsets(0.5, "split", size, art)
	var half := size.x / 2.0
	t.near((s.left as Vector2).x, -half * 0.5 * 0.92, 1e-4, "split left leaf at open 0.5")
	t.near((s.right as Vector2).x, half * 0.5 * 0.92, 1e-4, "split right leaf at open 0.5")
	t.near((s.left as Vector2).y, 0.0, 1e-9, "split moves sideways only")
	t.eq(s.clip, Rect2(Vector2.ZERO, size), "split leaves are clipped to the door rect")
	var full: Dictionary = M.doors.leaf_offsets(1.0, "split", size, art)
	t.near((full.right as Vector2).x, half * 0.92, 1e-4, "split at open 1")
	var r: Dictionary = M.doors.leaf_offsets(1.0, "rollup", size, art)
	t.near((r.panel as Vector2).y, -0.92 * size.y, 1e-4, "rollup moves 0.92 x height up")
	t.near((r.panel as Vector2).x, 0.0, 1e-9, "rollup does not move sideways")
	t.eq(r.clip, Rect2(Vector2.ZERO, size), "rollup is clipped to the door rect")
	var r0: Dictionary = M.doors.leaf_offsets(0.0, "rollup", size, art)
	t.near((r0.panel as Vector2).y, 0.0, 1e-9, "closed rollup is at rest")


# ---------------------------------------------------------------- T-A1, T-O1: accents, offline

func test_accent_pulse_a1(t) -> void:
	var M := _need(t, ["light"])
	if M.is_empty():
		return
	var art := _art()
	var L = M.light
	for kind_rate in [["reactor", 1.8], ["habitat", 1.1]]:
		var kind: String = kind_rate[0]
		var period := TAU / float(kind_rate[1])
		var lo_day := 9.0
		var hi_day := -9.0
		var lo_night := 9.0
		var hi_night := -9.0
		for i in 200:
			var rt := period * i / 200.0
			var p := float(L.pulse(rt, 3, kind, art))
			t.between(p, 0.0, 1.0, "pulse in 0..1")
			var a_day := float(L.accent_alpha(12.0, p, 1.0, art))
			var a_night := float(L.accent_alpha(23.0, p, 1.0, art))
			lo_day = minf(lo_day, a_day)
			hi_day = maxf(hi_day, a_day)
			lo_night = minf(lo_night, a_night)
			hi_night = maxf(hi_night, a_night)
		t.check(lo_day >= 0.08 - 1e-6 and hi_day <= 0.30 + 1e-6, "%s day accent in 0.08..0.30 (%f..%f)" % [kind, lo_day, hi_day])
		t.near(hi_day, 0.30, 0.002, kind + " day accent reaches 0.30")
		t.near(lo_day, 0.08, 0.002, kind + " day accent reaches 0.08")
		# Spec 5.3: (0.08 + 0.22 p) + N (0.30 + 0.45 p) = 0.38 .. 1.05 at N = 1 (T-A1 prints 0.83, a slip).
		t.check(lo_night >= 0.38 - 1e-6 and hi_night <= 1.05 + 1e-6, "%s night accent in 0.38..1.05 (%f..%f)" % [kind, lo_night, hi_night])
		t.near(hi_night, 1.05, 0.005, kind + " night accent reaches 1.05")
		t.near(lo_night, 0.38, 0.005, kind + " night accent reaches 0.38")
		# Period.
		t.near(float(L.pulse(0.7 + period, 3, kind, art)), float(L.pulse(0.7, 3, kind, art)), 1e-9, kind + " period 2pi / rate")
	t.check(absf(float(L.pulse(0.7 + TAU / 1.8, 3, "habitat", art)) - float(L.pulse(0.7, 3, "habitat", art))) > 0.01, "habitat does not repeat at the reactor period")
	t.check(absf(float(L.pulse(0.0, 1, "habitat", art)) - float(L.pulse(0.0, 2, "habitat", art))) > 0.05, "two ids are out of phase")
	t.near(float(L.accent_alpha(23.0, 0.5, 0.5, art)), 0.5 * float(L.accent_alpha(23.0, 0.5, 1.0, art)), 1e-9, "accent scales with vis")
	# Mid-ramp (N = 0.5 at 20.25): (0.08 + 0.22 p) + N (0.30 + 0.45 p).
	for p in [0.0, 0.3, 1.0]:
		t.near(float(L.accent_alpha(20.25, p, 1.0, art)), (0.08 + 0.22 * p) + 0.5 * (0.30 + 0.45 * p), 1e-9, "accent at N = 0.5, pulse %s" % str(p))


func test_offline_o1(t) -> void:
	var M := _need(t, ["building_anim", "particles"])
	if M.is_empty():
		return
	var art := _art()
	var dt := 1.0 / 60.0
	var a = M.building_anim.new(art, 2, "habitat")
	for i in 120:
		a.update(dt, true, false)
	t.near(float(a.power), 1.0, 1e-12, "online power 1")
	var h := 23.0
	var on: Dictionary = a.lights(h, 1.0, 0.0)
	t.check(float(on.accent) > 0.3 and float(on.windows) > 0.8 and float(on.strip) > 0.05 and float(on.door_glow) > 0.1, "online lights are lit at night")
	t.near(float(on.dim), 0.0, 1e-12, "no dim overlay while online")
	t.near(float(on.windows), 0.85, 1e-9, "windows 0.85 at full dark")
	t.near(float(on.strip), 0.10, 1e-9, "strip 0.10 at full dark")
	t.near(float(on.door_glow), 0.25 * float(a.door_open) * 1.4, 1e-9, "door glow 0.25 x open x (0.4 + N)")
	# Offline: linear over 0.5 s.
	for i in 15:
		a.update(dt, true, true)
	t.near(float(a.power), 0.5, 1e-9, "power 0.5 after 0.25 s")
	var half: Dictionary = a.lights(h, 1.0, 0.0)
	t.near(float(half.accent), 0.5 * float(on.accent), 1e-4, "accent halves")
	t.near(float(half.windows), 0.5 * float(on.windows), 1e-9, "windows halve")
	t.near(float(half.strip), 0.5 * float(on.strip), 1e-9, "strip halves")
	t.near(float(half.door_glow), 0.25 * float(a.door_open) * 1.4 * 0.5, 1e-9, "door glow halves")
	t.near(float(half.dim), 0.25, 1e-9, "dim overlay 0.25 halfway")
	for i in 15:
		a.update(dt, true, true)
	t.near(float(a.power), 0.0, 1e-9, "power 0 after 0.5 s")
	var off: Dictionary = a.lights(h, 1.0, 0.0)
	for k in ["accent", "windows", "strip", "door_glow"]:
		t.near(float(off[k]), 0.0, 1e-9, k + " is 0 when offline")
	t.near(float(off.dim), 0.5, 1e-9, "dim overlay 0.5 when offline")
	# The door still animates while offline (manual doors).
	var open_before := float(a.door_open)
	a.update(dt, false, true)
	t.check(float(a.door_open) < open_before, "offline door still closes")
	# Back online restores.
	for i in 40:
		a.update(dt, true, false)
	t.near(float(a.power), 1.0, 1e-9, "power back to 1")
	t.near(float(a.lights(h, 1.0, 0.0).dim), 0.0, 1e-9, "dim gone")
	# Roof open (cut 1) takes the exterior lights away.
	t.near(float(a.lights(h, 1.0, 1.0).windows), 0.0, 1e-9, "cut 1: windows 0")
	# Flicker: 1.2 per s of model time, accumulator emission, 0.08 s life, inside the footprint.
	var ps = M.particles.new(art, 0)
	var rect := Rect2(80, 160, 104, 72)
	var src := [{"key": "flicker:2", "kind": "flicker", "rect": rect}]
	var seen := 0
	var last := 0
	var max_live := 0
	var all_in := true
	var all_life := true
	for i in 20000:
		ps.update(0.05, src)
		var e := int(ps.emitted("flicker:2"))
		max_live = maxi(max_live, int(ps.count()))
		if e != last:
			for p in ps.snapshot():
				if p.kind == "flicker" and absf(float(p.life) - float(p.max_life)) < 1e-12:
					seen += 1
					all_life = all_life and absf(float(p.max_life) - 0.08) < 1e-9
					all_in = all_in and float(p.x) >= rect.position.x + 4.0 - 1e-9 and float(p.x) <= rect.end.x - 4.0 + 1e-9 \
							and float(p.y) >= rect.position.y - 1e-9 and float(p.y) <= rect.position.y + 0.6 * rect.size.y + 1e-9
			last = e
	t.check(absi(int(ps.emitted("flicker:2")) - 1200) <= 1, "1000 s of flicker emits 1,200 +-1 (got %d)" % int(ps.emitted("flicker:2")))
	t.check(absi(seen - 1200) <= 1, "all emissions were seen as fresh particles (%d)" % seen)
	t.check(all_life, "each flicker lasts 0.08 s")
	t.check(all_in, "flicker points inside the footprint (x inset 4 px, top 60%)")
	t.check(max_live <= 1, "flickers do not overlap at 1.2 per s (max live %d)" % max_live)


# ---------------------------------------------------------------- T-C1, T-C2: construction, sparks

func test_construction_table_c1(t) -> void:
	var M := _need(t, ["construction"])
	if M.is_empty():
		return
	var art := _art()
	var C = M.construction
	# built, p, f, g, sa
	var rows := [[0.0, 0.0, 0.0, 0.0, 0.0], [0.3, 0.0, 0.0, 0.0, 0.0], [0.4, 0.0, 0.0, 0.0, 0.0],
			[0.5, 0.16667, 0.02222, 0.0, 1.0], [0.6, 0.33333, 0.24444, 0.0, 1.0], [0.7, 0.5, 0.46667, 0.09091, 1.0],
			[0.9, 0.83333, 0.91111, 0.69697, 1.0], [0.95, 0.91667, 1.0, 0.84848, 0.69444]]
	for r in rows:
		var ph: Dictionary = C.phases(r[0], art)
		t.near(float(ph.p), float(r[1]), 1e-4, "p at built %s" % str(r[0]))
		t.near(float(ph.f), float(r[2]), 1e-4, "f at built %s" % str(r[0]))
		t.near(float(ph.g), float(r[3]), 1e-4, "g at built %s" % str(r[0]))
		t.near(float(ph.sa), float(r[4]), 1e-4, "sa at built %s" % str(r[0]))
	# Thresholds in built: slab at 0.4+, opaque 0.472, walls 0.49, paint 0.67, scaffolds down at 0.928.
	t.check(float(C.phases(0.401, art).p) > 0.0, "slab starts just after 0.4")
	t.near(float(C.phases(0.472, art).p), 0.12, 0.001, "p reaches the 0.12 slab fade at built 0.472")
	t.check(float(C.phases(0.485, art).f) == 0.0 and float(C.phases(0.495, art).f) > 0.0, "walls start at 0.49")
	t.check(float(C.phases(0.665, art).g) == 0.0 and float(C.phases(0.675, art).g) > 0.0, "paint starts at 0.67")
	t.check(float(C.phases(0.92, art).sa) == 1.0 and float(C.phases(0.93, art).sa) < 1.0, "scaffold starts down at 0.928")
	var early: Dictionary = C.phases(0.41, art)
	t.near(float(early.sa), float(early.p) / 0.08, 1e-9, "sa fades in as p / 0.08")
	# g <= f for 1,000 values; all in 0..1.
	var ok := true
	for i in 1001:
		var b := i / 1000.0
		var ph: Dictionary = C.phases(b, art)
		ok = ok and float(ph.g) <= float(ph.f) + 1e-12
		ok = ok and float(ph.f) >= 0.0 and float(ph.f) <= 1.0 and float(ph.g) >= 0.0 and float(ph.g) <= 1.0 \
				and float(ph.sa) >= 0.0 and float(ph.sa) <= 1.0
	t.check(ok, "g <= f and all phases in 0..1 for 1,000 values of built")
	# Corridor reveal.
	t.near(float(C.corridor_frac(0.2, art)), 0.5, 1e-9, "corridor 0.5 at built 0.2")
	t.near(float(C.corridor_frac(0.4, art)), 1.0, 1e-9, "corridor 1 at 0.4")
	t.near(float(C.corridor_frac(0.9, art)), 1.0, 1e-9, "corridor 1 above 0.4")
	t.near(float(C.corridor_frac(0.0, art)), 0.0, 1e-9, "corridor 0 at 0")
	# Draw lists.
	var rect := Rect2(100, 50, 104, 66)
	var l3: Array = C.draw_list(0.3, rect, art)
	var names3: Array = []
	for e in l3:
		names3.append(e.layer)
	names3.sort()
	t.eq(names3, ["ghost", "stakes", "tunnel"], "built 0.3: stakes, ghost and tunnel only")
	var l7: Array = C.draw_list(0.7, rect, art)
	var by := {}
	for e in l7:
		by[e.layer] = e
	for need in ["stakes", "ghost", "tunnel", "slab", "gray", "paint", "scaffold"]:
		t.check(by.has(need), "built 0.7 has " + need)
	if by.has("gray") and by.has("paint"):
		t.near(float(by.gray.clip_top), rect.position.y + rect.size.y * (1.0 - 0.466667), 1e-4, "gray clip top at Y + H x 0.5333")
		t.near(float(by.paint.clip_top), rect.position.y + rect.size.y * (1.0 - 0.090909), 1e-4, "paint clip top at Y + H x 0.9091")
	t.eq(C.draw_list(1.0, rect, art).size(), 0, "built 1.0: no site layers at all")
	var l4: Array = C.draw_list(0.45, rect, art)
	var n4: Array = []
	for e in l4:
		n4.append(e.layer)
	n4.sort()
	t.eq(n4, ["ghost", "scaffold", "slab", "stakes", "tunnel"], "built 0.45: slab and scaffold (sa = 1), no walls yet")


func _src_seam(crew: int, f: float) -> Array:
	return [{"key": "seam:9", "kind": "weld_seam", "rect": Rect2(100, 50, 104, 66), "f": f, "crew": crew}]


func _run_frames(ps, src: Array, dts: Array) -> void:
	for dt in dts:
		ps.update(float(dt), src)


func _uniform_dts(n: int, total: float) -> Array:
	var out: Array = []
	for i in n:
		out.append(total / n)
	return out


func _irregular_dts(total: float, seed_in: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_in
	var out: Array = []
	var sum := 0.0
	while sum < total - 1e-12:
		var d := minf(rng.randf_range(0.011, 0.1), total - sum)
		out.append(d)
		sum += d
	return out


func test_sparks_c2(t) -> void:
	var M := _need(t, ["particles"])
	if M.is_empty():
		return
	var art := _art()
	var P = M.particles
	# Seam: crew 2, f 0.5, 10 s at 60 fps, 30 fps and irregular frames: floor(10 x 2 x 10) = 200 +-1.
	for dts in [_uniform_dts(600, 10.0), _uniform_dts(300, 10.0), _irregular_dts(10.0, 5), _irregular_dts(10.0, 6)]:
		var ps = P.new(art, 0)
		_run_frames(ps, _src_seam(2, 0.5), dts)
		t.check(absi(int(ps.emitted("seam:9")) - 200) <= 1, "crew 2 seam: 200 +-1 over 10 s in %d frames (got %d)" % [dts.size(), int(ps.emitted("seam:9"))])
	# Crew 5 is capped at 3 crews' worth: 300.
	var p5 = P.new(art, 0)
	_run_frames(p5, _src_seam(5, 0.5), _uniform_dts(600, 10.0))
	t.check(absi(int(p5.emitted("seam:9")) - 300) <= 1, "crew 5 capped at 3: 300 +-1 (got %d)" % int(p5.emitted("seam:9")))
	# f = 0, f = 1, crew 0: none.
	for case in [[2, 0.0], [2, 1.0], [0, 0.5]]:
		var pn = P.new(art, 0)
		_run_frames(pn, _src_seam(case[0], case[1]), _uniform_dts(600, 10.0))
		t.eq(int(pn.emitted("seam:9")), 0, "no seam sparks for crew %d f %s" % [case[0], str(case[1])])
	# Hand: 38 per s -> 380 +-1 over 10 s, any frame rate.
	var hand := [{"key": "hand:4", "kind": "weld_hand", "feet": Vector2(50, 60), "face": 1, "scale": 1.0}]
	for dts in [_uniform_dts(600, 10.0), _irregular_dts(10.0, 8)]:
		var ph = P.new(art, 0)
		_run_frames(ph, hand, dts)
		t.check(absi(int(ph.emitted("hand:4")) - 380) <= 1, "hand 380 +-1 over 10 s (got %d)" % int(ph.emitted("hand:4")))
		t.eq(int(ph.emitted_kind("weld_hand")), int(ph.emitted("hand:4")), "emitted_kind sums the sources of a kind")
	# Accumulator: floor(acc); 0.38 per 0.01 s frame, first emission on frame 3.
	var pa = P.new(art, 0)
	for i in 2:
		pa.update(0.01, hand)
	t.eq(int(pa.emitted("hand:4")), 0, "0.76 accumulated: nothing yet")
	pa.update(0.01, hand)
	t.eq(int(pa.emitted("hand:4")), 1, "1.14 accumulated: one particle, 0.14 left")
	# dt clamp: one 5 s frame is a 0.1 s frame (38 x 0.1 = 3.8 -> 3).
	var pc = P.new(art, 0)
	pc.update(5.0, hand)
	t.eq(int(pc.emitted("hand:4")), 3, "dt above 0.1 s is clamped (3 particles)")
	# Cap 600: never exceeded, new ones dropped.
	var many: Array = []
	for i in 40:
		many.append({"key": "hand:%d" % i, "kind": "weld_hand", "feet": Vector2(i, 0), "face": 1, "scale": 1.0})
	var pm = P.new(art, 0)
	var worst := 0
	for i in 300:
		pm.update(1.0 / 60.0, many)
		worst = maxi(worst, int(pm.count()))
	t.check(worst <= 600, "pool never exceeds 600 (max %d)" % worst)
	t.check(worst >= 590, "pool fills towards the cap (max %d)" % worst)
	t.check(int(pm.dropped) > 0, "new particles are dropped at the cap (%d)" % int(pm.dropped))
	# Determinism: same seed and dt sequence is identical; a different seed differs.
	var dts := _irregular_dts(3.0, 21)
	var s1 = P.new(art, 3)
	var s2 = P.new(art, 3)
	var s3 = P.new(art, 4)
	for ps in [s1, s2, s3]:
		_run_frames(ps, many.slice(0, 5) + _src_seam(2, 0.5), dts)
	t.eq(str(s1.snapshot()), str(s2.snapshot()), "same seed and dt sequence: identical particles")
	t.check(str(s1.snapshot()) != str(s3.snapshot()), "a different seed gives different particles")
	t.check(s1.snapshot().size() > 10, "particles exist")
	# Seam sparks start on the top edge of the gray wall, across the sprite width.
	var pseam = P.new(art, 0)
	pseam.update(0.1, _src_seam(2, 0.5))
	var snap: Array = pseam.snapshot()
	t.eq(snap.size(), 2, "0.1 s of a crew-2 seam emits 2 sparks")
	for sp in snap:
		t.near(float(sp.y), 50.0 + 66.0 * 0.5, 1e-3, "seam spark starts at Y + H x (1 - f)")
		t.check(float(sp.x) >= 100.0 and float(sp.x) <= 204.0, "seam spark x within the sprite width")
	# Dig dust: 7 per s, counts only (colour is drawing).
	var dig := [{"key": "dig:3", "kind": "dig", "feet": Vector2(5, 5), "face": -1, "scale": 1.0, "ice": true}]
	var pd = P.new(art, 0)
	_run_frames(pd, dig, _uniform_dts(600, 10.0))
	t.check(absi(int(pd.emitted("dig:3")) - 70) <= 1, "dig 7 per s: 70 +-1 (got %d)" % int(pd.emitted("dig:3")))


func test_sparks_through_the_model(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var reactor := w.add_building("reactor", 10, 10)
	var site_b := w.buildings.add_attached("habitat", reactor, "r", 13, 9, 6, 0.715)
	var site := Buildings.Site.new()
	site.building_id = site_b.id
	site.parent_id = reactor
	site.last_work_t = w.t
	w.buildings.site = site
	for i in 2:
		var b := w.add_being(reactor, "builder")
		b.state = "work"
		b.job = site
		b.construction_suit = true
		b.x = float(site_b.tx * 8 + 20 + i * 5)
		b.y = float(site_b.ty * 8 + 20)
		b.heading = 0.0
		b.air_h = 30.0
		b.wait_h = 1.0
	# A third being works on something else: not part of this site's crew.
	var other := w.add_being(reactor, "builder")
	other.state = "work"
	other.job = RefCounted.new()
	other.construction_suit = true
	other.x = 400.0
	other.y = 400.0
	other.heading = 0.0
	other.air_h = 30.0
	other.wait_h = 1.0
	var vm = M.view_model.new(w, art, _manifest())
	for i in 600:
		vm.update(1.0 / 60.0)
	t.check(absi(int(vm.particles.emitted_kind("weld_seam")) - 200) <= 1, "model: crew 2 at f = 0.5 emits 200 +-1 seam sparks (got %d)" % int(vm.particles.emitted_kind("weld_seam")))
	t.check(absi(int(vm.particles.emitted_kind("weld_hand")) - 1140) <= 3, "model: three welders emit 1,140 +-3 hand sparks (got %d)" % int(vm.particles.emitted_kind("weld_hand")))
	t.check(int(vm.particles.count()) <= 600, "model pool within the cap")
	# The sim never advanced.
	t.eq(w.step_index, 0, "the model did not step the sim")


# ---------------------------------------------------------------- T-FP: footprints

func _print(w: SimWorld, x: float, y: float, at: float, heavy: bool) -> Resources.Footprint:
	w.resources.add_footprint(x, y, 0.0, at, heavy)
	return w.resources.footprints[w.resources.footprints.size() - 1]


func test_footprints_fp(t) -> void:
	var M := _need(t, ["footprints"])
	if M.is_empty():
		return
	var art := _art()
	var F = M.footprints
	for pair in [[0.0, 0.32, 0.42], [0.5, 0.16, 0.21], [0.99, 0.0032, 0.0042]]:
		t.near(float(F.alpha(pair[0], false, art)), float(pair[1]), 1e-9, "light alpha at age %s" % str(pair[0]))
		t.near(float(F.alpha(pair[0], true, art)), float(pair[2]), 1e-9, "heavy alpha at age %s" % str(pair[0]))
	t.eq(float(F.alpha(1.0, false, art)), 0.0, "age 1: nothing")
	t.eq(float(F.alpha(1.5, true, art)), 0.0, "age 1.5: nothing")
	var w := _world()
	w.t = w.clock.sol_h * 10.0
	var fade_h := float(SimData.suits().footprint.fade_sols) * w.clock.sol_h
	t.near(float(F.age_of(_print(w, 0, 0, w.t - fade_h * 0.5, false), w)), 0.5, 1e-9, "age_of: half the fade time")
	t.eq(float(F.age_of(_print(w, 0, 0, w.t, false), w)), 0.0, "age_of: fresh print")
	var old_print := _print(w, 5, 5, w.t - 3.0 * w.clock.sol_h, false)
	t.check(float(F.age_of(old_print, w)) >= 1.0, "a 3-sol-old print has age 1.2")
	# 80 random prints; count inside a camera rect equals the direct count.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	w.resources.footprints.clear()
	for i in 80:
		var age_sols := rng.randf_range(0.0, 3.2)
		w.resources.add_footprint(rng.randf_range(0.0, 300.0), rng.randf_range(0.0, 300.0), rng.randf_range(0.0, TAU),
				w.t - age_sols * w.clock.sol_h, rng.randf() < 0.4)
	var cam := Rect2(40.5, 60.5, 150.0, 120.0)
	var want := 0
	for f in w.resources.footprints:
		var age := (w.t - f.t) / fade_h
		if age < 1.0 and cam.has_point(Vector2(f.x, f.y)):
			want += 1
	var drawn: Array = F.drawn(w, cam, art)
	t.eq(drawn.size(), want, "drawn prints in the camera rect equal the sim count with age < 1")
	t.check(want > 5, "the fixture has prints in view (%d)" % want)
	for d in drawn:
		t.check(float(d.alpha) > 0.0 and float(d.alpha) <= 0.42 + 1e-9, "drawn alpha in range")
		t.check(cam.has_point(Vector2(d.x, d.y)), "drawn print is inside the camera rect")
	var all_view: Array = F.drawn(w, Rect2(-10, -10, 400, 400), art)
	var alive := 0
	for f in w.resources.footprints:
		if (w.t - f.t) / fade_h < 1.0:
			alive += 1
	t.eq(all_view.size(), alive, "every live print is drawn in a rect covering all")


# ---------------------------------------------------------------- T-Z: sort

func _eb(id: int, rect: Rect2, built: float = 1.0) -> Dictionary:
	return {"type": "building", "id": id, "base_y": rect.end.y, "built": built, "rect": rect, "state": "", "pos": Vector2.ZERO}


func _eg(id: int, pos: Vector2, state: String = "eva") -> Dictionary:
	return {"type": "being", "id": id, "base_y": pos.y, "built": 1.0, "rect": Rect2(), "state": state, "pos": pos}


func _ids(list: Array) -> Array:
	var out: Array = []
	for e in list:
		out.append("%s%d" % ["B" if e.type == "building" else "g", e.id])
	return out


func test_zsort(t) -> void:
	var M := _need(t, ["zsort"])
	if M.is_empty():
		return
	var Z = M.zsort
	var rect := Rect2(80, 160, 104, 72)
	var bottom := rect.end.y
	t.eq(_ids(Z.sorted([_eg(2, Vector2(300, 60)), _eg(1, Vector2(300, 50))])), ["g1", "g2"], "two beings: by y")
	t.eq(_ids(Z.sorted([_eg(1, Vector2(300, 50)), _eg(2, Vector2(300, 60))])), ["g1", "g2"], "input order does not matter")
	t.eq(_ids(Z.sorted([_eg(5, Vector2(100, bottom)), _eb(1, rect)])), ["B1", "g5"], "a being at the bottom edge draws after (above) its building")
	t.eq(_ids(Z.sorted([_eb(1, rect), _eg(5, Vector2(100, bottom - 1.0))])), ["g5", "B1"], "1 px north of the bottom edge draws before (behind)")
	var site := _eb(3, rect, 0.5)
	t.eq(_ids(Z.sorted([site, _eg(7, Vector2(100, 170))])), ["B3", "g7"], "a builder inside a site rect draws above the site")
	t.eq(_ids(Z.sorted([_eg(7, Vector2(100, 170)), site])), ["B3", "g7"], "same, other input order")
	t.eq(_ids(Z.sorted([site, _eg(8, Vector2(400, 170))])), ["g8", "B3"], "a being outside the site rect sorts by y (behind)")
	t.eq(_ids(Z.sorted([_eb(1, rect), _eg(9, Vector2(100, 170))])), ["g9", "B1"], "inside a finished building's rect: by y, behind")
	t.eq(_ids(Z.sorted([_eg(5, Vector2(10, 40)), _eg(3, Vector2(20, 40))])), ["g3", "g5"], "equal keys sort by id")
	t.eq(_ids(Z.sorted([_eb(6, Rect2(0, 0, 80, 80)), _eb(4, Rect2(200, 0, 80, 80))])), ["B4", "B6"], "equal building keys sort by id")
	# Transit beings: an earlier layer, not in the L6 list.
	var tr := _eg(11, Vector2(100, 10), "transit")
	t.eq(Z.layer(tr), "L4", "transit beings are in L4")
	t.eq(Z.layer(_eg(12, Vector2(0, 0), "eva")), "L6", "outside beings are in L6")
	t.eq(Z.layer(_eb(1, rect)), "L6", "buildings are in L6")
	t.eq(_ids(Z.sorted([tr, _eg(12, Vector2(100, 5)), _eb(1, rect)])), ["g12", "B1"], "transit beings are not in the L6 sort")


# ---------------------------------------------------------------- T-I: interiors

func _inside(ids: Array, state: String = "idle", suit_up: bool = false) -> Array:
	var out: Array = []
	for i in ids:
		out.append({"id": i, "state": state, "suit_up": suit_up})
	return out


func test_interior_slots_i(t) -> void:
	var M := _need(t, ["interior_slots"])
	if M.is_empty():
		return
	var art := _art()
	var size := Vector2(99, 68)
	var dt := 1.0 / 60.0
	var I = M.interior_slots
	# Deterministic: the same inputs twice (and reversed input order) give the same slot and position.
	var a = I.new(art, 1, "habitat", size)
	var b = I.new(art, 1, "habitat", size)
	var c = I.new(art, 1, "habitat", size)
	var ids := [1, 2, 3, 4, 5, 6, 7, 8]
	var rev := ids.duplicate()
	rev.reverse()
	for i in 900:
		a.update(dt, _inside(ids))
		b.update(dt, _inside(ids))
		c.update(dt, _inside(rev))
	for id in ids:
		t.eq(a.slot_of(id).get("id"), b.slot_of(id).get("id"), "same slot for being %d twice" % id)
		t.eq(a.positions()[id], b.positions()[id], "same position for being %d twice" % id)
		t.eq(a.slot_of(id).get("id"), c.slot_of(id).get("id"), "slot is a function of the sorted ids (being %d)" % id)
	# Sleepers: bunks in ascending id (3 bunks, 5 sleepers -> 2 on the floor), never shared.
	var s = I.new(art, 1, "habitat", size)
	var sleepers := _inside([7, 3, 6, 4, 5], "sleep")
	s.update(dt, sleepers)
	s.update(dt, sleepers)
	var bunks: Array = []
	for slot in art.interiors.habitat.slots:
		if slot.type == "bunk":
			bunks.append(slot)
	t.eq(bunks.size(), 3, "habitat has 3 bunks")
	for k in 3:
		t.eq(s.slot_of(3 + k).get("id"), bunks[k].id, "sleeper %d takes %s" % [3 + k, bunks[k].id])
		t.eq(s.slot_of(3 + k).get("type"), "bunk", "bunk type")
		var want := Vector2(bunks[k].pos[0], bunks[k].pos[1])
		t.near((s.positions()[3 + k] as Vector2).x, want.x, 1e-6, "sleeper %d lies at the bunk (x)" % [3 + k])
		t.near((s.positions()[3 + k] as Vector2).y, want.y, 1e-6, "sleeper %d lies at the bunk (y)" % [3 + k])
	var floor_ids: Array = []
	for id in [6, 7]:
		t.check(s.slot_of(id).get("type", "bunk") != "bunk", "sleeper %d is on the floor" % id)
		floor_ids.append(s.slot_of(id).get("id"))
	t.check(floor_ids[0] != floor_ids[1], "the two floor sleepers do not share a slot")
	# A sleeper that wakes leaves its bunk.
	var wk = I.new(art, 1, "habitat", size)
	wk.update(dt, _inside([3], "sleep"))
	t.eq(wk.slot_of(3).get("type"), "bunk", "the lone sleeper is in a bunk")
	wk.update(dt, _inside([3], "idle"))
	t.check(wk.slot_of(3).get("type", "bunk") != "bunk", "an awake being never keeps a bunk")
	# Kinds without an entry use the default grid (no bunks): sleepers lie on the floor.
	var d = I.new(art, 2, "archive", size)
	d.update(dt, _inside([1, 2], "sleep"))
	t.eq(d.slots().size(), art.interiors.default.slots.size(), "archive uses the default slots")
	t.check(d.slot_of(1).get("id") != d.slot_of(2).get("id"), "default: two sleepers, two slots")
	t.eq(d.slot_of(1).get("type"), "stand", "default: floor slot")
	# No slot shared among non-sleepers (12 beings, 15 slots), none in a bunk; walking stays inside; speed <= 10 px/s.
	var e = I.new(art, 1, "habitat", size)
	var crowd := range(1, 13)
	var shared_ok := true
	var inside_ok := true
	var bunk_ok := true
	var speed_ok := true
	var prev: Dictionary = {}
	for i in 3000:
		e.update(dt, _inside(crowd))
		var used := {}
		for id in crowd:
			var sl: Dictionary = e.slot_of(id)
			if sl.is_empty() or used.has(sl.id):
				shared_ok = false
			else:
				used[sl.id] = true
			if sl.get("type", "") == "bunk":
				bunk_ok = false
			var p: Vector2 = e.positions()[id]
			inside_ok = inside_ok and p.x >= 0.0 and p.x <= 1.0 and p.y >= 0.0 and p.y <= 1.0
			if prev.has(id):
				var dn: Vector2 = p - (prev[id] as Vector2)
				var dpx := Vector2(dn.x * size.x, dn.y * size.y).length()
				speed_ok = speed_ok and dpx <= 10.0 * dt + 1e-3
			prev[id] = p
	t.check(shared_ok, "no two beings share a slot")
	t.check(bunk_ok, "awake beings never take a bunk")
	t.check(inside_ok, "positions stay inside the interior rect")
	t.check(speed_ok, "interior walk is at most 10 px per second")
	# They actually move over a long run (pause 1.5..5 s, then a new slot).
	var moved := false
	var first: Dictionary = {}
	var f = I.new(art, 1, "habitat", size)
	for i in 4000:
		f.update(dt, _inside([1, 2, 3]))
		if i == 600:
			first = f.positions().duplicate()
	for id in [1, 2, 3]:
		if (f.positions()[id] as Vector2) != (first[id] as Vector2):
			moved = true
	t.check(moved, "beings walk between slots")
	# Cap: at most 25 drawn, the lowest ids.
	var big = I.new(art, 1, "habitat", size)
	var forty := range(1, 41)
	forty.reverse()
	big.update(dt, _inside(forty))
	big.update(dt, _inside(forty))
	var drawn: Array = big.drawn_ids()
	t.eq(drawn.size(), 25, "at most 25 beings drawn")
	t.eq(drawn, range(1, 26), "the lowest 25 ids are drawn")
	t.eq(big.positions().size(), 25, "positions only for the drawn beings")
	# Enter at the door; leave the same refresh.
	var g = I.new(art, 1, "habitat", size)
	g.update(dt, _inside([1]))
	g.update(0.0, _inside([1, 9]))
	var door := Vector2(art.interiors.habitat.door[0], art.interiors.habitat.door[1])
	t.near((g.positions()[9] as Vector2).x, door.x, 1e-6, "a being that enters appears at the door point (x)")
	t.near((g.positions()[9] as Vector2).y, door.y, 1e-6, "a being that enters appears at the door point (y)")
	g.update(dt, _inside([1]))
	t.check(not g.positions().has(9) and not g.drawn_ids().has(9), "a being that leaves disappears the same refresh")
	# A suiting-up being heads for the door and reaches it.
	var h = I.new(art, 1, "habitat", size)
	var su := [{"id": 4, "state": "to_door", "suit_up": true}]
	for i in 1500:
		h.update(dt, su)
	var p4: Vector2 = h.positions()[4]
	var dpx2 := Vector2((p4.x - door.x) * size.x, (p4.y - door.y) * size.y).length()
	t.check(dpx2 <= 0.8 + 1e-6, "a to_door suit_up being stands at the door point (%f px away)" % dpx2)


func test_interior_via_model_leaves_sim_alone(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := SimWorld.new(7)
	for i in 600:
		w.step()
	var before := _sig(w)
	var vm = M.view_model.new(w, art, _manifest())
	vm.camera.zoom = 6.0
	vm.camera_rect = Rect2(-100000, -100000, 200000, 200000)
	var opened := false
	for i in 10000:
		vm.update(1.0 / 60.0)
		if i == 200:
			for b in w.buildings.list:
				if vm.interior(b.id) != null:
					opened = true
	t.check(opened, "at zoom 6 the model builds interiors")
	t.eq(_sig(w), before, "sim state hash unchanged after 10,000 refreshes with open roofs")
	t.eq(int(vm.skipped), 0, "no being was skipped")


# ---------------------------------------------------------------- T-S: selection

func test_selection_s(t) -> void:
	var M := _need(t, ["selection"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var h1 := w.buildings.add("habitat", 10, 10, 1.0, 13, 9)
	var h2 := w.buildings.add("workshop", 40, 10, 1.0, 12, 9)
	var site := w.buildings.add("archive", 70, 10, 0.5, 12, 9)
	var S = M.selection
	var s = S.new(art)
	t.eq(int(s.selected), 0, "nothing selected at the start")
	var in1 := Vector2(h1.tx * 8 + 30, h1.ty * 8 + 20)
	var in2 := Vector2(h2.tx * 8 + 30, h2.ty * 8 + 20)
	s.tap(in1, w)
	t.eq(int(s.selected), h1.id, "tap on a footprint selects")
	t.eq(s.peek, false, "peek off after the first tap")
	s.tap(in1, w)
	t.eq(int(s.selected), h1.id, "tap again keeps the selection")
	t.eq(s.peek, true, "tap again sets peek")
	s.tap(in1, w)
	t.eq(s.peek, false, "tap again toggles peek off")
	s.tap(in1, w)
	t.eq(s.peek, true, "and on")
	s.tap(in2, w)
	t.eq(int(s.selected), h2.id, "tap another building moves the selection")
	t.eq(s.peek, false, "and clears peek")
	s.tap(Vector2(1000, 1000), w)
	t.eq(int(s.selected), 0, "tap on empty ground deselects")
	t.eq(s.peek, false, "deselect clears peek")
	# Drag threshold 6 px.
	t.check(s.is_tap(Vector2(100, 100), Vector2(103, 100)), "3 px is a tap")
	t.check(not s.is_tap(Vector2(100, 100), Vector2(107, 100)), "7 px is a drag")
	t.check(not s.is_tap(Vector2(100, 100), Vector2(105, 105)), "7.07 px diagonal is a drag")
	# Peek is ignored on a site.
	var in_site := Vector2(site.tx * 8 + 30, site.ty * 8 + 20)
	s.tap(in_site, w)
	t.eq(int(s.selected), site.id, "a site can be selected")
	s.tap(in_site, w)
	t.eq(s.peek, false, "peek stays off on a site")
	s.update(0.5, 2.0, w)
	t.eq(float(s.peek_cut), 0.0, "no roof opening on a site")
	t.eq(float(s.cut(site.id, 2.0)), 0.0, "cut 0 for a site at zoom 2")
	# Selection persists through completion.
	site.built = 1.0
	s.update(0.1, 2.0, w)
	t.eq(int(s.selected), site.id, "selection persists through completion")
	t.eq(s.peek, false, "peek false after completion")
	# cut at zoom 4.6, 5.0, 5.4 = 0, 0.5, 1.
	t.near(float(S.zoom_cut(4.6, art)), 0.0, 1e-9, "zoom cut at 4.6")
	t.near(float(S.zoom_cut(5.0, art)), 0.5, 1e-9, "zoom cut at 5.0")
	t.near(float(S.zoom_cut(5.4, art)), 1.0, 1e-9, "zoom cut at 5.4")
	t.near(float(S.zoom_cut(2.0, art)), 0.0, 1e-9, "zoom cut at 2.0")
	t.near(float(S.zoom_cut(6.0, art)), 1.0, 1e-9, "zoom cut at 6.0")
	var z = S.new(art)
	t.near(float(z.cut(h1.id, 5.0)), 0.5, 1e-9, "per building cut at zoom 5.0 (any building)")
	# peek_cut: 0 to 1 in 0.25 s, linear; cut = max(zoom cut, peek cut).
	var p = S.new(art)
	p.tap(in1, w)
	p.tap(in1, w)
	p.update(0.125, 2.0, w)
	t.near(float(p.peek_cut), 0.5, 1e-9, "peek_cut halfway after 0.125 s")
	t.near(float(p.cut(h1.id, 2.0)), 0.5, 1e-9, "cut follows peek_cut for the selected building")
	t.near(float(p.cut(h2.id, 2.0)), 0.0, 1e-9, "other buildings stay closed")
	p.update(0.125, 2.0, w)
	t.near(float(p.peek_cut), 1.0, 1e-9, "peek_cut 1 after 0.25 s")
	p.update(1.0, 2.0, w)
	t.near(float(p.peek_cut), 1.0, 1e-9, "peek_cut stops at 1")
	t.near(float(p.cut(h1.id, 5.0)), 1.0, 1e-9, "max of zoom cut and peek cut")
	p.tap(in1, w)
	p.update(0.25, 2.0, w)
	t.near(float(p.peek_cut), 0.0, 1e-9, "peek off: back to 0 in 0.25 s")
	# Outline source and pulse.
	t.eq(S.outline_source(0.49, art), "exterior", "exterior outline at cut 0.49")
	t.eq(S.outline_source(0.5, art), "interior", "interior outline at cut 0.5")
	var lo := 9.0
	var hi := -9.0
	for i in 2000:
		var pv := float(S.pulse(i * 0.01, art))
		lo = minf(lo, pv)
		hi = maxf(hi, pv)
	t.check(lo >= 0.24 - 1e-9 and hi <= 1.0 + 1e-9, "pulse within 0.24..1.0 (%f..%f)" % [lo, hi])
	t.near(lo, 0.24, 0.002, "pulse reaches 0.24")
	t.near(hi, 1.0, 0.002, "pulse reaches 1.0")
	t.near(float(S.pulse(0.3, art)), 0.62 + 0.38 * sin(0.3 * 3.2), 1e-9, "pulse formula")


# ---------------------------------------------------------------- T-CAM: camera

func test_camera_cam(t) -> void:
	var M := _need(t, ["camera"])
	if M.is_empty():
		return
	var art := _art()
	var union := Rect2(80, 60, 300, 200)
	var vp := Vector2(1280, 720)
	var C = M.camera
	var c = C.new(art, union)
	t.near(float(c.zoom), 2.0, 1e-12, "default zoom 2.0")
	t.eq(c.bounds(), union.grow(240.0), "bounds are the union grown by 240 px")
	# Zoom clamps from both directions.
	c.center = Vector2(230, 160)
	c.wheel(60, vp / 2.0, vp)
	t.eq(float(c.zoom), 6.0, "wheel in clamps at 6.0")
	c.wheel(-80, vp / 2.0, vp)
	t.eq(float(c.zoom), 0.6, "wheel out clamps at 0.6")
	c.reset(Vector2(230, 160))
	for i in 600:
		c.zoom_key(1, 1.0 / 60.0)
	t.eq(float(c.zoom), 6.0, "zoom key in clamps at 6.0")
	for i in 1200:
		c.zoom_key(-1, 1.0 / 60.0)
	t.eq(float(c.zoom), 0.6, "zoom key out clamps at 0.6")
	c.reset(Vector2(230, 160))
	for i in 60:
		c.zoom_key(1, 1.0 / 60.0)
	t.near(float(c.zoom), 2.0 * 1.8, 1e-9, "held for 1 s the zoom multiplies by 1.8")
	# Wheel keeps the world point under the cursor fixed; one notch is x1.12; out is the inverse.
	c.reset(Vector2(230, 160))
	var cursor := Vector2(900, 200)
	var before: Vector2 = c.screen_to_world(cursor, vp)
	c.wheel(1, cursor, vp)
	var after: Vector2 = c.screen_to_world(cursor, vp)
	t.near(float(c.zoom), 2.0 * 1.12, 1e-9, "one notch is x1.12")
	t.near(after.x, before.x, 1e-6, "cursor point fixed (x)")
	t.near(after.y, before.y, 1e-6, "cursor point fixed (y)")
	c.wheel(-1, cursor, vp)
	t.near(float(c.zoom), 2.0, 1e-9, "out is the inverse")
	var back: Vector2 = c.screen_to_world(cursor, vp)
	t.near(back.x, before.x, 1e-6, "cursor point fixed after the inverse (x)")
	# Pan speed 520 screen px per second (world speed / zoom), clamped to the bounds.
	c.reset(Vector2(230, 160))
	c.pan(Vector2(1, 0), 1.0)
	t.near((c.center as Vector2).x, 230.0 + 260.0, 1e-6, "pan 1 s at zoom 2 moves 260 world px")
	for i in 100:
		c.pan(Vector2(1, 1), 1.0)
	var bd: Rect2 = c.bounds()
	t.near((c.center as Vector2).x, bd.end.x, 1e-6, "pan clamps at the right bound")
	t.near((c.center as Vector2).y, bd.end.y, 1e-6, "pan clamps at the bottom bound")
	for i in 100:
		c.pan(Vector2(-1, -1), 1.0)
	t.near((c.center as Vector2).x, bd.position.x, 1e-6, "pan clamps at the left bound")
	t.near((c.center as Vector2).y, bd.position.y, 1e-6, "pan clamps at the top bound")
	# Zooming out keeps the centre inside the bounds too.
	c.wheel(-30, Vector2(0, 0), vp)
	var ctr: Vector2 = c.center
	t.check(ctr.x >= bd.position.x - 1e-6 and ctr.x <= bd.end.x + 1e-6 and ctr.y >= bd.position.y - 1e-6 and ctr.y <= bd.end.y + 1e-6, "centre stays inside the bounds after zooming")
	# Home.
	c.zoom = 5.0
	c.center = Vector2(-100, 400)
	c.reset(Vector2(230, 160))
	t.near(float(c.zoom), 2.0, 1e-12, "Home resets the zoom")
	t.eq(c.center, Vector2(230, 160), "Home centres on the given centroid")
	# Follow eases 0.08 of the distance per 60 Hz frame; user input cancels it.
	c.follow_target = Vector2(330, 160)
	c.follow = true
	c.update(1.0 / 60.0)
	t.near((c.center as Vector2).x, 230.0 + 0.08 * 100.0, 1e-6, "follow moves 8% of the distance in one 60 Hz frame")
	t.check(not c.follow_done(), "follow is not done yet")
	for i in 400:
		c.update(1.0 / 60.0)
	t.check(c.follow_done(), "follow is done within 0.5 px")
	t.near((c.center as Vector2).x, 330.0, 0.5, "follow arrives")
	c.follow_target = Vector2(300, 100)
	c.follow = true
	c.pan(Vector2(1, 0), 0.01)
	t.eq(c.follow, false, "a user pan cancels follow")
	c.follow = true
	c.wheel(1, vp / 2.0, vp)
	t.eq(c.follow, false, "a user zoom cancels follow")
	# Key map matches camera.keys.
	for action in art.camera.keys:
		for k in art.camera.keys[action]:
			t.eq(c.action_for_key(k), action, "key %s -> %s" % [k, action])
	t.eq(c.action_for_key("M"), "toggle_debug_map", "M toggles the debug map")
	t.eq(c.action_for_key("Home"), "reset", "Home resets")
	t.eq(c.action_for_key("Q"), "", "an unmapped key is nothing")


# ---------------------------------------------------------------- the facade reads the sim correctly

func test_transit_position_through_the_model(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var r := w.add_building("reactor", 10, 10)
	var c := w.buildings.add_attached("habitat", r, "r", 13, 9, 6)
	var a := w.add_being(r, "builder")
	a.state = "transit"
	a.corridor_id = c.id
	a.transit_t = 0.25
	a.from_a = true
	var b := w.add_being(r, "builder")
	b.state = "transit"
	b.corridor_id = c.id
	b.transit_t = 0.25
	b.from_a = false
	var vm = M.view_model.new(w, art, _manifest())
	vm.update(1.0 / 60.0)
	var p1: Vector2 = c.corridor.p1
	var p2: Vector2 = c.corridor.p2
	var want_a := p1 + (p2 - p1) * 0.25
	var want_b := p1 + (p2 - p1) * 0.75
	t.near((vm.being(a.id).pos as Vector2).x, want_a.x, 1e-3, "from_a: p1 + (p2 - p1) x transit_t (x)")
	t.near((vm.being(a.id).pos as Vector2).y, want_a.y, 1e-3, "from_a (y)")
	t.near((vm.being(b.id).pos as Vector2).x, want_b.x, 1e-3, "not from_a: s = 1 - transit_t (x)")
	t.near((vm.being(b.id).pos as Vector2).y, want_b.y, 1e-3, "not from_a (y)")
	t.eq(vm.being(a.id).visible, true, "a transit being is drawn")
	t.eq(int(vm.skipped), 0, "nothing skipped")


func test_walk_through_the_model(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var hab := w.add_building("habitat", 10, 10)
	var g := _outside(w, hab, 100.0, 120.0)
	var vm = M.view_model.new(w, art, _manifest())
	for i in 60:
		g.x = 100.0 + 0.5 * i
		vm.update(1.0 / 60.0)
	t.near(float(vm.being(g.id).phase), 59.0 * 0.5 * 1.25, 0.02, "phase follows the distance moved (59 steps of 0.5 px)")
	t.eq(vm.being(g.id).moving, true, "moving while it moves")
	var phase_before := float(vm.being(g.id).phase)
	for i in 20:
		vm.update(1.0 / 60.0)
	t.eq(vm.being(g.id).moving, false, "not moving 0.33 s after it stopped")
	t.near(float(vm.being(g.id).phase), phase_before, 1e-9, "the phase holds while it stands still (paused sim)")


func test_lamp_through_the_model(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var hab := w.add_building("habitat", 10, 10)
	var out := _outside(w, hab, 100.0, 120.0)
	var inn := w.add_being(hab, "builder")
	for case in [[23.0, 1.0], [12.0, 0.0], [20.25, 0.65]]:
		w.t = w.clock.sol_h * (3.0 + float(case[0]) / w.clock.clock_hours)
		var vm = M.view_model.new(w, art, _manifest())
		for i in 150:
			vm.update(1.0 / 60.0)
		t.near(float(vm.being(out.id).lamp_level), float(case[1]), 0.01, "outside lamp level at hour %s" % str(case[0]))
		t.near(float(vm.being(inn.id).lamp_level), 0.0, 1e-9, "inside lamp level at hour %s" % str(case[0]))


func test_interior_beings_through_the_model(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := _world()
	var hab := w.add_building("habitat", 10, 10)
	var ids: Array[int] = []
	for i in 3:
		var b := w.add_being(hab, "builder")
		b.earth_born = true
		ids.append(b.id)
	var out := _outside(w, hab, 60.0, 100.0)
	var vm = M.view_model.new(w, art, _manifest())
	for i in 5:
		vm.update(1.0 / 60.0)
	t.eq(vm.interior(hab), null, "roof closed at zoom 2: no interior model")
	for id in ids:
		t.eq(vm.being(id).visible, false, "a being inside a closed building is not drawn")
	t.eq(vm.being(out.id).visible, true, "an outside being is drawn")
	t.eq(vm.being(out.id).inside, false, "and is not an interior being")
	vm.camera.zoom = 6.0
	for i in 5:
		vm.update(1.0 / 60.0)
	t.check(vm.interior(hab) != null, "roof open at zoom 6: interior model exists")
	for id in ids:
		t.eq(vm.being(id).visible, true, "interior being %d is drawn" % id)
		t.eq(vm.being(id).inside, true, "interior being %d is inside" % id)
		t.near(float(vm.being(id).height_px), 7.6 * 1.9, 1e-9, "interior scale 1.9x")
	t.near(float(vm.being(out.id).height_px), 7.6, 1e-9, "outside scale unchanged")
	vm.camera.zoom = 2.0
	for i in 5:
		vm.update(1.0 / 60.0)
	t.eq(vm.interior(hab), null, "roof closed again: interior model dropped")
	# A being outside with no position is skipped and counted (spec section 14).
	var lost := _outside(w, hab, 0.0, 0.0)
	lost.x = null
	vm.update(1.0 / 60.0)
	t.check(int(vm.skipped) >= 1, "a being outside without x is skipped and counted")


# ---------------------------------------------------------------- T-DBG, T-RNG

func test_debug_toggle_dbg(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var w := SimWorld.new(7)
	for i in 200:
		w.step()
	var before := _sig(w)
	var vm = M.view_model.new(w, art, _manifest())
	t.eq(vm.debug_map, false, "default is the sprite view")
	vm.press_key("M")
	t.eq(vm.debug_map, true, "M switches to the debug map")
	vm.update(1.0 / 60.0)
	vm.press_key("Q")
	t.eq(vm.debug_map, true, "another key does not toggle")
	vm.press_key("M")
	t.eq(vm.debug_map, false, "M switches back")
	t.eq(_sig(w), before, "toggling leaves the sim state hash unchanged")


func test_model_leaves_the_sim_alone_rng(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	var wa := SimWorld.new(7)
	var wb := SimWorld.new(7)
	var vm = M.view_model.new(wa, art, man)
	vm.camera.zoom = 6.0
	vm.camera_rect = Rect2(-100000, -100000, 200000, 200000)
	var checkpoints := 0
	for frame in 10000:
		wa.step()
		wa.step()
		wb.step()
		wb.step()
		vm.update(1.0 / 60.0)
		if frame % 2500 == 2499:
			checkpoints += 1
			t.eq(_sig(wa), _sig(wb), "sim state, rng state and stats identical at frame %d" % frame)
			t.eq(wa.rng._rng.state, wb.rng._rng.state, "rng state identical at frame %d" % frame)
	t.eq(checkpoints, 4, "four checkpoints")
	t.near(float(vm.real_time), 10000.0 / 60.0, 1e-6, "the model ran 10,000 frames")
	t.check(wa.colony.pop() > 0 and wa.sol() >= 40, "the sim ran for sols (%d) with %d beings" % [wa.sol(), wa.colony.pop()])
	t.eq(int(vm.skipped), 0, "no being skipped")
	for b in wa.beings:
		t.check(vm.being(b.id) != null, "the model tracks being %d" % b.id)
		break
	# Short balance-style row: the same population, stocks, power and deaths with and without the model.
	var rows: Array[String] = []
	for row in [wa, wb]:
		rows.append("sol %d pop %d oxygen %.3f food %.3f ice %.3f regolith %.3f supply %.1f deaths %s births %d" % [
				row.sol(), row.colony.pop(), row.colony.oxygen, row.colony.food, row.colony.ice, row.colony.regolith,
				row.buildings.supply(), JSON.stringify(row.stats.deaths), int(row.stats.births)])
	t.eq(rows[0].sha256_text(), rows[1].sha256_text(), "balance row hash identical with and without the model")
	print("balance row (seed 7, 10,000 frames x 2 steps): " + rows[0])


func test_model_view_state_is_reproducible(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	var sigs: Array = []
	for run in 2:
		var w := SimWorld.new(7)
		var vm = M.view_model.new(w, art, man)
		vm.camera.zoom = 6.0
		vm.camera_rect = Rect2(-100000, -100000, 200000, 200000)
		for frame in 1500:
			w.step()
			vm.update(1.0 / 60.0)
		sigs.append(vm.signature())
	t.check(String(sigs[0]).length() > 8, "signature is a non-trivial string")
	t.eq(sigs[0], sigs[1], "same seed and inputs give identical view state")
	# A different dt sequence gives different view state (the signature is sensitive).
	var w2 := SimWorld.new(7)
	var vm2 = M.view_model.new(w2, art, man)
	vm2.camera.zoom = 6.0
	vm2.camera_rect = Rect2(-100000, -100000, 200000, 200000)
	for frame in 1500:
		w2.step()
		vm2.update(1.0 / 30.0)
	t.check(vm2.signature() != sigs[0], "a different dt sequence changes the view state")


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


## Source with comments and string contents removed (so a mention in a comment does not count).
func _code_only(src: String) -> String:
	var strip_str := RegEx.create_from_string("\"[^\"\\n]*\"|'[^'\\n]*'")
	var out: Array[String] = []
	for line in src.split("\n"):
		var s := strip_str.sub(line, "\"\"", true)
		var i := s.find("#")
		if i >= 0:
			s = s.substr(0, i)
		out.append(s)
	return "\n".join(out)


func test_no_global_random_in_view_rng(t) -> void:
	var files := _gd_files("res://view")
	t.check(files.size() >= 3, "the scan sees view scripts (%d)" % files.size())
	var bad := RegEx.create_from_string("SimRng|(?<![\\w.])(randomize|randf|randi|randf_range|randi_range|rand_from_seed)\\s*\\(|\\.pick_random\\s*\\(|\\.shuffle\\s*\\(")
	for f in files:
		var code := _code_only(FileAccess.get_file_as_string(f))
		var m := bad.search(code)
		t.check(m == null, "%s uses global or sim randomness: %s" % [f, m.get_string() if m else ""])
	# The scanner itself: it sees a violation.
	t.check(bad.search(_code_only("var x = randf()")) != null, "scan catches randf()")
	t.check(bad.search(_code_only("var r := SimRng.new(1)")) != null, "scan catches SimRng")
	t.check(bad.search(_code_only("var x = _rng.randf()")) == null, "scan allows a view-owned generator")
	t.check(bad.search(_code_only("# randf() in a comment")) == null, "scan ignores comments")
	# The model exists and owns its generators.
	var model_files := _gd_files("res://view/model")
	t.check(not model_files.is_empty(), "res://view/model/ exists and has scripts")
	var seeded := 0
	for f in model_files:
		if FileAccess.get_file_as_string(f).contains("RandomNumberGenerator"):
			seeded += 1
	t.check(seeded >= 1, "view/model owns RandomNumberGenerator instances (%d files)" % seeded)


# ---------------------------------------------------------------- T-DATA

func _esc(s: String) -> String:
	return s.replace(".", "\\.")


func _collect(node: Variant, path: Array, out: Array) -> void:
	if node is Dictionary and not (node as Dictionary).is_empty():
		for k in node:
			_collect(node[k], path + [String(k)], out)
	else:
		out.append(path)


## Leaves of art.json (as dotted paths) that spec section 13 does not name. A leaf is named when the text has its path
## or an ancestor path of two or more segments as a token (art.camera.keys.*), or a line of section 13 holds the
## leaf's key as a token and its group name (rows list siblings as "a.b.c / d / e").
func _unnamed_leaves(art: Dictionary, section: String) -> Array[String]:
	var leaves: Array = []
	_collect(art, [], leaves)
	section = section.replace("art.", "")
	var lines := section.split("\n")
	var out: Array[String] = []
	for p in leaves:
		var named := false
		for i in range(2, p.size() + 1):
			var pre := ".".join(PackedStringArray(p.slice(0, i)))
			var re := RegEx.create_from_string("(?<![\\w.])" + _esc(pre) + "(?![\\w])")
			if re.search(section) != null:
				named = true
				break
		if not named:
			var key_re := RegEx.create_from_string("(?<![\\w])" + _esc(p[p.size() - 1]) + "(?![\\w])")
			for line in lines:
				if line.contains(p[0]) and key_re.search(line) != null:
					named = true
					break
		if not named:
			out.append(".".join(PackedStringArray(p)))
	return out


func test_data_every_art_leaf_is_named_in_the_spec(t) -> void:
	var spec := FileAccess.get_file_as_string(SPEC_PATH)
	t.check(spec.length() > 1000, "spec readable")
	var i0 := spec.find("## 13. Tunables")
	var i1 := spec.find("## 14. Edge cases")
	t.check(i0 > 0 and i1 > i0, "spec section 13 found")
	var section := spec.substr(i0, i1 - i0)
	var art := _art()
	var missing := _unnamed_leaves(art, section)
	t.check(missing.is_empty(), "art.json leaves not named in spec section 13 (%d): %s" % [missing.size(), ", ".join(missing.slice(0, 20))])
	# Self-test: an unnamed key is reported.
	var mutated := art.duplicate(true)
	mutated.fit["zz_unlisted_key"] = 3
	var found := _unnamed_leaves(mutated, section)
	t.check("fit.zz_unlisted_key" in found, "the check reports a new unnamed leaf")
	t.eq(found.size(), missing.size() + 1, "and only that one")
	t.eq(int(art.schema), 1, "art.schema is 1")


func _literals(src: String) -> Array[String]:
	var code := _code_only(src)
	var num := RegEx.create_from_string("(?<![A-Za-z_0-9.])(\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?)(?![A-Za-z_0-9])")
	var idx := RegEx.create_from_string("\\[\\s*\\d+\\s*\\]")
	var out: Array[String] = []
	for line in code.split("\n"):
		var l: String = idx.sub(line, "[]", true)
		for m in num.search_all(l):
			var s := m.get_string()
			if s in ["0", "1", "2", "0.0", "1.0", "2.0"] or s in LITERAL_EXCEPTIONS:
				continue
			out.append("%s in `%s`" % [s, line.strip_edges()])
	return out


func test_data_no_tunable_literals_in_view_model(t) -> void:
	# The scanner first (so the test cannot pass by finding nothing).
	t.eq(_literals("var a = 0.25 + 3").size(), 2, "scan finds 0.25 and 3")
	t.eq(_literals("var a = 0 + 1 + 2.0 + b[3] # 7 in a comment").size(), 0, "0, 1, 2, indices and comments are fine")
	t.eq(_literals("var a = 60.0 * 0.5").size(), 0, "the listed exceptions are fine")
	t.eq(_literals("var a = 'x 9' + \"y 8\" + v2").size(), 0, "strings and identifiers with digits are fine")
	var files := _gd_files("res://view/model")
	t.check(not files.is_empty(), "res://view/model/ has scripts to scan")
	for f in files:
		var found := _literals(FileAccess.get_file_as_string(f))
		t.check(found.is_empty(), "%s has hard-coded numbers (%d), first: %s" % [f, found.size(), found[0] if not found.is_empty() else ""])


# ---------------------------------------------------------------- T-PERF

func test_perf_perf(t) -> void:
	var M := _need(t, ["view_model"])
	if M.is_empty():
		return
	var art := _art()
	var man := _manifest()
	# Texture memory: sum(w x h x 4) x 1.34 over entries with a real file, at most 48 MB.
	var real := 0.0
	var all_files := 0.0
	for id in man.entries:
		var e: Dictionary = man.entries[id]
		if e.get("file") != null:
			var bytes := float(e.w) * float(e.h) * 4.0
			all_files += bytes
			if not e.get("placeholder", false):
				real += bytes
	var mb_real := real * float(art.perf.mipmap_overhead) / 1048576.0
	var mb_all := all_files * float(art.perf.mipmap_overhead) / 1048576.0
	print("texture memory: %.1f MB real entries, %.1f MB with placeholder files (limit %s)" % [mb_real, mb_all, str(art.perf.texture_memory_mb_max)])
	t.check(mb_real <= float(art.perf.texture_memory_mb_max), "texture memory %.1f MB <= 48" % mb_real)
	t.check(mb_all <= float(art.perf.texture_memory_mb_max), "texture memory with placeholders %.1f MB <= 48" % mb_all)
	# 160 beings, about 20 outside, six buildings in a row, one open.
	var w := _world(42)
	var reactor := w.add_building("reactor", 10, 10)
	var ids: Array[int] = [reactor]
	var kinds := ["habitat", "workshop", "green_room", "archive", "comms"]
	for i in 5:
		ids.append(w.buildings.add_attached(kinds[i], ids[i], "r", 12, 9, 6).id)
	for i in 160:
		var b := w.add_being(ids[i % ids.size()], "builder")
		b.earth_born = i % 3 != 0
		if i < 20:
			b.state = "eva" if i % 2 == 0 else "mining"
			b.x = 100.0 + i * 9.0
			b.y = 140.0 + (i % 5) * 7.0
			b.heading = i * 0.7
			b.air_h = 30.0
			b.wait_h = 1.0 if i % 4 == 1 else 0.0
		elif i % 7 == 0:
			b.state = "sleep"
	var vm = M.view_model.new(w, art, man)
	var open_b: Buildings.Building = w.buildings.get_building(ids[1])
	var inside := Vector2(open_b.tx * 8 + 30, open_b.ty * 8 + 20)
	vm.selection.tap(inside, w)
	vm.selection.tap(inside, w)
	for i in 30:
		vm.update(1.0 / 60.0)
	t.near(float(vm.selection.peek_cut), 1.0, 1e-9, "one building is open")
	var times: Array[float] = []
	for i in 200:
		for b in w.beings:
			if b.is_outside():
				b.x += 0.2
		var t0 := Time.get_ticks_usec()
		vm.update(1.0 / 60.0)
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
	times.sort()
	var median := times[int(times.size() * 0.5)]
	print("view model update, 160 beings, %d refreshes: median %.3f ms, max %.3f ms (limit %s ms; headless)" % [times.size(), median, times[times.size() - 1], str(art.perf.model_update_ms_max)])
	t.check(median <= float(art.perf.model_update_ms_max), "median update %.3f ms <= 2.0 ms" % median)
	t.eq(int(vm.skipped), 0, "no being skipped at 160 beings")
