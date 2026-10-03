extends Control
## Text HUD. Reads sim state only; the one thing it changes is _sim.speed (a view setting).
## Labels refresh at REFRESH_S real seconds, never per sim step.

const REFRESH_S := 0.1
const LOG_LINES := 8
## Keyboard speed presets (multiples of real time). 0 pauses.
const SPEEDS := {KEY_1: 1.0, KEY_2: 10.0, KEY_3: 100.0, KEY_4: 1000.0}
const STATES: Array[String] = ["idle", "sleep", "work", "mining", "eva", "transit"]

var _clock: Label
var _colony: Label
var _power: Label
var _site: Label
var _beings: Label
var _log: Label
var _controls: Label
var _map: Control

## The Sim autoload, looked up by path so the scene also loads where autoloads are not registered.
var _sim: Node
var _acc := 0.0
var _printed := false
var _resume_speed := 1.0
## Last sampled stocks for the ice and regolith rate readout: [t, ice, regolith].
var _prev: Array = []


func _ready() -> void:
	setup(get_node("/root/Sim"))


## Binds the sim host and the child nodes. Separate from _ready so a test can drive the scene
## without a running tree.
func setup(sim: Node) -> void:
	_sim = sim
	_clock = get_node("Margin/HBox/VBox/Clock")
	_colony = get_node("Margin/HBox/VBox/Colony")
	_power = get_node("Margin/HBox/VBox/Power")
	_site = get_node("Margin/HBox/VBox/Site")
	_beings = get_node("Margin/HBox/VBox/Beings")
	_log = get_node("Margin/HBox/VBox/Log")
	_controls = get_node("Margin/HBox/VBox/Controls")
	_map = get_node("Margin/HBox/Map")
	_map.setup(sim)
	refresh()


func _process(delta: float) -> void:
	_acc += delta
	if _acc >= REFRESH_S:
		_acc = 0.0
		refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_SPACE:
		toggle_pause()
	elif SPEEDS.has(k.keycode):
		set_speed(SPEEDS[k.keycode])


func set_speed(s: float) -> void:
	_sim.speed = s
	if s > 0.0:
		_resume_speed = s
	refresh()


func toggle_pause() -> void:
	set_speed(_resume_speed if _sim.speed == 0.0 else 0.0)
	if _sim.speed == 0.0:
		return
	refresh()


func refresh() -> void:
	var w: SimWorld = _sim.world
	_clock.text = _clock_text(w)
	_colony.text = _colony_text(w)
	_power.text = _power_text(w)
	_site.text = _site_text(w)
	_beings.text = _beings_text(w)
	_log.text = _log_text(w)
	_controls.text = "Speed: %s   [Space] pause  [1] 1x  [2] 10x  [3] 100x  [4] 1000x" % _speed_name()
	_map.queue_redraw()
	if not _printed:
		_printed = true
		print("\n".join([_clock.text, _colony.text, _power.text, _site.text, _beings.text,
				_log.text, _controls.text]))


func _speed_name() -> String:
	return "paused" if _sim.speed == 0.0 else "%dx" % int(_sim.speed)


func _clock_text(w: SimWorld) -> String:
	var c := w.clock
	var hour := c.mars_hour(w.t)
	return "%s  |  Year %d, Sol %d  |  %02d:%02d  |  %s" % [
		c.site_name, c.year_index(w.t), c.sol_index(w.t),
		int(hour), int(fmod(hour, 1.0) * 60.0), c.season(w.t)]


func _colony_text(w: SimWorld) -> String:
	var col := w.colony
	var d: Dictionary = w.stats.deaths
	var causes: PackedStringArray = []
	for k: String in d:
		causes.append("%s %d" % [k.replace("_", " "), int(d[k])])
	var ice_rate := 0.0
	var reg_rate := 0.0
	if _prev.size() == 3 and w.t > _prev[0]:
		ice_rate = (col.ice - _prev[1]) / (w.t - _prev[0])
		reg_rate = (col.regolith - _prev[2]) / (w.t - _prev[0])
	if _prev.is_empty() or w.t - _prev[0] >= 1.0 or w.t < _prev[0]:
		_prev = [w.t, col.ice, col.regolith]
	return "\n".join([
		"Population %d   births %d   deaths %d" % [
			col.pop(), int(w.stats.births), int(w.stats.deaths_list.size())],
		"  deaths by cause: " + ", ".join(causes),
		"Oxygen   %7.1f / %.0f   %+.2f /h" % [col.oxygen, col.o2_cap(), col.o2_net()],
		"Food     %7.1f / %.0f   %+.2f /h" % [col.food, col.food_cap(), col.food_net()],
		"Ice      %7.1f (target %.0f)   %+.2f /h" % [col.ice, col.ice_target(), ice_rate],
		"Regolith %7.1f (target %.0f)   %+.2f /h" % [col.regolith, col.regolith_target(), reg_rate],
	])


func _power_text(w: SimWorld) -> String:
	var b := w.buildings
	var total := {}
	var offline := {}
	for x in b.list:
		if not x.finished():
			continue
		total[x.kind] = int(total.get(x.kind, 0)) + 1
		if x.offline:
			offline[x.kind] = int(offline.get(x.kind, 0)) + 1
	var parts: PackedStringArray = []
	for kind: String in total:
		var s := "%s %d" % [b.cfg.kinds[kind].label, total[kind]]
		if offline.has(kind):
			s += " (%d offline)" % offline[kind]
		parts.append(s)
	return "Power: supply %.0f  draw %.0f  demand %.0f\nBuildings: %s" % [
		b.supply(), b.draw(), b.demand(), ", ".join(parts) if not parts.is_empty() else "none"]


func _site_text(w: SimWorld) -> String:
	var s := w.buildings.site
	if s == null:
		return "Construction: none"
	var b := w.buildings.get_building(s.building_id)
	var crew := 0
	for x in w.beings:
		if x.state == "work" and x.job == s:
			crew += 1
	return "Construction: %s %d%%  crew %d" % [
		w.buildings.cfg.kinds[b.kind].label, int(b.built * 100.0), crew]


func _beings_text(w: SimWorld) -> String:
	var n := {}
	for b in w.beings:
		var key: String = b.state
		if not STATES.has(key):
			key = "idle"  # to_door and any other inside state read as idle
		n[key] = int(n.get(key, 0)) + 1
	var parts: PackedStringArray = []
	for s in STATES:
		parts.append("%s %d" % [s, int(n.get(s, 0))])
	return "Beings: " + "  ".join(parts)


func _log_text(w: SimWorld) -> String:
	var lines: PackedStringArray = ["Log"]
	for e: Dictionary in w.log.slice(maxi(0, w.log.size() - LOG_LINES)):
		lines.append("  sol %d  %s" % [int(e.clock_sol), e.text])
	return "\n".join(lines)
