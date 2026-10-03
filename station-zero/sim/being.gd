class_name Being
extends RefCounted
## One being. Spec: life-support-power.md section 4 (Being). Only the fields the colony needs are
## used so far; the rest are declared so later steps (state machine, EVA, mining) just fill them in.

var id: int
var name: String
## Persona.persona_from shape: {traits, role, description}.
var persona: Dictionary
var role: String
var earth_born := false
var born_t: float
var energy: float
## idle, to_door, transit, sleep, eva, work, mining.
var state := "idle"
## The building it is in (or left from while in transit or outside). No x,y inside.
var building_id: int
var wait_h := 0.0
var sleep_intent := false
var suit_up := false
var job: Variant = null
var mine: Variant = null
var mine_intent: Variant = null
## Null unless outside.
var air_h: Variant = null
var x: Variant = null
var y: Variant = null
var heading: Variant = null
var path: Variant = null
var after: Variant = null
var returning := false
var load := 0.0
var work_left_h := 0.0
var step_acc_px := 0.0
var foot_side := 1
var corridor_id: Variant = null
var transit_t := 0.0
var from_a := false
var sleep_started_t: Variant = null


## True while the being is in a building (sleepers count). Used by shortage victims and births.
func is_inside() -> bool:
	var s := state
	return s != "transit" and s != "eva" and s != "work" and s != "mining"


## Syllable name plus number, drawn from the world rng.
static func make_name(rng: SimRng) -> String:
	var cfg: Dictionary = SimData.beings().names
	return "%s%s-%d" % [rng.pick(cfg.syllables_a), rng.pick(cfg.syllables_b),
			rng.randi_range(int(cfg.number[0]), int(cfg.number[1]))]


## A persona with every trait at `value`; used by blank-world tests.
static func flat_persona(role_in: String, value: float = 0.5) -> Dictionary:
	var traits := {}
	for d in SimData.persona().dims:
		traits[d] = value
	return {"traits": traits, "role": role_in, "description": ""}
