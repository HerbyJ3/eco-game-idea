extends RefCounted
## Per-being view state: walk phase, interpolated render position, moving flag, last move direction, lamp level
## (spec sprite-view.md 4.3, 4.4). One sample is pushed per refresh; nothing here depends on sim speed.

const FacingPose = preload("res://view/model/facing_pose.gd")

var art: Dictionary
var id: int
## Walk phase in radians, advanced by distance moved (clamped per refresh), never by time or by frame.
var phase := 0.0
## Helmet lamp level 0..1, eased toward its target.
var lamp_level := 0.0
## Last non-zero move vector (world px), Vector2.ZERO before the first move.
var move_dir := Vector2.ZERO
var _prev := Vector2.ZERO
var _new := Vector2.ZERO
var _t_prev := 0.0
var _t_new := 0.0
var _has_sample := false
var _last_move_t := 0.0
var _has_moved := false


func _init(art_in: Dictionary, id_in: int) -> void:
	art = art_in
	id = id_in


## Forgets the samples, so the next push_sample is a snap (a being that changed space: door, tunnel, interior).
## The walk phase is kept.
func reset_samples() -> void:
	_has_sample = false
	_has_moved = false
	move_dir = Vector2.ZERO


## Records the position seen this refresh. The first sample sets both samples.
func push_sample(pos: Vector2, real_time: float) -> void:
	var w: Dictionary = art.walk
	if not _has_sample:
		_has_sample = true
		_prev = pos
		_new = pos
		_t_prev = real_time
		_t_new = real_time
		return
	var v := pos - _new
	var d := v.length()
	if d >= float(w.min_move_px):
		phase += minf(d, float(w.max_advance_px_per_refresh)) * float(w.phase_per_px)
		_last_move_t = real_time
		_has_moved = true
		move_dir = v
	_prev = _new
	_t_prev = _t_new
	_new = pos
	_t_new = real_time


## True when a move of at least walk.min_move_px was seen within the last walk.moving_hold_s of real time.
func moving_at(real_time: float) -> bool:
	return _has_moved and real_time - _last_move_t <= float(art.walk.moving_hold_s)


func frame_index() -> int:
	return FacingPose.walk_frame(phase, art)


## Lerp from the previous to the newest sample over the (clamped) interval between them; the render lags one sample
## and holds the newest once nothing newer arrives.
func render_pos(real_time: float) -> Vector2:
	var bounds: Array = art.walk.interp_sample_interval_s
	var span := clampf(_t_new - _t_prev, float(bounds[0]), float(bounds[1]))
	return _prev.lerp(_new, clampf((real_time - _t_new) / span, 0.0, 1.0))


## Exponential ease toward the target with time constant lamp.fade_s (never overshoots).
func update_lamp(dt: float, target: float) -> void:
	lamp_level += (target - lamp_level) * (1.0 - exp(-dt / float(art.lamp.fade_s)))
