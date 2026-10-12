extends RefCounted
## Real-time pacing of the being panel (docs/specs/emotions.md 7.1 rules 5 and 6). Pure: every call is handed the real
## time in seconds, so it holds no clock and no simulation state. Refreshes are served at most `refresh_hz` times a second
## of real time, the shown band changes at most once per `hold_s`, and the "has died" beat lasts `died_beat_s`.

var _refresh_gap: float
var _hold: float
var _died_beat: float
var _last_refresh := -INF
var _shown := -1
var _shown_at := -INF
var _died_at := -INF


func _init(cfg: Dictionary) -> void:
	_refresh_gap = 1.0 / float(cfg.refresh_hz)
	_hold = float(cfg.hold_s)
	_died_beat = float(cfg.died_beat_s)


## True when a refresh may be served at real time `now_s`; the call that returns true starts the next gap.
func refresh_due(now_s: float) -> bool:
	if now_s - _last_refresh < _refresh_gap:
		return false
	_last_refresh = now_s
	return true


## The band to show: the first call takes `wanted`; later a change waits until `hold_s` has passed since the last change.
func shown_band(now_s: float, wanted: int) -> int:
	if _shown < 0:
		_shown = wanted
		_shown_at = now_s
	elif wanted != _shown and now_s - _shown_at >= _hold:
		_shown = wanted
		_shown_at = now_s
	return _shown


## Forgets the shown band (a different being was selected).
func reset() -> void:
	_last_refresh = -INF
	_shown = -1
	_shown_at = -INF
	_died_at = -INF


func begin_died(now_s: float) -> void:
	_died_at = now_s


func died_open(now_s: float) -> bool:
	return now_s - _died_at < _died_beat
