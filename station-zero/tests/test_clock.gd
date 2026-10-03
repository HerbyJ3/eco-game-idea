extends RefCounted

var c := Clock.new()


func test_constants(t) -> void:
	t.near(c.sol_h, 24.6597, 1e-12, "SOL_H")
	t.near(c.year_h, 686.98 * 24, 1e-9, "YEAR_H")
	t.near(c.earth_year_h, 365.256 * 24, 1e-9, "EARTH_YEAR_H")
	t.near(c.start_hour, 24.6597 * 0.25, 1e-12, "START_HOUR")
	t.near(c.sols_per_year(), 668.60, 0.01, "sols per year")


func test_mod360_and_sign(t) -> void:
	t.near(Clock.mod360(-1), 359, 1e-12)
	t.near(Clock.mod360(361), 1, 1e-12)
	t.near(Clock.mod360(360), 0, 1e-12)
	t.near(Clock.mod360(-360), 0, 1e-12)
	t.eq(c.sign_of(0), 0)
	t.eq(c.sign_of(29.999), 0)
	t.eq(c.sign_of(30), 1)
	t.eq(c.sign_of(359.999), 11)
	t.eq(c.sign_of(360), 0)
	t.eq(c.sign_of(-1), 11)
	t.between(c.sign_of(-1e-15), 0, 11, "tiny negative stays in range (fposmod can round to 360)")


func test_ls_at_founding(t) -> void:
	t.near(c.mars_ls(0), 0.378014432, 1e-6, "Ls(0)")
	t.near(c.mars_ls(c.start_hour), 0.506, 0.01, "Ls(START_HOUR)")
	t.eq(c.sign_of(c.mars_ls(c.start_hour)), 0, "founding sun sign")
	t.eq(c.season(c.start_hour), "northern spring")
	t.eq(c.year_index(c.start_hour), 1, "year 1")
	t.eq(c.sol_index(c.start_hour), 1, "sol 1")


func test_ls_reference_points(t) -> void:
	# From a replica of the prototype's marsLs().
	t.near(c.mars_ls(1234.5), 25.02477196, 1e-6)
	t.near(c.mars_ls(5000), 94.640280469, 1e-6)
	t.near(c.mars_ls(9876.54), 197.412540365, 1e-6)
	t.near(c.mars_ls(15000), 327.793762583, 1e-6)


func test_ls_periodic_and_monotonic(t) -> void:
	var ok_range := true
	var monotonic := true
	var prev := c.mars_ls(0)
	for s in range(1, 670):
		var ht := s * c.sol_h
		var ls := c.mars_ls(ht)
		if ls < 0.0 or ls >= 360.0:
			ok_range = false
		var d := Clock.mod360(ls - prev)
		if d <= 0.0 or d > 5.0:
			monotonic = false
		prev = ls
	t.check(ok_range, "Ls in [0, 360)")
	t.check(monotonic, "Ls increases every sol")
	t.near(c.mars_ls(1000 + c.year_h), c.mars_ls(1000), 1e-6, "periodic over a year")


func test_sign_lengths(t) -> void:
	# Scan one year in 0.1-sol steps; measure how long the sun stays in each sign.
	var step := c.sol_h * 0.1
	var lengths := {}
	var cur := c.sign_of(c.mars_ls(0))
	var start := -1.0
	var ht := 0.0
	while ht < c.year_h * 2.0:
		var s := c.sign_of(c.mars_ls(ht))
		if s != cur:
			if start >= 0.0 and not lengths.has(s - 1 if s > 0 else 11):
				lengths[cur] = (ht - start) / c.sol_h
			cur = s
			start = ht
		ht += step
	t.eq(lengths.size(), 12, "all signs measured")
	var lo := 1e9
	var hi := 0.0
	var lo_sign := -1
	var hi_sign := -1
	var total := 0.0
	for k in lengths:
		total += lengths[k]
		if lengths[k] < lo:
			lo = lengths[k]
			lo_sign = k
		if lengths[k] > hi:
			hi = lengths[k]
			hi_sign = k
	t.between(lo, 46.0, 47.0, "shortest sign (sols)")
	t.between(hi, 66.0, 67.0, "longest sign (sols)")
	t.eq(lo_sign, 8, "shortest is near perihelion")
	t.eq(hi_sign, 2, "longest is near aphelion")
	t.near(total, c.sols_per_year(), 0.5, "signs sum to a year")


func test_mars_hour(t) -> void:
	t.near(c.mars_hour(0), 0, 1e-12)
	t.near(c.mars_hour(c.start_hour), 6.0, 1e-9, "dawn")
	t.near(c.mars_hour(c.sol_h * 0.5), 12.0, 1e-9)
	t.between(c.mars_hour(-1), 0.0, 23.999999, "negative t")
	t.near(c.mars_hour(-1), 24.0 - 24.0 / c.sol_h, 1e-9)
	var h := c.mars_hour(c.sol_h)
	t.check(h >= 0.0 and h < 24.0, "hour stays in [0, 24)")


func test_seasons(t) -> void:
	t.eq(c.season_of_ls(0), "northern spring")
	t.eq(c.season_of_ls(89.9), "northern spring")
	t.eq(c.season_of_ls(90), "northern summer")
	t.eq(c.season_of_ls(180), "northern autumn")
	t.eq(c.season_of_ls(270), "northern winter")
	t.eq(c.season_of_ls(359.9), "northern winter")


func test_counting(t) -> void:
	t.eq(c.sol_index(0), 1)
	t.eq(c.sol_index(c.sol_h - 1e-6), 1)
	t.eq(c.sol_index(c.sol_h), 2)
	t.eq(c.year_index(c.year_h - 1e-6), 1)
	t.eq(c.year_index(c.year_h), 2)


func test_lon_of_tile(t) -> void:
	t.near(c.lon_of_tile(0), 77.5, 1e-12)
	t.near(c.lon_of_tile(40), 87.5, 1e-12)
