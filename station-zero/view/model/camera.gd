extends RefCounted
## Camera state and its input rules (spec sprite-view.md 8). The caller feeds taps, wheel, keys and dt; nothing here
## touches the sim.

var art: Dictionary
var zoom: float
## World point at the middle of the viewport.
var center: Vector2
var follow := false
var follow_target := Vector2.ZERO
## Zoom the follow eases toward; 0 keeps the current zoom (and then the zoom plays no part in follow_done).
var follow_zoom := 0.0
var _union: Rect2


## footprint_union: union of all building footprints in world px (the view passes the founder layout when empty).
func _init(art_in: Dictionary, footprint_union: Rect2) -> void:
	art = art_in
	_union = footprint_union
	zoom = float(art.camera.zoom_default)
	center = footprint_union.get_center()


## The footprint union changed (a building was added).
func set_union(footprint_union: Rect2) -> void:
	_union = footprint_union
	_clamp_center()


## Where the centre may go: the union grown by camera.pan_margin_px.
func bounds() -> Rect2:
	return _union.grow(float(art.camera.pan_margin_px))


func _clamp_center() -> void:
	var bd := bounds()
	center = Vector2(clampf(center.x, bd.position.x, bd.end.x), clampf(center.y, bd.position.y, bd.end.y))


func _clamp_zoom() -> void:
	zoom = clampf(zoom, float(art.camera.zoom_min), float(art.camera.zoom_max))


func screen_to_world(p: Vector2, viewport: Vector2) -> Vector2:
	return center + (p - viewport * 0.5) / zoom


## Wheel zoom about the cursor: x wheel_step per notch (negative notches zoom out), the point under it stays fixed.
func wheel(notches: int, cursor: Vector2, viewport: Vector2) -> void:
	follow = false
	var anchor := screen_to_world(cursor, viewport)
	zoom *= pow(float(art.camera.wheel_step), notches)
	_clamp_zoom()
	center = anchor - (cursor - viewport * 0.5) / zoom
	_clamp_center()


## Key zoom, centre-anchored: dir +1 or -1, the multiplier per second held is camera.key_zoom_per_s.
func zoom_key(dir: int, dt: float) -> void:
	follow = false
	zoom *= pow(float(art.camera.key_zoom_per_s), dir * dt)
	_clamp_zoom()


## Pan by a screen direction at camera.pan_speed_screen_px_s (world speed = that over zoom).
func pan(screen_dir: Vector2, dt: float) -> void:
	follow = false
	if screen_dir != Vector2.ZERO:
		center += screen_dir.normalized() * float(art.camera.pan_speed_screen_px_s) * dt / zoom
	_clamp_center()


func reset(centroid: Vector2) -> void:
	zoom = float(art.camera.zoom_default)
	center = centroid
	follow = false
	_clamp_center()


## Follow easing, 1 - (1 - ease)^(60 dt), toward follow_target (and follow_zoom when set).
func update(dt: float) -> void:
	if follow:
		var k := 1.0 - pow(1.0 - float(art.camera.focus_ease_per_60hz_frame), 60.0 * dt)
		center = center.lerp(follow_target, k)
		if follow_zoom > 0.0:
			zoom = lerpf(zoom, follow_zoom, k)
			_clamp_zoom()


## Done when within camera.focus_done_pos_px of the target and, if a follow zoom is set, within focus_done_zoom_eps.
func follow_done() -> bool:
	var zoom_ok := follow_zoom <= 0.0 or absf(zoom - follow_zoom) <= float(art.camera.focus_done_zoom_eps)
	return zoom_ok and center.distance_to(follow_target) <= float(art.camera.focus_done_pos_px)


## The camera.keys action a key name maps to, "" for none.
func action_for_key(key_name: String) -> String:
	var keys: Dictionary = art.camera.keys
	for action in keys:
		if key_name in keys[action]:
			return String(action)
	return ""
