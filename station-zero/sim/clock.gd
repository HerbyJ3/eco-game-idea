class_name Clock
extends RefCounted
## Mars time. All time is Earth hours `t` since the epoch.
## Formulas: HANDOFF.md section 3.

var sol_h: float
var year_h: float
var earth_year_h: float
var earth_day_h: float
var ecc: float
var m0: float
var perihelion_ls: float
var start_hour: float
var dawn_hour: float
var clock_hours: float
var sign_width: float
var season_width: float
var seasons: Array
var site_name: String
var site_lon: float
var lon_per_tile: float


func _init(cal: Dictionary = {}) -> void:
	if cal.is_empty():
		cal = SimData.calendar()
	earth_day_h = cal.earth_day_hours
	sol_h = cal.sol_hours
	year_h = cal.mars_year_days * earth_day_h
	earth_year_h = cal.earth_year_days * earth_day_h
	ecc = cal.eccentricity
	m0 = cal.mean_anomaly_epoch_deg
	perihelion_ls = cal.perihelion_ls_deg
	start_hour = sol_h * cal.start_hour_sol_fraction
	dawn_hour = cal.dawn_hour
	clock_hours = cal.hours_per_sol_clock
	sign_width = cal.sign_width_deg
	season_width = cal.season_width_deg
	seasons = cal.seasons
	site_name = cal.site.name
	site_lon = cal.site.lon
	lon_per_tile = cal.site.lon_per_tile


static func mod360(v: float) -> float:
	return fposmod(v, 360.0)


func sign_of(lon: float) -> int:
	return int(floor(mod360(lon) / sign_width)) % int(round(360.0 / sign_width))


## Solar longitude Ls in degrees [0, 360). Mars-tropical zodiac: the sun sign is the season.
func mars_ls(t: float) -> float:
	var m := deg_to_rad(m0 + 360.0 * t / year_h)
	var nu := m + 2.0 * ecc * sin(m) + 1.25 * ecc * ecc * sin(2.0 * m)
	return mod360(rad_to_deg(nu) + perihelion_ls)


## Local hour of the sol on a 24-hour clock, [0, 24).
func mars_hour(t: float) -> float:
	return fposmod(t / sol_h, 1.0) * clock_hours


func earth_hour(t: float) -> float:
	return fposmod(t, earth_day_h)


func sol_index(t: float) -> int:
	return int(floor(t / sol_h)) + 1


func year_index(t: float) -> int:
	return int(floor(t / year_h)) + 1


func sols_per_year() -> float:
	return year_h / sol_h


func season_of_ls(ls: float) -> String:
	return seasons[int(floor(mod360(ls) / season_width)) % seasons.size()]


func season(t: float) -> String:
	return season_of_ls(mars_ls(t))


## Birthplace longitude for a building centered at tile x (game scale).
func lon_of_tile(center_tile_x: float) -> float:
	return site_lon + center_tile_x * lon_per_tile
