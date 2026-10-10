extends RefCounted
## Scripted attentive player (docs/specs/influence-powers.md section 5). Glances at the colony every
## check_h sim hours and uses only Guide (water) and Good fortune (power). Used by tests/balance_run.gd --player attentive.

var check_h := 6.0
var _next_t := 0.0
var uses := {"guide": 0, "fortune": 0}


func label() -> String:
	return "attentive"


func after_step(w: SimWorld) -> void:
	if w.t < _next_t:
		return
	_next_t = w.t + check_h
	if w.colony.pop() == 0:
		return
	if w.colony.ice < 0.5 * w.colony.ice_target() and w.power_ready_in("guide") == 0.0:
		var best := -1
		var best_amt := -1.0
		var sites := w.power_sites()
		for i in sites.size():
			var s: Resources.Site = sites[i]
			if s.kind == "ice" and w._site_live(s) and s.amount > best_amt:
				best = i
				best_amt = s.amount
		if best >= 0 and w.use_power("guide", best).ok:
			uses.guide += 1
	var dark := false
	for b in w.buildings.list:
		if b.finished() and b.offline:
			dark = true
	if (dark or w.buildings.margin() < 0.0) and w.power_ready_in("fortune") == 0.0:
		if w.use_power("fortune").ok:
			uses.fortune += 1
