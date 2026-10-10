class_name Powers
extends RefCounted
## God-power state (spec docs/specs/influence-powers.md). SimWorld.use_power applies a power; the hooks in
## Buildings, SimWorld and Being read the fields below. Nothing here draws from the RNG.

## Supply is multiplied while the world clock is below this. Never-set sentinel.
var power_multiplier_until: float = Buildings.NEVER
## Weak: Buildings holds this Powers, so a strong ref back would leak both.
var _buildings: WeakRef


func _init(buildings_in: Buildings) -> void:
	_buildings = weakref(buildings_in)


## Raises supply until `until_t` and resets the 3 h re-online hold.
func set_power_multiplier(until_t: float) -> void:
	power_multiplier_until = until_t
	var b: Buildings = _buildings.get_ref()
	if b != null:
		b.clear_short_hold()


## Sim time at which each power is ready again (absent = ready).
var ready_at: Dictionary = {}
## Inspire: {kind, until} or empty.
var inspire: Dictionary = {}
## Grace: {habitat_id, until} or empty.
var grace: Dictionary = {}
## Guide: {site (Resources.Site), until} or empty.
var guide: Dictionary = {}


func ready_in(power_name: String, now: float) -> float:
	return maxf(0.0, float(ready_at.get(power_name, 0.0)) - now)


func inspire_kind(now: float) -> String:
	return str(inspire.kind) if not inspire.is_empty() and now < float(inspire.until) else ""


func grace_bonus(habitat_id: int, now: float) -> float:
	if grace.is_empty() or now >= float(grace.until) or int(grace.habitat_id) != habitat_id:
		return 0.0
	return float(SimData.powers().grace.bonus)


func guided_site(now: float) -> Resources.Site:
	if guide.is_empty() or now >= float(guide.until):
		return null
	return guide.site
