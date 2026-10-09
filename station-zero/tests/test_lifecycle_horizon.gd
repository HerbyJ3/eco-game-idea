extends RefCounted
## Lifecycle calibration spec section 8: the pure arithmetic of section 1, no run.


func test_eighteen_years_in_sols(t) -> void:
	var life := Lifecycle.new()
	var sol_h := float(SimData.load_json("calendar.json").sol_hours)
	var h := life.add_months(0.0, 216) - 0.0
	var sols := h / sol_h
	t.between(sols, 6350.0, 6450.0, "18 years = %.1f sols, spec says 6,350..6,450" % sols)


func test_stage_thresholds_in_sols(t) -> void:
	var life := Lifecycle.new()
	var sol_h := float(SimData.load_json("calendar.json").sol_hours)
	var nine := life.add_months(0.0, 9) / sol_h
	t.between(nine, 260.0, 275.0, "9 months = %.1f sols (spec ~267)" % nine)
