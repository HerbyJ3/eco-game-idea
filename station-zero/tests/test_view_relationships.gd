extends RefCounted
## Task 4, step 3: the view half of spec docs/specs/relationships.md section 14 test 16 (talk gradient, section 10.1) plus the
## "no bond value reaches the view" source scan. Red until step 4 (the module and `debug_set_bond`) and step 8 (the gradient in
## view_model._talk_flags and the two art keys); the file compiles today (everything is dynamic), so it stays live and fails
## cleanly through `_api()`.
##
## Staging (spec 14 test 16): a blank world with one habitat and four beings (ids 1 to 4) awake and idle inside it; the view
## model is built by hand (ViewModel.new(world, art, manifest)); its interior model for the habitat is injected (no roof
## logic, no update(): _interiors / _interior_rects are set directly and the InteriorSlots records are written so that each
## being is `paused` at a stand slot at a chosen normalised position). `real_time` is set directly. The interior rect is
## 100 x 100 px and interior.talk_radius_px is 10, so positions 0.05 apart (5 px) are neighbours and positions 0.6 apart are not.
##
## API ASSUMED (the spec names the behaviour, not the shape of the result):
##  - `view_model._talk_flags()` still returns {being id: Dictionary}; a being is "talking" exactly when its id is a key
##    (today: every paused awake being with a neighbour in range). A non-friend pair that is in its quiet part of the stranger
##    cycle has NO key (the being shows idle-front). The Dictionary keeps the key `first` (bool: the lower id of the pair
##    speaks first); extra keys are tolerated, so the Task 3 equality at share 1.0 is checked on the id set and on `first`.
##  - Art keys: art.interior.stranger_talk_share and art.interior.stranger_talk_cycle_s (read live from the art Dictionary the
##    view model holds, so a test can edit them; restored at the end).
##  - Phase (spec 10.1): a non-friend pair with lower id lo talks iff
##    fposmod(real_time / stranger_talk_cycle_s + lo x 0.618034, 1.0) < stranger_talk_share.

const RADIUS := 10.0
const PHI := 0.618034

var _undo: Array = []


func _abort_msg(t) -> String:
	return "%s: aborted before its last line (a runtime error in the code under test?)" % t._current


func _begin(t) -> void:
	t._failures.append(_abort_msg(t))


func _end(t) -> void:
	while not _undo.is_empty():
		var u: Array = _undo.pop_back()
		if u[3]:
			u[0][u[1]] = u[2]
		else:
			u[0].erase(u[1])
	t._failures.erase(_abort_msg(t))


func _edit(dict: Dictionary, key: String, value: Variant) -> void:
	_undo.append([dict, key, dict.get(key), dict.has(key)])
	dict[key] = value


func _art() -> Dictionary:
	return SimData.load_json("art.json")


func _manifest() -> Dictionary:
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://assets/processed/manifest.json"))
	return m if m is Dictionary else {"schema": 1, "entries": {}}


func _api(t) -> bool:
	var missing: Array[String] = []
	var w = SimWorld.new(1, {"blank": true})
	if not ("relationships" in w) or w.relationships == null:
		missing.append("SimWorld.relationships")
	elif not w.relationships.has_method("debug_set_bond") or not w.relationships.has_method("are_friends"):
		missing.append("Relationships.debug_set_bond / are_friends")
	var art := _art()
	for k in ["stranger_talk_share", "stranger_talk_cycle_s"]:
		if not art.interior.has(k):
			missing.append("art.interior.%s" % k)
	t.check(missing.is_empty(), "missing API: " + ", ".join(PackedStringArray(missing)))
	if missing.is_empty():
		_begin(t)
	return missing.is_empty()


## {world, vm, hab, bid}; four beings (ids 1 to 4) inside one habitat, injected as paused at the given normalised x (y 0.5).
func _stage(xs: Dictionary) -> Dictionary:
	var w = SimWorld.new(1, {"blank": true})
	w.add_building("reactor", 0, 0)
	var bid: int = w.add_building("habitat", 40, 0)
	for i in 4:
		var b = w.add_being(bid)
		b.energy = 70.0
	var vm = load("res://view/model/view_model.gd").new(w, _art(), _manifest())
	var IS = load("res://view/model/interior_slots.gd")
	var model = IS.new(_art(), bid, "habitat", Vector2(100.0, 100.0))
	var slot := 0
	for i in model.slots().size():
		if model.slots()[i].type != "bunk":
			slot = i
			break
	for id in xs:
		model._recs[id] = {"pos": Vector2(float(xs[id]), 0.5), "slot": slot, "pause": 5.0, "waiting": true,
				"shared": false, "id": id, "rng": RandomNumberGenerator.new()}
	var ids: Array[int] = []
	for id in xs:
		ids.append(int(id))
	ids.sort()
	model._drawn = ids
	vm._interiors[bid] = model
	vm._interior_rects[bid] = Rect2(0.0, 0.0, 100.0, 100.0)
	return {"world": w, "vm": vm, "bid": bid}


