extends Control
## Text HUD. Reads sim state only; the one thing it changes is _sim.speed (a view setting).
## Labels refresh at REFRESH_S real seconds, never per sim step.

const REFRESH_S := 0.1
const LOG_LINES := 8
## Slack of the sample's ice comparison, so the word flips at exactly the same stock.
const LOW_EPS := Ages.CMP_EPS
const THROTTLE_NOTE := "The colony is too large to run this fast."
## Keyboard speed presets (multiples of real time). 0 pauses.
const SPEEDS := {KEY_1: 1.0, KEY_2: 10.0, KEY_3: 100.0, KEY_4: 1000.0}
const STATES: Array[String] = ["idle", "sleep", "work", "mining", "eva", "transit"]

var _clock: Label
var _colony: Label
var _power: Label
var _site: Label
var _beings: Label
var _chapters: Label
var _log: Label
var _controls: Label
var _map: Control
## The sprite world view (default). M swaps it for the debug dot map.
var _world: Node
var _background: Control
var _shade: Control
var _vbox: Control
var _hud_visible := true

## The Sim autoload, looked up by path so the scene also loads where autoloads are not registered.
var _sim: Node
var _acc := 0.0
var _printed := false
var _resume_speed := 1.0
## Speed readout (spec ages.md section 9): [frame real seconds, sim hours advanced in it] over the last
## speed_readout_window_s, the cached readout (achieved multiple of real time, -1 = none yet) and the refresh timer.
var _speed_samples: Array = []
var _last_t := 0.0
var _readout_acc := 0.0
var _achieved := -1.0
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
	_chapters = get_node("Margin/HBox/VBox/Chapters")
	_log = get_node("Margin/HBox/VBox/Log")
	_controls = get_node("Margin/HBox/VBox/Controls")
	_map = get_node("Margin/HBox/Map")
	_map.setup(sim)
	_world = get_node("WorldLayer/WorldView")
	_background = get_node("Background")
	_shade = get_node("HudShade")
	_vbox = get_node("Margin/HBox/VBox")
	_world.setup(sim)
	if not _world.debug_map_changed.is_connected(_show_debug_map):
		_world.debug_map_changed.connect(_show_debug_map)
	_show_debug_map(_world.vm != null and _world.vm.debug_map)
	_reset_speed_readout()
	refresh()


## Debug dot map on: the dark background and the map; off: the sprite view behind a shaded HUD.
func _show_debug_map(on: bool) -> void:
	_background.visible = on
	_map.visible = on
	_shade.visible = not on and _hud_visible


## Screenshot and test seams: the camera and view-side state go straight to the world view.
func set_camera(zoom_in: float, center_in: Vector2) -> void:
	_world.set_camera(zoom_in, center_in)


func settle_view(seconds: float) -> void:
	_world.settle_view(seconds)
	_world.freeze_model = true


func apply_shot_view(opts: Dictionary) -> void:
	if opts.has("hud"):
		_hud_visible = bool(opts.hud)
		get_node("Margin").visible = _hud_visible
	_world.apply_shot_view(opts)
	_show_debug_map(_world.vm.debug_map)


func _process(delta: float) -> void:
	_sample_speed(delta)
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
	if s != _sim.speed:
		_reset_speed_readout()
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
	_chapters.text = _chapters_text(w)
	_log.text = _log_text(w)
	_controls.text = _controls_text()
	_map.queue_redraw()
	_fit_shade.call_deferred()
	if not _printed:
		_printed = true
		print("\n".join([_clock.text, _colony.text, _power.text, _site.text, _beings.text,
				_chapters.text, _log.text, _controls.text]))


func _speed_name() -> String:
	return "paused" if _sim.speed == 0.0 else "%dx max" % int(_sim.speed)


func _reset_speed_readout() -> void:
	_speed_samples.clear()
	_readout_acc = 0.0
	_achieved = -1.0
	if _sim != null and _sim.world != null:
		_last_t = _sim.world.t


