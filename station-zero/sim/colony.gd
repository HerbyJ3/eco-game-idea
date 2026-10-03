class_name Colony
extends RefCounted
## Colony stocks, caps, targets, warnings and the shortage death timer.
## Spec: life-support-power.md sections 4, 5 and 9. Every number comes from data/colony.json.
## Births (section 10) arrive in a later step; the birth fields are declared here already.

var oxygen: float
var food: float
var ice: float
var regolith: float
var air_warn_t: float = Buildings.NEVER
var food_warn_t: float = Buildings.NEVER
var thirst_warn_t: float = Buildings.NEVER
var regolith_warn_t: float = Buildings.NEVER
var waiting_warn_t: float = Buildings.NEVER
var death_timer_h := 0.0
var birth_timer_h := 0.0
## Habitat id -> t of its last birth (absent = never).
var last_birth_t: Dictionary = {}
var extinct := false

var cfg: Dictionary
var sol_h: float
var _beings: Array
var _buildings: Buildings
var _rng: SimRng


## `beings` is the world's live array (shared, never copied).
func _init(beings_in: Array, buildings_in: Buildings, rng_in: SimRng, sol_hours: float) -> void:
	cfg = SimData.colony()
	sol_h = sol_hours
	_beings = beings_in
	_buildings = buildings_in
	_rng = rng_in
	oxygen = cfg.start.oxygen
	food = cfg.start.food
	ice = cfg.start.ice
	regolith = cfg.start.regolith


# ---------------------------------------------------------------- derived values

func pop() -> int:
	return _beings.size()


func green_rooms() -> int:
	return _buildings.count_online("green_room")


func o2_net() -> float:
	return green_rooms() * float(cfg.production.o2_per_green_room) - pop() * float(cfg.consumption.o2_per_being)


func food_net() -> float:
	return green_rooms() * float(cfg.production.food_per_green_room) - pop() * float(cfg.consumption.food_per_being)


func o2_cap() -> float:
	return float(cfg.caps.o2_base) + green_rooms() * float(cfg.caps.o2_per_green_room)


func food_cap() -> float:
	return float(cfg.caps.food_base) + green_rooms() * float(cfg.caps.food_per_green_room)


func ice_target() -> float:
	return maxf(float(cfg.targets.ice_min), pop() * float(cfg.targets.ice_per_being))


## All buildings count, construction site included.
func regolith_target() -> float:
	return float(cfg.targets.regolith_base) + _buildings.count() * float(cfg.targets.regolith_per_building)


## Beings inside a building (sleepers count); every living being if none is inside.
func shortage_victim_candidates() -> Array:
	var inside: Array = []
	for b: Being in _beings:
		if b.is_inside():
			inside.append(b)
	return inside if not inside.is_empty() else _beings.duplicate()


# ---------------------------------------------------------------- per-step phases

## Phase 2. Uses pop and online green rooms as they stood at the end of the previous step.
func step_stocks(dt: float) -> void:
	oxygen = clampf(oxygen + o2_net() * dt, 0.0, o2_cap())
	food = clampf(food + food_net() * dt, 0.0, food_cap())


## Phase 4. Returns [{kind, text}] to log.
func air_food_warnings(t: float) -> Array:
	var out: Array = []
	var repeat_h: float = float(cfg.warnings.air_food_repeat_sols) * sol_h
	if oxygen <= 0.0 and _due(t, air_warn_t, repeat_h):
		air_warn_t = t
		out.append({"kind": "air_low", "text": "The air has run out."})
	if food <= 0.0 and _due(t, food_warn_t, repeat_h):
		food_warn_t = t
		out.append({"kind": "food_empty", "text": "The food has run out."})
	return out


## Phase 5 (ice part): drain, then the thirst warning. Returns [{kind, text}] to log.
func drain_ice(t: float, dt: float) -> Array:
	ice = maxf(0.0, ice - pop() * float(cfg.consumption.ice_per_being) * dt)
	var out: Array = []
	if ice <= 0.0 and _due(t, thirst_warn_t, float(cfg.warnings.thirst_repeat_sols) * sol_h):
		thirst_warn_t = t
		out.append({"kind": "water_dry", "text": "The water has run dry."})
	return out


## Phase 10. Returns {} or {victim: Being, cause: String}; the world removes and logs the victim.
func shortage_check(dt: float) -> Dictionary:
	var lacking := oxygen <= 0.0 or food <= 0.0 or ice <= 0.0
	if pop() == 0 or not lacking:
		death_timer_h = 0.0
		return {}
	var d: Dictionary = cfg.death
	var interval_h: float = float(d.air_interval_h) if oxygen <= 0.0 \
			else (float(d.thirst_interval_h) if ice <= 0.0 else float(d.hunger_interval_h))
	var cause := "air" if oxygen <= 0.0 else ("thirst" if ice <= 0.0 else "hunger")
	death_timer_h += dt
	if death_timer_h < interval_h - SimWorld.STEP_EPS:
		return {}
	death_timer_h = 0.0
	if not _rng.chance(float(d.chance)):
		return {}
	return {"victim": _rng.pick(shortage_victim_candidates()), "cause": cause}


## Elapsed-since comparator (spec section 3).
func _due(t: float, last_t: float, repeat_h: float) -> bool:
	return t - last_t > repeat_h + SimWorld.STEP_EPS