func _talking(vm, id: int) -> bool:
	return vm._talk_flags().has(id)


func _cycle() -> float:
	return float(_art().interior.stranger_talk_cycle_s)


func _share() -> float:
	return float(_art().interior.stranger_talk_share)


func test_t16a_friend_pair_talks_through_the_whole_cycle_and_both_agree(t) -> void:
	if not _api(t):
		return
	var s := _stage({1: 0.10, 2: 0.15, 3: 0.90})
	s.world.relationships.debug_set_bond(1, 2, 0.5)
	t.check(s.world.relationships.are_friends(1, 2), "staging: 1 and 2 are friends")
	var vm = s.vm
	var always := true
	var agree := true
	for i in 100:
		vm.real_time = float(i) * _cycle() / 100.0
		var f: Dictionary = vm._talk_flags()
		always = always and f.has(1) and f.has(2)
		agree = agree and f.has(1) == f.has(2)
	t.check(always, "a friend pair talks at every one of 100 samples across a 5 s cycle")
	t.check(agree, "both beings of a mutual pair show the same state at every sample")
	t.check(not _talking(vm, 3), "a lone being with no neighbour in range does not talk")
	_end(t)


func test_t16b_stranger_pair_talks_in_the_share_and_follows_the_phase(t) -> void:
	if not _api(t):
		return
	var s := _stage({1: 0.10, 2: 0.15, 3: 0.90})
	var vm = s.vm
	t.check(not s.world.relationships.are_friends(1, 2), "staging: 1 and 2 are strangers")
	var talks := 0
	var agree := true
	var formula := true
	for i in 100:
		vm.real_time = float(i) * _cycle() / 100.0
		var f: Dictionary = vm._talk_flags()
		var want := fposmod(vm.real_time / _cycle() + 1.0 * PHI, 1.0) < _share()
		formula = formula and f.has(1) == want and f.has(2) == want
		agree = agree and f.has(1) == f.has(2)
		if f.has(1):
			talks += 1
	t.check(absf(float(talks) / 100.0 - _share()) <= 0.02, "stranger pair talks in %d of 100 samples (share %s +/- 0.02)" % [talks, str(_share())])
	t.check(agree, "both beings of a mutual stranger pair show the same state")
	t.check(formula, "the state follows fposmod(real_time / cycle + lo x 0.618034, 1) < share")
	_end(t)


func test_t16c_two_stranger_pairs_with_different_lo_are_not_in_phase(t) -> void:
	if not _api(t):
		return
	var s := _stage({1: 0.05, 2: 0.10, 3: 0.80, 4: 0.85})
	var vm = s.vm
	var a: Array = []
	var b: Array = []
	for i in 100:
		vm.real_time = float(i) * _cycle() / 100.0
		var f: Dictionary = vm._talk_flags()
		a.append(f.has(1))
		b.append(f.has(3))
	t.check(a != b, "pairs (1,2) and (3,4) talk at different moments")
	var both := 0
	for i in 100:
		if a[i] and b[i]:
			both += 1
	t.check(both < 20, "and not mostly at the same time (%d of 100 together)" % both)
	t.check(a.has(true) and b.has(true), "each pair does talk at times")
	_end(t)


func test_t16d_share_one_restores_task_3(t) -> void:
	if not _api(t):
		return
	var s := _stage({1: 0.10, 2: 0.15, 3: 0.90})
	var vm = s.vm
	_edit(_art().interior, "stranger_talk_share", 1.0)
	var ok := true
	for i in 50:
		vm.real_time = float(i) * 0.37
		var f: Dictionary = vm._talk_flags()
		ok = ok and f.keys() == [1, 2] and bool(f[1].get("first")) and not bool(f[2].get("first"))
	t.check(ok, "share 1.0: always exactly beings 1 and 2, `first` true for the lower id (the Task 3 output)")
	# Non-mutual choice: 3 picks the lowest id in range (1), 2 picks 1, 1 picks 2: all three talk, first as in Task 3.
	var s2 := _stage({1: 0.10, 2: 0.15, 3: 0.20})
	var f2: Dictionary = s2.vm._talk_flags()
	t.check(f2.has(1) and f2.has(2) and f2.has(3), "share 1.0, three beings in range: all talk")
	t.check(bool(f2[1].get("first")) and not bool(f2[2].get("first")) and not bool(f2[3].get("first")),
			"first = (id < chosen partner), exactly as Task 3")
	_end(t)


func test_t16e_no_bond_value_reaches_the_view(t) -> void:
	_begin(t)
	var forbidden := [".pairs", "bond", "friend_count", "web_share", "second_share", "lonely_share", "friends_mean",
			"stats.relationships", ".present", "found_friend", "crew_drift_named"]
	var files: Array[String] = []
	_collect("res://view", files)
	t.check(files.size() > 10, "the view sources were found (%d files)" % files.size())
	for f in files:
		var src := FileAccess.get_file_as_string(f)
		for w in forbidden:
			t.check(not src.contains(w), "%s does not mention '%s'" % [f, w])
	_end(t)


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
