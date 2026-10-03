class_name SimWorld
extends RefCounted
## Root of the headless simulation. Advances in fixed steps independent of frame rate.
## Task 0 holds only time and the sky; colony systems arrive in Task 1+.

var rng: SimRng
var clock: Clock
var sky: MarsSky
var persona: Persona
var t: float
## Earth-born founders: [{born, lon, chart, persona}]. Charts stay inside the sim.
var founders: Array = []
var fixed_step: float
var max_steps_per_advance: int
var _accum := 0.0
## Float slack so 0.05-hour steps add up to whole hours.
const STEP_EPS := 1e-9


func _init(seed_in: Variant = null) -> void:
	var cfg := SimData.sim()
	rng = SimRng.new(int(seed_in) if seed_in != null else int(cfg.default_seed))
	max_steps_per_advance = int(cfg.max_steps_per_frame)
	clock = Clock.new()
	sky = MarsSky.new(clock)
	persona = Persona.new()
	fixed_step = cfg.fixed_step_hours
	t = clock.start_hour
	_create_founders()


func _create_founders() -> void:
	var cfg: Dictionary = SimData.persona().founders
	for i in int(cfg.count):
		var birth := sky.founder_birth(rng, cfg)
		birth["persona"] = persona.persona_from(birth.chart)
		founders.append(birth)


## Advance by `hours` of sim time using whole fixed steps. Returns steps taken.
## At most max_steps_per_advance steps per call; leftover time is dropped so a hitch can't stall.
func advance(hours: float) -> int:
	_accum += hours
	var steps := 0
	while _accum >= fixed_step - STEP_EPS:
		if steps >= max_steps_per_advance:
			_accum = 0.0
			break
		step()
		_accum -= fixed_step
		steps += 1
	return steps


func step() -> void:
	t += fixed_step
