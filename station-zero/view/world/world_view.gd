extends Node2D
## The sprite world view (spec sprite-view.md 4 to 10). A stack of draw layers under one camera transform, all painted
## from the view model (view/model): terrain, footprints, tunnels, transit beings, shadows, y-sorted entities, dust,
## the day/night multiply tint, additive lights and the selection outline. Nothing here animates or decides; it reads
## the sim through the model and never writes it.
##
## The camera is the model's (view/model/camera.gd) applied as this node's transform; the HUD is a sibling in the
## default canvas, above this view's canvas layer, so it is not zoomed.

const ViewModel = preload("res://view/model/view_model.gd")
const Light = preload("res://view/model/light.gd")
const WorldCtx = preload("res://view/world/world_ctx.gd")
const TerrainDraw = preload("res://view/world/terrain_draw.gd")
const CorridorDraw = preload("res://view/world/corridor_draw.gd")
const BuildingDraw = preload("res://view/world/building_draw.gd")
const ParticleDraw = preload("res://view/world/particle_draw.gd")
const WorldLayer = preload("res://view/world/world_layer.gd")

## Layer ids back to front (spec 6): L0/L1 terrain, L2 footprints, L3 tunnels, L4 transit beings, L5 shadows,
## L6 entities (buildings, later outside beings), L7 dust, L8 tint, L9 lights, L10 selection.
const LAYERS: Array[String] = ["terrain", "footprints", "corridors", "transit", "shadows", "entities", "dust", "tint",
		"lights", "selection"]

## Emitted when M switches between the sprite view and the debug dot map.
signal debug_map_changed(on: bool)

var vm: ViewModel
var art: Dictionary
var lib := ArtLibrary.new()
var ctx: WorldCtx
## When true the model is not refreshed from real time (screenshots settle it by hand and then freeze it).
var freeze_model := false

var layers: Dictionary = {}
var _sim: Node
var _terrain := TerrainDraw.new()
var _corridors := CorridorDraw.new()
var _buildings := BuildingDraw.new()
var _particles := ParticleDraw.new()
var _press := Vector2.ZERO
var _pressed := false
var _dragging := false
var _was_debug := false
var _keycodes: Dictionary = {}
## Real seconds of the last model refresh, kept while the model is frozen so spark streaks keep their length.
var _trail_dt := 0.0


func _ready() -> void:
	if _sim == null and has_node("/root/Sim"):
		setup(get_node("/root/Sim"))


## Binds the sim host (anything with a `world`). Separate from _ready so a test can drive the view without a tree.
func setup(sim: Node) -> void:
	if _sim == sim and vm != null and vm.world == sim.world:
		return
	_sim = sim
	art = SimData.load_json("art.json")
	_build_layers()
	_bind(sim.world)


func _bind(world: SimWorld) -> void:
	if not lib.load_manifest():
		push_error("sprite view: art manifest missing or unreadable, run tools/build_all.py")
		return
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ArtLibrary.MANIFEST))
	vm = ViewModel.new(world, art, man)
	ctx = WorldCtx.new(vm, lib)
	_resolve_keys()
	_update_frame(0.0)


func _build_layers() -> void:
	if not layers.is_empty():
		return
	for id in LAYERS:
		var n := WorldLayer.new()
		n.name = id.capitalize()
		n.view = self
		n.layer_id = id
		n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(n)
		layers[id] = n
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	layers["lights"].material = add
	var mul := CanvasItemMaterial.new()
	mul.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	layers["tint"].material = mul


func _resolve_keys() -> void:
	_keycodes.clear()
	for action in art.camera.keys:
		var codes: Array = []
		for key_name in art.camera.keys[action]:
			var k := OS.find_keycode_from_string(String(key_name))
			if k == KEY_NONE:
				k = OS.find_keycode_from_string(String(key_name).replace("_", " "))
			if k != KEY_NONE:
				codes.append({"name": key_name, "code": k})
		_keycodes[action] = codes


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	if _sim == null or vm == null:
		return
	if _sim.world != vm.world:
		_bind(_sim.world)
	if vm.debug_map != _was_debug:
		_was_debug = vm.debug_map
		visible = not vm.debug_map
		debug_map_changed.emit(vm.debug_map)
	if vm.debug_map:
		return
	_poll_keys(delta)
	_update_frame(0.0 if freeze_model else delta)


## One refresh of the model and the context, then a redraw of every layer.
func _update_frame(dt: float) -> void:
	var size := _viewport_size()
	vm.camera_rect = _view_rect(size)
	if dt > 0.0 or vm.real_time == 0.0:
		vm.update(dt)
	var rect := _view_rect(size)
	vm.camera_rect = rect
	if dt > 0.0:
		_trail_dt = dt
	ctx.begin_frame(rect, _trail_dt)
	position = size * 0.5 - vm.camera.center * vm.camera.zoom
	scale = Vector2(vm.camera.zoom, vm.camera.zoom)
	for id in layers:
		layers[id].queue_redraw()


