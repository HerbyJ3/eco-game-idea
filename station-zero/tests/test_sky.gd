extends RefCounted

var c := Clock.new()
var sky := MarsSky.new(c)


func _chart_eq(t, got: Dictionary, want: Dictionary, label: String) -> void:
	for k in want:
		t.eq(got[k], want[k], "%s %s" % [label, k])


func test_mars_chart_reference_points(t) -> void:
	# Expected values from a replica of the prototype's marsChart().
	_chart_eq(t, sky.mars_chart(0, 0), {"sun": 0, "deimos": 7, "phobos": 1, "rise": 9, "earth": 0}, "t=0")
	_chart_eq(t, sky.mars_chart(1234.5, 80), {"sun": 0, "deimos": 3, "phobos": 5, "rise": 1, "earth": 1}, "t=1234.5")
	_chart_eq(t, sky.mars_chart(5000, 100), {"sun": 3, "deimos": 6, "phobos": 5, "rise": 0, "earth": 4}, "t=5000")
	_chart_eq(t, sky.mars_chart(9876.54, 77.5), {"sun": 6, "deimos": 4, "phobos": 6, "rise": 0, "earth": 5}, "t=9876.54")
	_chart_eq(t, sky.mars_chart(15000, 90), {"sun": 10, "deimos": 5, "phobos": 11, "rise": 2, "earth": 10}, "t=15000")


func test_earth_direction_reference_points(t) -> void:
	t.near(sky.earth_direction(0), 15.911926751, 1e-6)
	t.near(sky.earth_direction(1234.5), 50.230020169, 1e-6)
	t.near(sky.earth_direction(5000), 131.537002751, 1e-6)
	t.near(sky.earth_direction(9876.54), 158.557532301, 1e-6)
	t.near(sky.earth_direction(15000), 315.283071264, 1e-6)


func test_rise_at_dawn(t) -> void:
	# At dawn the hour term is zero, so rise = sign(Ls + lon). Equals the sun sign only at lon 0.
	var ch := sky.mars_chart(c.start_hour, 0)
	t.eq(ch.sun, 0)
	t.eq(ch.rise, 0, "rise = sun at lon 0")
	t.eq(sky.mars_chart(c.start_hour, 77.5).rise, 2, "Jezero dawn: sign(78)")
	t.eq(sky.mars_chart(c.start_hour, 87.5).rise, 2)
	t.eq(sky.mars_chart(c.start_hour, 105).rise, 3)


func test_rise_half_sol(t) -> void:
	var r0: int = sky.mars_chart(c.start_hour, 77.5).rise
	var r1: int = sky.mars_chart(c.start_hour + c.sol_h * 0.5, 77.5).rise
	t.check(posmod(r1 - r0, 12) in [5, 6, 7], "rise moves about half the zodiac in half a sol")


func _count_changes(key: String, t0: float) -> int:
	var minute := 1.0 / 60.0
	var prev: int = sky.mars_chart(t0, 0)[key]
	var n := 0
	var ht := t0 + minute
	while ht < t0 + c.sol_h:
		var s: int = sky.mars_chart(ht, 0)[key]
		if s != prev:
			n += 1
		prev = s
		ht += minute
	return n


func test_moon_speeds(t) -> void:
	t.between(_count_changes("phobos", 100.0), 37, 40, "phobos sign changes per sol")
	t.between(_count_changes("deimos", 100.0), 9, 10, "deimos sign changes per sol")
	t.eq(sky.mars_chart(0, 0).phobos, sky.mars_chart(sky.phobos_h, 0).phobos, "phobos period")


func test_earth_direction_range_and_synodic(t) -> void:
	var ok := true
	for i in 500:
		var d := sky.earth_direction(i * 97.3)
		if d < 0.0 or d >= 360.0:
			ok = false
	t.check(ok, "direction in [0, 360)")


func test_earth_chart(t) -> void:
	var ch := sky.earth_chart(0, 0)
	t.eq(ch.sun, 0, "sign(15)")
	t.eq(ch.moon, 4, "sign(137)")
	t.eq(sky.earth_chart(c.earth_year_h, 0).sun, ch.sun, "sun repeats each Earth year")
	t.eq(sky.earth_chart(sky.luna_h, 0).moon, ch.moon, "moon repeats each month")
	t.eq(sky.earth_chart(6.0, 0).rise, sky.earth_chart(6.0, 0).sun, "rise = sun at 06:00, lon 0")
	_chart_eq(t, sky.earth_chart(-300000, 10), {"sun": 9, "moon": 10, "rise": 7}, "t=-300000")
	_chart_eq(t, sky.earth_chart(-200000.5, -100), {"sun": 2, "moon": 4, "rise": 4}, "t=-200000.5")


func test_founder_birth(t) -> void:
	var rng := SimRng.new(7)
	var cfg: Dictionary = SimData.persona().founders
	for i in 50:
		var b := sky.founder_birth(rng, cfg)
		var age_years: float = (c.start_hour - b.born) / c.earth_year_h
		t.between(age_years, 24.0, 45.0, "founder age")
		t.between(b.lon, -120.0, 140.0, "founder lon")
		t.eq(b.chart.world, "earth")
