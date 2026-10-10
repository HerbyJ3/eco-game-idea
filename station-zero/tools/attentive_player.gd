extends RefCounted
## Scripted attentive player (docs/specs/influence-powers.md section 5). Glances at the colony every `cadence`
## sols and uses only Guide (when the water outlook is low or dry) and Good fortune (a room is dark, or the
## reactor margin is negative). Public API only. Used by tests/balance_run.gd --player attentive [--cadence <sols>].

## Sols between glances (set by --cadence); 1 is the main test, 2 the sloppy player, 0.25 the idealised diagnostic.
var cadence := 1.0
## Sols between samples for the ice and "low" shares (set from --every).
var sample_every := 10
var _next_t := 0.0
var _last_sample_sol := -1
var uses := {"guide": 0, "fortune": 0}
var checks := 0
var guide_uses_in_trouble := 0
var _ice_ratio_sum := 0.0
var _samples := 0
var _low_samples := 0


func label() -> String:
	return "attentive cadence=%s" % str(cadence)


func after_step(w: SimWorld) -> void:
	_sample(w)
	if w.t < _next_t:
		return
	_next_t = w.t + cadence * w.clock.sol_h
	if w.colony.pop() == 0:
		return
	checks += 1
	var state: String = w.water_outlook().state
	if (state == "low" or state == "dry") and w.power_ready_in("guide") == 0.0:
		if w.use_power("guide").ok:
			uses.guide += 1
			guide_uses_in_trouble += 1
	if (w.dark_building_count() > 0 or w.buildings.margin() < 0.0) and w.power_ready_in("fortune") == 0.0:
		if w.use_power("fortune").ok:
			uses.fortune += 1


## Records the water state at each sample sol while the colony is alive (the same sols as the balance rows).
func _sample(w: SimWorld) -> void:
	var s := w.sol()
	if s == _last_sample_sol or s % sample_every != 0 or w.colony.pop() == 0:
		return
	_last_sample_sol = s
	var o := w.water_outlook()
	_samples += 1
	_ice_ratio_sum += float(o.ice) / float(o.target)
	if o.state == "low" or o.state == "dry":
		_low_samples += 1


## Per-run metrics (spec section 5) printed under the table.
func report(w: SimWorld) -> Array[String]:
	var sols := maxf(1.0, float(w.sol()))
	var first_low: Variant = w.stats.first_low_sol
	var window_trips := maxi(1, int(w.stats.ice_trips_guided_window))
	return [
		"# player %s" % label(),
		"PLAYER checks=%d uses guide=%d fortune=%d per100 guide=%.1f fortune=%.1f guide_in_trouble=%d" % [
				checks, uses.guide, uses.fortune, 100.0 * uses.guide / sols, 100.0 * uses.fortune / sols,
				guide_uses_in_trouble],
		"PLAYER first_low_sol=%s samples=%d mean_ice_over_target=%.3f low_share=%.3f" % [
				"none" if first_low == null else str(first_low), _samples,
				_ice_ratio_sum / maxf(1.0, float(_samples)), float(_low_samples) / maxf(1.0, float(_samples))],
		"PLAYER guide_trips=%d ice_trips_total=%d ice_trips_in_guided_window=%d guide_share_of_window=%.3f guide_hauled=%.1f" % [
				int(w.stats.guide_trips), int(w.stats.ice_trips_total), int(w.stats.ice_trips_guided_window),
				float(w.stats.guide_trips) / float(window_trips), float(w.stats.guide_hauled)],
		"PLAYER air_deaths=%d turn_backs_air=%d first_thirst_sol=%s" % [int(w.stats.deaths.air),
				int(w.stats.turn_backs_air), _first_thirst(w)],
	]


func _first_thirst(w: SimWorld) -> String:
	for d in w.stats.deaths_list:
		if str(d.get("cause", "")) == "thirst":
			return str(d.get("sol", "?"))
	return "none"
