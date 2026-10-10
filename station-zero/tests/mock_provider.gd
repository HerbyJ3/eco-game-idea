extends RefCounted
## Task 6b, step 3: the scripted provider the AI minds tests use (spec docs/specs/ai-minds.md section 3 "tests/mock_provider.gd",
## sections 13 and 14). It is the ONLY "provider" a test ever talks to. It opens no socket, reads no environment variable and
## holds no key: every answer is computed in memory (test 19 and 20 scan sim/ and the repository for the opposite).
##
## Randomness: latency and failures come from a generator of its own, seeded with the data constant `tests.mock_seed` of
## data/minds.json (1013), so a test that uses it is repeatable (spec test 11). It never touches SimRng.
##
## Two views of the same script:
##  - sim level (`answer_for`): given one outbox request {id, k, deadline_step, facts, menu, priority} it returns the delivery
##    a driver would make: {fail, steps, entry} where `steps` is the latency in sim steps and `entry` is the dictionary handed
##    to Minds.deliver (id, k, choice (an option KEY), say, model, filtered). Tests use it as a test-local mini driver.
##  - wire level (`respond`): given a request body it returns {status, latency_s, body} like an HTTP adapter would, for the
##    driver tests (spec 14 tests 24 and 25).
##
## Behaviours (`behaviour`): "scripted" (random choice among the menu keys, random latency, random failures; the default),
## "always_stay", "always_roam", "always_first_visit", "always_invalid" (a key that is in no menu), "never" (no answer),
## "late" (answers after the deadline), "fixed" (answers `fixed_choice` / `fixed_say` for every slot).

const FALLBACK_SEED := -1

var rng := RandomNumberGenerator.new()
var behaviour := "scripted"
var fixed_choice := "carry_on"
var fixed_say := ""
## Probability that a scripted answer fails (timeout, 500, malformed), and the latency range in real seconds.
var fail_rate := 0.15
var latency_lo_s := 0.3
var latency_hi_s := 3.0
## Real seconds one sim step takes at 1x, derived in _init from data/sim.json (fixed_step_hours x real_seconds_per_hour_at_1x).
var seconds_per_step := 0.0
var calls := 0
var failures := 0
var remarks: Array[String] = ["Feeling steady today.", "A quiet sort of day.", "Tired but glad of it.", "Something is on my mind.",
		"The light looks good in here.", "It has been a long week."]


func _init(seed_in: int = FALLBACK_SEED) -> void:
	seconds_per_step = float(SimData.sim().fixed_step_hours) * float(SimData.sim().real_seconds_per_hour_at_1x)
	rng.seed = seed_in if seed_in != FALLBACK_SEED else mock_seed()


## The constant of data/minds.json `tests.mock_seed`; -1 when the file or the key does not exist yet (so a test that uses the
## mock on a tree without the data fails loudly through its own `_api` check rather than running on a made-up seed).
static func mock_seed() -> int:
	if not FileAccess.file_exists("res://data/minds.json"):
		return FALLBACK_SEED
	var d: Variant = SimData.load_json("minds.json")
	if d is Dictionary and d.has("tests") and d.tests.has("mock_seed"):
		return int(d.tests.mock_seed)
	return FALLBACK_SEED


func _pick_key(menu: Array) -> String:
	match behaviour:
		"always_stay":
			return "stay"
		"always_roam":
			return "roam"
		"always_invalid":
			return "no_such_key"
		"always_first_visit":
			for k in menu:
				if str(k).begins_with("visit:"):
					return str(k)
			return "carry_on"
		"fixed":
			return fixed_choice
	return str(menu[rng.randi_range(0, menu.size() - 1)]) if not menu.is_empty() else "carry_on"


## Sim level. Returns {fail: bool, steps: int, entry: Dictionary}; `entry` is empty when the behaviour never answers.
func answer_for(req: Dictionary) -> Dictionary:
	calls += 1
	if behaviour == "never":
		return {"fail": true, "steps": 0, "entry": {}}
	var lat := rng.randf_range(latency_lo_s, latency_hi_s)
	var fail := false
	if behaviour == "scripted":
		fail = rng.randf() < fail_rate
	if fail:
		failures += 1
		return {"fail": true, "steps": 0, "entry": {}}
	var steps := maxi(1, int(round(lat / seconds_per_step)))
	if behaviour == "late":
		steps = int(req.deadline_step) - int(req.get("open_step", 0)) + 5
	var say := fixed_say if behaviour == "fixed" else remarks[rng.randi_range(0, remarks.size() - 1)]
	var entry := {"id": int(req.id), "k": int(req.k), "choice": _pick_key(req.menu), "say": say, "model": "mock", "filtered": false}
	return {"fail": false, "steps": steps, "entry": entry}


## Wire level, the interface a driver uses (API ASSUMED: provider.send(body, timeout_s) -> {status, latency_s, body}). Failure kinds
## are consumed one per call from `kinds` (empty means "ok"); `choice_number` (>= 0) and `say_override` replace the scripted
## reply of every slot; `partial` keeps only the first slot of a batch.
var kinds: Array = []
var choice_number := -1
var say_override: Variant = null
var partial := false
var sent: Array = []


func send(body: Dictionary, timeout_s: float = 8.0) -> Dictionary:
	sent.append(body)
	var kind: String = str(kinds.pop_front()) if not kinds.is_empty() else "ok"
	var r := respond(body, kind)
	if float(r.latency_s) > timeout_s:
		return {"status": 0, "latency_s": timeout_s, "body": ""}
	return r


## Wire level. `body` is the request the driver would send ({slots: [{slot, menu: [keys]}]}); the reply body is the strict JSON
## array of {slot, choice (a number), say} of spec 6.4. Failure kinds: 500, timeout (status 0), malformed, empty.
func respond(body: Dictionary, kind: String = "ok") -> Dictionary:
	calls += 1
	match kind:
		"500":
			failures += 1
			return {"status": 500, "latency_s": 0.2, "body": ""}
		"timeout":
			failures += 1
			return {"status": 0, "latency_s": 99.0, "body": ""}
		"malformed":
			failures += 1
			return {"status": 200, "latency_s": 0.5, "body": "this is not json {"}
		"empty":
			failures += 1
			return {"status": 200, "latency_s": 0.5, "body": "[]"}
		"401":
			return {"status": 401, "latency_s": 0.1, "body": ""}
		"429":
			return {"status": 429, "latency_s": 0.1, "body": "", "retry_after_s": 30.0}
	var out: Array = []
	for s in body.get("slots", []):
		var pick := rng.randi_range(0, maxi(0, s.menu.size() - 1))
		var say: String = remarks[rng.randi_range(0, remarks.size() - 1)]
		out.append({"slot": s.slot, "choice": choice_number if choice_number >= 0 else pick, "say": say if say_override == null else str(say_override)})
		if partial:
			break
	return {"status": 200, "latency_s": rng.randf_range(latency_lo_s, latency_hi_s), "body": JSON.stringify(out)}
