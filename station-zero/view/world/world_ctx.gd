extends RefCounted
## Per-frame drawing context shared by the layer drawers (spec sprite-view.md 6). It holds what the model says for this
## frame (hour, light, shadow vector, camera rect) and the helpers that put textures on a canvas. The drawers decide
## nothing about animation: every position, frame, door offset and light value comes from view/model.
##
## Drawers take their canvas as an Object with the CanvasItem draw_* methods, so a test can hand them a recorder and
## inspect the commands without a renderer. `record` makes this context log every textured draw as well.

const Light = preload("res://view/model/light.gd")
const ViewModel = preload("res://view/model/view_model.gd")

var vm: ViewModel
var art: Dictionary
var man: Dictionary
var lib: ArtLibrary
var world: SimWorld
## Mars hour of the sim.
var hour := 0.0
## Night factor N (0 day, 1 dark) and daylight L = 1 - N.
var night := 0.0
var daylight := 1.0
## Shadow offset (dx, dy) in world px for this hour.
var shadow := Vector2.ZERO
var real_time := 0.0
## Real seconds of the last refresh, clamped like the model's.
var dt := 0.0
## The world rect the camera sees.
var view_rect := Rect2()
var tile_px := 1.0
## False below `art.lod.detail_min_zoom`: far zoom skips door leaves, halos, ground strips, pads, being shadows and lamp glows.
var detail := true
## Soft round gradient (white in the middle, clear at the edge), for glows.
var glow: Texture2D
## True when textured draws are appended to `log` as {id, rect, tex_size, src, alpha}.
var record := false
var log: Array = []
var _colors: Dictionary = {}


func _init(vm_in: ViewModel, lib_in: ArtLibrary) -> void:
	vm = vm_in
	art = vm_in.art
	man = vm_in.man
	lib = lib_in
	world = vm_in.world
	tile_px = float(SimData.buildings().tile_px)
	glow = _make_glow()


## Refreshes the per-frame values from the world and the camera.
func begin_frame(view_rect_in: Rect2, dt_real: float) -> void:
	world = vm.world
	hour = world.clock.mars_hour(world.t)
	night = Light.night(hour, art)
	daylight = 1.0 - night
	shadow = Vector2(Light.shadow_dx(hour, art), float(art.light.shadow.dy_px))
	real_time = vm.real_time
	dt = minf(dt_real, float(art.door.max_dt_s))
	view_rect = view_rect_in
	detail = vm.camera.zoom >= float(art.lod.detail_min_zoom)
	log.clear()


static func _make_glow() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


## Colour from an art.json hex string with an alpha, cached.
func col(hex: String, alpha: float = 1.0) -> Color:
	if not _colors.has(hex):
		_colors[hex] = Color.html(hex)
	var c: Color = _colors[hex]
	return Color(c.r, c.g, c.b, alpha)


func tex(id: String) -> Texture2D:
	return lib.texture(id)


func visible(rect: Rect2) -> bool:
	return view_rect.intersects(rect)


## Draws a manifest texture stretched over rect (callers pass rects of the texture's own aspect).
func blit(c: Object, id: String, rect: Rect2, alpha: float = 1.0) -> void:
	var t := lib.texture(id)
	if t == null or alpha <= 0.0:
		return
	c.draw_texture_rect(t, rect, false, Color(1, 1, 1, alpha))
	if record:
		log.append({"id": id, "rect": rect, "tex_size": t.get_size(), "src": Rect2(Vector2.ZERO, t.get_size()), "alpha": alpha})


## Draws only the part of `rect` inside `clip`, cutting the source region by the same fraction (nothing is rescaled).
func blit_clip(c: Object, id: String, rect: Rect2, clip: Rect2, alpha: float = 1.0) -> void:
	var t := lib.texture(id)
	var inter := rect.intersection(clip)
	if t == null or alpha <= 0.0 or inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return
	var k := t.get_size() / rect.size
	var src := Rect2((inter.position - rect.position) * k, inter.size * k)
	c.draw_texture_rect_region(t, inter, src, Color(1, 1, 1, alpha))
	if record:
		log.append({"id": id, "rect": inter, "tex_size": t.get_size(), "src": src, "alpha": alpha})


## One atlas frame drawn at `feet` (the sprite's pivot) with the given rotation (rad) and horizontal mirror. `dest` is the
## cell rect relative to the pivot, `src` the frame in the atlas. The log gets the transform too.
func sprite(c: Object, id: String, dest: Rect2, src: Rect2, feet: Vector2, rot: float, mirror: bool,
		alpha: float = 1.0) -> void:
	var t := lib.texture(id)
	if t == null or alpha <= 0.0:
		return
	c.draw_set_transform(feet, rot, Vector2(-1.0 if mirror else 1.0, 1.0))
	c.draw_texture_rect_region(t, dest, src, Color(1, 1, 1, alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if record:
		log.append({"id": id, "rect": dest, "tex_size": t.get_size(), "src": src, "alpha": alpha, "feet": feet,
				"rot": rot, "mirror": mirror})


## Draws a texture that is not a manifest entry (a runtime-built one, like the selection outline); logged under `id`.
func blit_texture(c: Object, id: String, t: Texture2D, rect: Rect2, alpha: float) -> void:
	if t == null or alpha <= 0.0:
		return
	c.draw_texture_rect(t, rect, false, Color(1, 1, 1, alpha))
	if record:
		log.append({"id": id, "rect": rect, "tex_size": t.get_size(), "src": Rect2(Vector2.ZERO, t.get_size()), "alpha": alpha})


## A soft additive ellipse: the glow gradient squashed to radii (rx, ry) around p.
func glow_ellipse(c: Object, p: Vector2, rx: float, ry: float, color: Color) -> void:
	c.draw_texture_rect(glow, Rect2(p - Vector2(rx, ry), Vector2(rx, ry) * 2.0), false, color)


## A soft additive disc: the glow gradient scaled to radius r around p.
func glow_disc(c: Object, p: Vector2, r: float, color: Color) -> void:
	c.draw_texture_rect(glow, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, color)


## A filled ellipse centred at p with radii (rx, ry).
func ellipse(c: Object, p: Vector2, rx: float, ry: float, color: Color) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	c.draw_set_transform(p, 0.0, Vector2(1.0, ry / rx))
	c.draw_circle(Vector2.ZERO, rx, color)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
