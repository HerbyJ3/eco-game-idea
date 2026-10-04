extends RefCounted
## Light curve, lamp targets, pulses and light alphas (spec sprite-view.md 4.4, 5.1, 5.3, 5.2 glow). h is the Mars hour.


## Night factor N: 0 in full day, 1 in full dark. Linear ramps 19:00 to 21:30 and 05:30 to 07:00 (art.light).
static func night(h: float, art: Dictionary) -> float:
	var l: Dictionary = art.light
	var dusk_start := float(l.dusk_start_h)
	var dark_start := float(l.dark_start_h)
	var dark_end := float(l.dark_end_h)
	var day_start := float(l.day_start_h)
	if h >= dark_start or h <= dark_end:
		return 1.0
	if h > dusk_start:
		return (h - dusk_start) / (dark_start - dusk_start)
	if h >= day_start:
		return 0.0
	return (day_start - h) / (day_start - dark_end)


static func daylight(h: float, art: Dictionary) -> float:
	return 1.0 - night(h, art)


## The blue dusk bump: gain x N x (1 - N), 0 at full day and full dark.
static func dusk(h: float, art: Dictionary) -> float:
	var n := night(h, art)
	return float(art.light.dusk_bump_gain) * n * (1.0 - n)


## Final alphas of the three full-screen multiply layers.
static func tint_alphas(h: float, art: Dictionary) -> Dictionary:
	var l: Dictionary = art.light
	return {"day": float(l.day_tint.alpha) * daylight(h, art), "dusk": float(l.dusk_tint.alpha) * dusk(h, art),
			"night": float(l.night_tint.alpha) * night(h, art)}


## Horizontal shadow offset in px: clamp((h - noon) / divisor, -clamp, clamp) x scale. Noon is half the clock day.
static func shadow_dx(h: float, art: Dictionary) -> float:
	var s: Dictionary = art.light.shadow
	var noon := float(SimData.calendar().hours_per_sol_clock) * 0.5
	var k := float(s.dx_clamp)
	return clampf((h - noon) / float(s.dx_hour_divisor), -k, k) * float(s.dx_scale_px)


## Helmet lamp level a being is easing toward: 0 inside; 1 while the sim's lamp_on is true; otherwise low + (1 - low) N
## across the dusk ramp, N across the dawn ramp, 0 by day.
static func lamp_target(h: float, outside: bool, lamp_on: bool, art: Dictionary) -> float:
	if not outside:
		return 0.0
	if lamp_on:
		return 1.0
	var l: Dictionary = art.light
	var low := float(art.lamp.low)
	if h >= float(l.dusk_start_h) and h < float(l.dark_start_h):
		return low + (1.0 - low) * night(h, art)
	if h >= float(l.dark_end_h) and h < float(l.day_start_h):
		return night(h, art)
	return 0.0


## Glow request for a helmet lamp: only for eva and construction suits, alphas scaled by the level.
static func lamp_glow(suit_kind: String, level: float, art: Dictionary) -> Dictionary:
	if (suit_kind != "eva" and suit_kind != "construction") or level <= 0.0:
		return {"on": false, "outer_alpha": 0.0, "core_alpha": 0.0, "ground_alpha": 0.0}
	var l: Dictionary = art.lamp
	return {"on": true, "outer_alpha": float(l.outer_alpha) * level, "core_alpha": float(l.core_alpha) * level,
			"ground_alpha": float(l.ground_alpha) * level}


## Accent pulse 0..1; reactors pulse faster, every building has its own phase from its id.
static func pulse(real_time: float, building_id: int, kind: String, art: Dictionary) -> float:
	var a: Dictionary = art.light.accent
	var rates: Dictionary = a.pulse_rate_rad_s
	var rate := float(rates.get(kind, rates["default"]))
	return 0.5 + 0.5 * sin(real_time * rate + building_id * float(a.id_phase_rad))


## Accent mask alpha before the offline power factor: day part plus night part, times visibility (1 - cut).
static func accent_alpha(h: float, p: float, vis: float, art: Dictionary) -> float:
	var a: Dictionary = art.light.accent
	var n := night(h, art)
	var day := float(a.day_base) + float(a.day_pulse) * p
	var dark := float(a.night_base) + float(a.night_pulse) * p
	return (day + n * dark) * vis


static func window_alpha(h: float, vis: float, art: Dictionary) -> float:
	var w: Dictionary = art.light.windows
	var n := night(h, art)
	if n <= float(w.night_min):
		return 0.0
	return float(w.alpha) * n * vis


## Door strip on the ground under the footprint's bottom edge.
static func strip_alpha(h: float, art: Dictionary) -> float:
	var s: Dictionary = art.light.ground_strip
	var n := night(h, art)
	if n <= float(s.night_min):
		return 0.0
	return float(s.alpha) * n


## Warm glow at the open door: alpha x open x (base + N), nothing while the door is nearly shut.
static func door_glow_alpha(h: float, open: float, art: Dictionary) -> float:
	var d: Dictionary = art.door
	if open <= float(d.glow_min_open):
		return 0.0
	return float(d.glow_alpha) * open * (float(d.glow_night_base) + night(h, art))