## Called every frame: records the sim hours the world advanced in this frame, and refreshes the cached readout at most
## every speed_readout_refresh_s so the text does not flicker.
func _sample_speed(delta: float) -> void:
	var w: SimWorld = _sim.world
	var cfg: Dictionary = SimData.sim()
	_speed_samples.append([delta, w.t - _last_t])
	_last_t = w.t
	var window := float(cfg.speed_readout_window_s)
	var total := 0.0
	for smp: Array in _speed_samples:
		total += float(smp[0])
	while _speed_samples.size() > 1 and total - float(_speed_samples[0][0]) >= window:
		total -= float(_speed_samples[0][0])
		_speed_samples.pop_front()
	_readout_acc += delta
	if _readout_acc < float(cfg.speed_readout_refresh_s) - 1e-6:
		return
	_readout_acc = 0.0
	if _sim.speed == 0.0 or total <= 0.0:
		_achieved = -1.0
		return
	var hours := 0.0
	for smp: Array in _speed_samples:
		hours += float(smp[1])
	# Hours per real second, as a multiple of the 1x rate.
	_achieved = hours / total * float(cfg.real_seconds_per_hour_at_1x)


## Speed, the achieved readout and the throttle note, then the key help (spec ages.md section 9).
func _controls_text() -> String:
	var line := "Speed: " + _speed_name()
	if _sim.speed > 0.0 and _achieved >= 0.0:
		line += " (running about %dx)" % int(round(_achieved))
		if _achieved < float(SimData.sim().speed_throttle_below) * _sim.speed:
			line += "  " + THROTTLE_NOTE
	return line + "   [Space] pause  [1] 1x  [2] 10x  [3] 100x  [4] 1000x"


func _clock_text(w: SimWorld) -> String:
	var c := w.clock
	var hour := c.mars_hour(w.t)
	var line := "%s  |  Year %d, Sol %d  |  %02d:%02d  |  %s" % [
		c.site_name, c.year_index(w.t), c.sol_index(w.t),
		int(hour), int(fmod(hour, 1.0) * 60.0), c.season(w.t)]
	# The age word ends the line; hidden when nobody is alive (spec ages.md section 9).
	if w.colony.pop() > 0:
		var ad: Dictionary = SimData.ages()
		var age_id: String = str(w.stats.age)
		if ad.has(age_id):
			line += "  |  " + str(ad[age_id].name)
		elif age_id == "council":
			line += "  |  " + str(SimData.council().age.name)  # spec council.md 7.6: no Council key in ages.json
	return line


## The pinned chapters strip: the last hud.chapters_shown age_history entries, oldest first, one line each, as
## `sol N  <first sentence>` (the text up to and including the first ". "; the full text is in the log).
func _chapters_text(w: SimWorld) -> String:
	var n := int(SimData.ages().hud.chapters_shown)
	var hist: Array = w.stats.age_history
	var lines: PackedStringArray = []
	for e: Dictionary in hist.slice(maxi(0, hist.size() - n)):
		lines.append("sol %d  %s" % [int(e.clock_sol), _first_sentence(str(e.text))])
	return "\n".join(lines)


func _first_sentence(text: String) -> String:
	var i := text.find(". ")
	return text if i < 0 else text.substr(0, i + 1)


## The low-stock word for the Oxygen, Food and Ice lines: the same thresholds as ages.sample (data keys), computed here
## from the stocks alone.
func _low_word(w: SimWorld, kind: String) -> String:
	var cfg: Dictionary = SimData.ages().sample
	var col := w.colony
	var low := false
	match kind:
		"oxygen":
			low = col.oxygen < float(cfg.o2_min_fraction) * col.o2_cap()
		"food":
			low = col.food < float(cfg.food_min_fraction) * col.food_cap()
		"ice":
			var use_per_sol: float = col.pop() * float(SimData.colony().consumption.ice_per_being) * col.sol_h
			low = col.ice < float(cfg.ice_min_sols) * use_per_sol - LOW_EPS
	return "   " + str(SimData.ages().hud.low_word) if low else ""


## Sizes the shade behind the HUD text to the text block (the block grows with the chapters strip).
func _fit_shade() -> void:
	if _shade == null or _vbox == null or not is_instance_valid(_vbox):
		return
	var r := _vbox.get_global_rect()
	_shade.position = Vector2.ZERO
	_shade.size = Vector2(r.end.x + 24.0, r.end.y + 16.0)


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
		"Oxygen   %7.1f / %.0f   %+.2f /h%s" % [col.oxygen, col.o2_cap(), col.o2_net(), _low_word(w, "oxygen")],
		"Food     %7.1f / %.0f   %+.2f /h%s" % [col.food, col.food_cap(), col.food_net(), _low_word(w, "food")],
		"Ice      %7.1f (target %.0f)   %+.2f /h%s" % [col.ice, col.ice_target(), ice_rate, _low_word(w, "ice")],
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
