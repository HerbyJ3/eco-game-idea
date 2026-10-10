extends Control
## Text HUD. Reads sim state only; the one thing it changes is _sim.speed (a view setting).
## Labels refresh at REFRESH_S real seconds, never per sim step.

const PanelText = preload("res://view/model/being_panel.gd")
const PanelHold = preload("res://view/model/panel_hold.gd")

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
## The being inspect panel (docs/specs/emotions.md 7.1): a text box at the bottom left, and the real-time pacing helper.
var _panel_box: PanelContainer
var _panel: Label
var _hold: PanelHold
## Real seconds since the HUD started (the clock of the panel pacing, independent of game speed).
var _real_s := 0.0
var _panel_id := 0
var _died := false
## The log entries shown at the last refresh, and the colonist a press on a log line is holding.
var _log_shown: Array = []
var _log_press_id := 0
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
	_build_panel()
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
		_panel_box.get_parent().visible = _hud_visible
	_world.apply_shot_view(opts)
	_show_debug_map(_world.vm.debug_map)


func _process(delta: float) -> void:
	_real_s += delta
	_sample_speed(delta)
	_update_panel()
	_acc += delta
	if _acc >= REFRESH_S:
		_acc = 0.0
		refresh()


## The panel sits in its own full-rect control so the HUD switch can hide it with the text.
func _build_panel() -> void:
	if _panel_box != null:
		return
	_hold = PanelHold.new(PanelText.selection_cfg())
	var holder := Control.new()
	holder.name = "PanelHolder"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_panel_box = PanelContainer.new()
	_panel_box.name = "BeingPanel"
	_panel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.04, 0.03, 0.7)
	style.set_content_margin_all(10.0)
	_panel_box.add_theme_stylebox_override("panel", style)
	_panel_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)
	_panel_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel = Label.new()
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_box.add_child(_panel)
	_panel_box.visible = false
	holder.add_child(_panel_box)


## The text now in the panel, "" while it is closed (a test seam).
func panel_text() -> String:
	return _panel.text if _panel_box != null and _panel_box.visible else ""


## One frame of the panel: closed with no colonist selected; the died beat for a colonist who left the world; else the
## cached lines, rebuilt at most refresh_hz times a second with the shown band held for hold_s (real time, any game speed).
func _update_panel() -> void:
	if _panel_box == null or _world.vm == null:
		return
	var sel = _world.vm.selection
	var w: SimWorld = _sim.world
	var id: int = sel.selected_being
	if id != _panel_id:
		_panel_id = id
		_died = false
		_hold.reset()
	if id == 0:
		_panel_box.visible = false
		return
	if not PanelText.alive(w, id):
		if not _died:
			_died = true
			_hold.begin_died(_real_s)
		var line := PanelText.died_line(w, id)
		if line == "" or not _hold.died_open(_real_s):
			sel.deselect()
			_panel_box.visible = false
			return
		_panel.text = line
		_panel_box.visible = true
		return
	if _hold.refresh_due(_real_s) or not _panel_box.visible:
		var band := _hold.shown_band(_real_s, PanelText.wanted_band(w, id))
		_panel.text = "\n".join(PackedStringArray(PanelText.lines(w, id, band)))
		_panel_box.visible = true


## The entry under a tap at height `y` (from the top of the first entry line) of the one-label log showing the last `shown`
## of `entries`, or null; an entry without a being_id is not a target.
static func log_entry_at(y: float, line_h: float, entries: Array, shown: int) -> Variant:
	if y < 0.0 or line_h <= 0.0:
		return null
	var first := maxi(0, entries.size() - shown)
	var i := first + int(y / line_h)
	if i >= entries.size() or i >= first + shown:
		return null
	var e: Dictionary = entries[i]
	return e if e.has("being_id") else null


## A press on a log line that carries a being_id takes the press; the release selects that colonist (no camera move).
func _input(event: InputEvent) -> void:
	var m := event as InputEventMouseButton
	if m == null or m.button_index != MOUSE_BUTTON_LEFT or not _hud_visible or _world.vm == null:
		return
	if m.pressed:
		var r := _log.get_global_rect()
		_log_press_id = 0
		if r.has_point(m.position):
			var e: Variant = log_entry_at(m.position.y - r.position.y - _log.get_line_height(), _log.get_line_height(),
					_log_shown, LOG_LINES)
			if e != null:
				_log_press_id = int(e.being_id)
				get_viewport().set_input_as_handled()
	elif _log_press_id != 0:
		_world.vm.selection.select_being(_log_press_id)
		_log_press_id = 0
		get_viewport().set_input_as_handled()


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


## The pinned chapters strip (spec council.md 7 and 9): the age_history entries merged with stats.council.chapters in time
## order (a tie on t: the age entry first), the latest hud.chapters_shown of them, oldest first, one line each, as
## `sol N  <first sentence>` (the full text is in the log). Once the pledge is made it is pinned: it takes one of the
## places and the latest (chapters_shown - 1) other entries fill the rest. No numbers beyond the sol.
func _chapters_text(w: SimWorld) -> String:
	var n := int(SimData.ages().hud.chapters_shown)
	var items: Array = []  # [t, order, entry]
	var order := 0
	for e: Dictionary in w.stats.age_history:
		items.append([float(e.t), order, e])
		order += 1
	var pinned: Array = []
	for e: Dictionary in w.stats.council.chapters:
		var it := [float(e.t), order, e]
		order += 1
		if pinned.is_empty() and str(e.get("kind", "")) == "pledge":
			pinned = it
		else:
			items.append(it)
	items.sort_custom(_chapter_before)
	var shown: Array = items.slice(maxi(0, items.size() - (n - 1 if not pinned.is_empty() else n)))
	if not pinned.is_empty():
		shown.append(pinned)
		shown.sort_custom(_chapter_before)
	var lines: PackedStringArray = []
	for it: Array in shown:
		lines.append("sol %d  %s" % [int(it[2].clock_sol), _first_sentence(str(it[2].text))])
	return "\n".join(lines)


func _chapter_before(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]


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
	var life := w.lifecycle.counts(w.beings, w.t)
	var n := {}
	for b in w.beings:
		var key: String = b.state
		if not STATES.has(key):
			key = "idle"  # to_door and any other inside state read as idle
		n[key] = int(n.get(key, 0)) + 1
	var parts: PackedStringArray = []
	for s in STATES:
		parts.append("%s %d" % [s, int(n.get(s, 0))])
	return "Beings: " + "  ".join(parts) + "\n" \
			+ "Babies %d  toddlers %d  children %d  teens %d  adults %d  pregnancies %d" % [
			life.baby, life.toddler, life.child, life.teen, life.adult, w.lifecycle.pregnancies.size()]


func _log_text(w: SimWorld) -> String:
	var lines: PackedStringArray = ["Log"]
	_log_shown = w.log.slice(maxi(0, w.log.size() - LOG_LINES))
	for e: Dictionary in _log_shown:
		lines.append("  sol %d  %s" % [int(e.clock_sol), e.text])
	return "\n".join(lines)
