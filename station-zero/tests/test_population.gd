extends RefCounted
## Seeded population runs: chart variety and role balance (HANDOFF.md section 3).

const BIRTHS := 20000


func test_mars_births(t) -> void:
	var c := Clock.new()
	var sky := MarsSky.new(c)
	var per := Persona.new()
	var rng := SimRng.new(42)
	var seen := {}
	var roles := {"builder": 0, "curious": 0, "social": 0, "tender": 0}
	for i in BIRTHS:
		var born := rng.randf_range(0.0, 2.0 * c.year_h)
		var lon := rng.randf_range(0.0, 360.0)
		var ch := sky.mars_chart(born, lon)
		seen[MarsSky.chart_key(ch)] = true
		roles[per.role_of(per.traits(ch))] += 1
	print("    unique charts: %d / %d" % [seen.size(), BIRTHS])
	t.between(seen.size(), 14500, 16500, "unique charts")
	var lo := 1.0
	var hi := 0.0
	for r in roles:
		var share: float = float(roles[r]) / BIRTHS
		print("    %s: %.3f" % [r, share])
		t.between(share, 0.15, 0.35, "%s share" % r)
		lo = minf(lo, share)
		hi = maxf(hi, share)
	t.check(hi / lo <= 2.0, "no role more than twice another (%.2f)" % (hi / lo))


## In game, lon = site lon + tile x * 0.25, so births only span a few tens of degrees.
## This run reports the in-game spread and guards against a role collapsing.
func test_mars_births_colony_lon(t) -> void:
	var c := Clock.new()
	var sky := MarsSky.new(c)
	var per := Persona.new()
	var rng := SimRng.new(42)
	var roles := {"builder": 0, "curious": 0, "social": 0, "tender": 0}
	var seen := {}
	for i in BIRTHS:
		var ch := sky.mars_chart(rng.randf_range(0.0, 2.0 * c.year_h), c.lon_of_tile(rng.randf_range(0.0, 100.0)))
		seen[MarsSky.chart_key(ch)] = true
		roles[per.role_of(per.traits(ch))] += 1
	print("    colony lon (tiles 0..100): unique %d" % seen.size())
	for r in roles:
		var share: float = float(roles[r]) / BIRTHS
		print("    %s: %.3f" % [r, share])
		t.between(share, 0.15, 0.35, "%s share" % r)