func _viewport_size() -> Vector2:
	return get_viewport_rect().size if is_inside_tree() else Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))


func _view_rect(size: Vector2) -> Rect2:
	var extent := size / vm.camera.zoom
	return Rect2(vm.camera.center - extent * 0.5, extent)


## Advances only the view model by `seconds` of real time in steps of the model's own dt clamp, so doors ease open and
## particles fly before a screenshot. The sim is not touched.
func settle_view(seconds: float) -> void:
	var step := float(art.door.max_dt_s)
	var left := seconds
	while left > 0.0:
		var dt := minf(step, left)
		vm.update(dt)
		left -= dt
	_trail_dt = float(art.walk.interp_sample_interval_s[0])
	_update_frame(0.0)


func set_camera(zoom_in: float, center_in: Vector2) -> void:
	vm.camera.set_view(zoom_in, center_in)
	_update_frame(0.0)


## View-side state for screenshots: debug_map, select (a building kind or id), peek, hud is handled by the HUD scene.
func apply_shot_view(opts: Dictionary) -> void:
	if opts.has("debug_map"):
		vm.debug_map = bool(opts.debug_map)
	if opts.has("select"):
		var want: Variant = opts.select
		for b in vm.world.buildings.list:
			if b.kind == str(want) or str(b.id) == str(want):
				vm.selection.selected = b.id
				break
	if opts.has("peek"):
		vm.selection.peek = bool(opts.peek)


# ---------------------------------------------------------------- input

func _poll_keys(dt: float) -> void:
	var dir := Vector2(_held("pan_right") - _held("pan_left"), _held("pan_down") - _held("pan_up"))
	if dir != Vector2.ZERO:
		vm.camera.pan(dir, dt)
	var zoom_dir := int(_held("zoom_in")) - int(_held("zoom_out"))
	if zoom_dir != 0:
		vm.camera.zoom_key(zoom_dir, dt)


func _held(action: String) -> float:
	for k in _keycodes.get(action, []):
		if Input.is_key_pressed(k.code):
			return 1.0
	return 0.0


func _unhandled_input(event: InputEvent) -> void:
	if vm == null:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo:
			for action in _keycodes:
				for entry in _keycodes[action]:
					if entry.code == k.keycode:
						vm.press_key(entry.name)
		return
	if vm.debug_map:
		return
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion and _pressed:
		var m := event as InputEventMouseMotion
		if not _dragging and m.position.distance_to(_press) >= float(art.camera.drag_threshold_px):
			_dragging = true
		if _dragging:
			vm.camera.drag(m.relative)


func _mouse_button(m: InputEventMouseButton) -> void:
	var size := _viewport_size()
	if m.pressed and m.button_index == MOUSE_BUTTON_WHEEL_UP:
		vm.camera.wheel(1, m.position, size)
	elif m.pressed and m.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		vm.camera.wheel(-1, m.position, size)
	elif m.button_index == MOUSE_BUTTON_LEFT:
		if m.pressed:
			_pressed = true
			_dragging = false
			_press = m.position
		else:
			if _pressed and not _dragging:
				vm.tap_screen(_press, m.position, size)
			_pressed = false
			_dragging = false


# ---------------------------------------------------------------- drawing

## Called by a layer's _draw. Layers whose content arrives in later steps stay empty.
func draw_layer(c: Object, id: String) -> void:
	if vm == null or ctx == null:
		return
	match id:
		"terrain":
			_terrain.draw(c, ctx)
		"corridors":
			_corridors.draw(c, ctx)
		"shadows":
			_buildings.draw_shadows(c, ctx)
		"entities":
			_buildings.draw_entities(c, ctx)
		"dust":
			_particles.draw_dust(c, ctx)
		"tint":
			_draw_tint(c)
		"lights":
			_buildings.draw_lights(c, ctx)
			_corridors.draw_lamps(c, ctx)
			_particles.draw_sparks(c, ctx)


## The day, dusk and night multiply layers (spec 5.1) as one multiply rect: each layer lerps white toward its colour by
## its alpha, and multiplying them in order is the product.
func _draw_tint(c: Object) -> void:
	c.draw_rect(ctx.view_rect.grow(float(art.camera.pan_margin_px)), tint_color())


## The combined multiply colour of the three tint layers for the current hour.
func tint_color() -> Color:
	var a: Dictionary = Light.tint_alphas(ctx.hour, art)
	var l: Dictionary = art.light
	var out := Color.WHITE
	for entry in [["day_tint", a.day], ["dusk_tint", a.dusk], ["night_tint", a.night]]:
		var tint := Color.html(String(l[entry[0]].color))
		var k := float(entry[1])
		out = Color(out.r * (1.0 - k + k * tint.r), out.g * (1.0 - k + k * tint.g), out.b * (1.0 - k + k * tint.b), 1.0)
	return out
