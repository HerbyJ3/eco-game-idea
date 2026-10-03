class_name MarsSky
extends RefCounted
## Birth charts. Mars-born: sun, deimos, phobos, rise, earth. Earth-born: sun, moon, rise.
## Formulas: HANDOFF.md section 3; prototype marsChart/earthChart is the tiebreaker.

var clock: Clock
var phobos_h: float
var deimos_h: float
var luna_h: float
var deimos_offset: float
var phobos_offset: float
var earth_au: float
var mars_au: float
var earth_epoch_angle: float
var mars_angle_from_ls: float
var earth_sun_offset: float
var luna_offset: float


func _init(clock_in: Clock = null, cal: Dictionary = {}) -> void:
	if cal.is_empty():
		cal = SimData.calendar()
	clock = clock_in if clock_in != null else Clock.new(cal)
	phobos_h = cal.phobos_hours
	deimos_h = cal.deimos_hours
	luna_h = cal.luna_days * cal.earth_day_hours
	var s: Dictionary = cal.sky
	deimos_offset = s.deimos_offset_deg
	phobos_offset = s.phobos_offset_deg
	earth_au = s.earth_orbit_au
	mars_au = s.mars_orbit_au
	earth_epoch_angle = s.earth_epoch_angle_deg
	mars_angle_from_ls = s.mars_angle_from_ls_deg
	earth_sun_offset = s.earth_sun_offset_deg
	luna_offset = s.luna_offset_deg


## Direction (deg) from Mars to Earth, as seen against the zodiac.
func earth_direction(t: float) -> float:
	var lm := deg_to_rad(clock.mars_ls(t) + mars_angle_from_ls)
	var le := deg_to_rad(earth_epoch_angle + 360.0 * t / clock.earth_year_h)
	return Clock.mod360(rad_to_deg(atan2(
		earth_au * sin(le) - mars_au * sin(lm),
		earth_au * cos(le) - mars_au * cos(lm))))


func phobos_lon(t: float) -> float:
	return 360.0 * t / phobos_h + phobos_offset


func deimos_lon(t: float) -> float:
	return 360.0 * t / deimos_h + deimos_offset


## Ascendant: at dawn (hour 6) it equals sign(Ls + lon); it sweeps the zodiac once per sol.
func rise_lon(sun_lon: float, hour: float, lon: float) -> float:
	return sun_lon + (hour - clock.dawn_hour) / clock.clock_hours * 360.0 + lon


func mars_chart(t: float, lon: float) -> Dictionary:
	var ls := clock.mars_ls(t)
	return {
		"world": "mars",
		"sun": clock.sign_of(ls),
		"deimos": clock.sign_of(deimos_lon(t)),
		"phobos": clock.sign_of(phobos_lon(t)),
		"rise": clock.sign_of(rise_lon(ls, clock.mars_hour(t), lon)),
		"earth": clock.sign_of(earth_direction(t)),
	}


func earth_chart(t: float, lon: float) -> Dictionary:
	var sun := 360.0 * t / clock.earth_year_h + earth_sun_offset
	return {
		"world": "earth",
		"sun": clock.sign_of(sun),
		"moon": clock.sign_of(360.0 * t / luna_h + luna_offset),
		"rise": clock.sign_of(rise_lon(sun, clock.earth_hour(t), lon)),
	}


static func chart_key(chart: Dictionary) -> String:
	if chart.world == "mars":
		return "m%d.%d.%d.%d.%d" % [chart.sun, chart.deimos, chart.phobos, chart.rise, chart.earth]
	return "e%d.%d.%d" % [chart.sun, chart.moon, chart.rise]


## An Earth-born founder: born 24 to 45 Earth years before landing at a random Earth longitude.
## Returns {"born": t, "lon": lon, "chart": chart}.
func founder_birth(rng: SimRng, founders_cfg: Dictionary) -> Dictionary:
	var age_h := rng.randf_range(
		founders_cfg.min_age_earth_years * clock.earth_year_h,
		founders_cfg.max_age_earth_years * clock.earth_year_h)
	var born := clock.start_hour - age_h
	var lon := rng.randf_range(founders_cfg.earth_lon_min, founders_cfg.earth_lon_max)
	return {"born": born, "lon": lon, "chart": earth_chart(born, lon)}
