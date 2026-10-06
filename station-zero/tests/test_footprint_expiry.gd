extends RefCounted
## expire_footprints keeps exactly what the original full pass kept (perf step 10: the faded prefix shortcut).


static func _reference(prints: Array, t: float, fade_h: float) -> Array:
	var keep: Array = []
	for f in prints:
		if not (t - f.t > fade_h + SimWorld.STEP_EPS):
			keep.append(f)
	return keep


func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true


func test_expiry_matches_full_pass_in_order(t) -> void:
	var w := SimWorld.new(1, {"blank": true})
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var now := 0.0
	var ok := true
	for step in 3000:
		now += 0.05
		for k in rng.randi_range(0, 3):
			w.resources.add_footprint(1.0, 2.0, 0.0, now, false)
		var want := _reference(w.resources.footprints, now, 2.0)
		w.resources.expire_footprints(now, 2.0)
		if not _same(want, w.resources.footprints):
			ok = false
			break
	t.check(ok, "sorted prints: same survivors as the full pass at every step")
	t.check(w.resources.footprints.size() > 0, "some prints survive")


func test_expiry_matches_full_pass_out_of_order(t) -> void:
	var w := SimWorld.new(1, {"blank": true})
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var now := 50.0
	var ok := true
	for step in 400:
		now += 0.3
		for k in rng.randi_range(0, 3):
			w.resources.add_footprint(1.0, 2.0, 0.0, now - rng.randf_range(0.0, 6.0), k == 1)
		var want := _reference(w.resources.footprints, now, 2.0)
		w.resources.expire_footprints(now, 2.0)
		if not _same(want, w.resources.footprints):
			ok = false
			break
	t.check(ok, "unsorted prints: same survivors as the full pass at every step")


func test_expiry_after_clear_and_equal_age_boundary(t) -> void:
	var w := SimWorld.new(1, {"blank": true})
	w.resources.add_footprint(0, 0, 0, 10.0, false)
	w.resources.add_footprint(0, 0, 0, 5.0, false)  # out of order
	w.resources.footprints.clear()
	w.resources.add_footprint(0, 0, 0, 1.0, false)
	w.resources.add_footprint(0, 0, 0, 2.0, false)
	w.resources.expire_footprints(3.0, 2.0)  # age 2.0 exactly: kept (not strictly older)
	t.eq(w.resources.footprints.size(), 2)
	w.resources.expire_footprints(3.0 + 1e-6, 2.0)
	t.eq(w.resources.footprints.size(), 1)
