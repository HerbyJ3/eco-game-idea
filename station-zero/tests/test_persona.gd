extends RefCounted

var per := Persona.new()


func _mars(a: int, b: int, c: int, d: int, e: int) -> Dictionary:
	return {"world": "mars", "sun": a, "deimos": b, "phobos": c, "rise": d, "earth": e}


func _near_all(t, got: Dictionary, want: Dictionary, label: String) -> void:
	for k in want:
		t.near(got[k], want[k], 1e-6, "%s %s" % [label, k])


func test_sign_table(t) -> void:
	var names := ["The Spark", "The Monolith", "The Twin Signal", "The Tide Shell", "The Crown Star",
		"The Lattice", "The Balance Arc", "The Deep Lantern", "The Far Arrow", "The Summit",
		"The Relay", "The Drift"]
	var els := ["fire", "earth", "air", "water"]
	var mods := ["cardinal", "fixed", "mutable"]
	for i in 12:
		t.eq(per.signs[i].name, names[i])
		t.eq(per.signs[i].element, els[i % 4], "element %d" % i)
		t.eq(per.signs[i].modality, mods[i % 3], "modality %d" % i)


func test_hand_calc_all_spark(t) -> void:
	var raw := per.raw_traits(_mars(0, 0, 0, 0, 0))
	t.near(raw.drive, 1.24 * 1.06, 1e-9, "raw drive")
	t.near(raw.restless, 0.72 * 1.14, 1e-9, "raw restless")
	var p := per.traits_from_raw(raw)
	t.near(p.drive, 1.0, 1e-12, "drive clamped")
	t.near(p.restless, 0.7472, 1e-9, "restless")


func test_reference_personas(t) -> void:
	# Expected values from a replica of the prototype's personaFrom/roleOf/describe.
	var p := per.traits(_mars(3, 7, 2, 10, 5))
	_near_all(t, p, {"drive": 0.276, "curiosity": 0.472933333, "sociability": 0.615333333,
		"care": 0.66, "restless": 0.3192, "steady": 0.412666667}, "chart A")
	t.eq(per.role_of(p), "social")
	t.eq(per.describe(p), "nurturing and warm")

	p = per.traits(_mars(11, 11, 11, 11, 11))
	_near_all(t, p, {"drive": 0.2, "curiosity": 0.3296, "sociability": 0.680666667,
		"care": 0.886666667, "restless": 0.428, "steady": 0.2152}, "chart B")
	t.eq(per.role_of(p), "tender")

	p = per.traits({"world": "earth", "sun": 4, "moon": 9, "rise": 1})
	_near_all(t, p, {"drive": 0.681333333, "curiosity": 0.2, "sociability": 0.2,
		"care": 0.354666667, "restless": 0.288, "steady": 0.770133333}, "earth chart")
	t.eq(per.role_of(p), "builder")
	t.eq(per.describe(p), "steady and driven")


func test_boost_routing(t) -> void:
	# The Drift (11, water mutable): care/sociability scale with inner, restless/steady with outer.
	var d := per.raw_traits(_mars(0, 11, 0, 0, 0))
	var base := per.raw_traits(_mars(0, 0, 0, 0, 0))
	# Deimos slot: weight .2, inner 1.5, outer .8.
	t.near(d.care - base.care, 0.2 * 1.5 * 1.0, 1e-9, "care via inner")
	t.near(d.sociability - base.sociability, 0.2 * 1.5 * 0.7, 1e-9, "sociability via inner")
	t.near(d.restless - base.restless, 0.2 * 0.8 * (0.3 - 0.72), 1e-9, "restless via outer")


func test_trait_ranges_over_all_charts(t) -> void:
	# Exhaustive over all 12^5 Mars charts. Expected ranges from a replica of the prototype.
	# The lower clamp is never reached by Mars charts; the upper clamp is (drive, curiosity, steady).
	var lo := {}
	var hi := {}
	for k: String in per.dims:
		lo[k] = 1e9
		hi[k] = -1e9
	for a in 12:
		for b in 12:
			for c in 12:
				for d in 12:
					for e in 12:
						var p := per.traits(_mars(a, b, c, d, e))
						for k: String in p:
							lo[k] = minf(lo[k], p[k])
							hi[k] = maxf(hi[k], p[k])
	_near_all(t, lo, {"drive": 0.2, "curiosity": 0.2, "sociability": 0.2, "care": 0.2,
		"restless": 0.0176, "steady": 0.0632}, "min")
	_near_all(t, hi, {"drive": 1.0, "curiosity": 1.0, "sociability": 0.680666667,
		"care": 0.886666667, "restless": 0.884, "steady": 1.0}, "max")
	var ok := true
	for a in 12:
		for b in 12:
			for c in 12:
				var p := per.traits({"world": "earth", "sun": a, "moon": b, "rise": c})
				for k in p:
					if p[k] < 0.0 or p[k] > 1.0:
						ok = false
	t.check(ok, "all 12^3 Earth charts in [0, 1]")


func _p(drive: float, curiosity: float, sociability: float, care: float) -> Dictionary:
	return {"drive": drive, "curiosity": curiosity, "sociability": sociability, "care": care,
		"restless": 0.0, "steady": 0.0}


func test_role_weights(t) -> void:
	t.eq(per.role_of(_p(0.5, 0.5, 0.5, 0.5)), "social", "equal traits")
	t.eq(per.role_of(_p(0.9, 0.0, 0.78, 0.0)), "social", ".792 < .905")
	t.eq(per.role_of(_p(0.9, 0.0, 0.60, 0.0)), "builder", ".792 > .696")
	t.eq(per.role_of(_p(0.0, 0.0, 0.0, 0.0)), "builder", "all-zero tie goes to first")
	t.eq(per.role_of(_p(0.0, 0.5, 0.0, 0.0)), "curious")
	t.eq(per.role_of(_p(0.0, 0.0, 0.0, 0.5)), "tender")


func test_describe(t) -> void:
	var p := _p(0.1, 0.2, 0.3, 0.4)
	p.restless = 0.9
	p.steady = 0.8
	t.eq(per.describe(p), "restless and nurturing", "restless never pairs with steady")
	p.restless = 0.7
	t.eq(per.describe(p), "steady and nurturing", "steady never pairs with restless")
	t.eq(per.describe(_p(0.5, 0.5, 0.1, 0.1)), "driven and inquisitive", "ties keep dims order")


func test_persona_from_is_deterministic(t) -> void:
	var ch := _mars(1, 2, 3, 4, 5)
	t.eq(per.persona_from(ch), per.persona_from(ch))
	t.check(not per.persona_from(ch).has("chart"), "chart stays hidden")
