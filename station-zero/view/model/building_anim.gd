extends RefCounted
## Per-building view state: door openness and the offline power fade (spec sprite-view.md 5.2 to 5.4).

const Doors = preload("res://view/model/doors.gd")
const Light = preload("res://view/model/light.gd")

var art: Dictionary
var id: int
var kind: String
## 0..1, eases in real time.
var door_open := 0.0
## 1 online, 0 offline, linear over offline.fade_s of real time.
var power := 1.0


func _init(art_in: Dictionary, id_in: int, kind_in: String) -> void:
	art = art_in
	id = id_in
	kind = kind_in


func update(dt: float, want_door: bool, offline: bool) -> void:
	door_open = Doors.ease_open(door_open, want_door, dt, art)
	var step := dt / float(art.offline.fade_s)
	power = clampf(power + (-step if offline else step), 0.0, 1.0)


## Final alphas of the exterior lights and the offline dim overlay. cut is the roof cut (vis = 1 - cut).
func lights(h: float, real_time: float, cut: float) -> Dictionary:
	var vis := 1.0 - cut
	var p := Light.pulse(real_time, id, kind, art)
	return {
		"accent": Light.accent_alpha(h, p, vis, art) * power,
		"windows": Light.window_alpha(h, vis, art) * power,
		"strip": Light.strip_alpha(h, art) * power,
		"door_glow": Light.door_glow_alpha(h, door_open, art) * power,
		"dim": float(art.offline.dim_alpha) * (1.0 - power) * vis,
	}
