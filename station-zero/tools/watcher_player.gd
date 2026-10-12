extends "res://tools/attentive_player.gd"
## Observer-only "player" for the unattended acceptance runs (docs/balance/task-7-acceptance.md): never calls use_power,
## so the run is the unattended colony, but it prints the same PLAYER metrics section (first_low_sol, low share, ice ratio).
## Used by tests/balance_run.gd --player watcher.


func label() -> String:
	return "watcher (observes only, no powers)"


func after_step(w: SimWorld) -> void:
	_sample(w)
