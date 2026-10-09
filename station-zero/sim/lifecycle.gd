class_name Lifecycle
extends RefCounted
## Human life stages and pregnancies, measured on a Gregorian calendar in simulation hours.
## The civil epoch only anchors month lengths; it does not change the Mars clock or sky.

const SECONDS_PER_HOUR := 3600.0
const MONTHS_PER_YEAR := 12
const STAGES := ["baby", "toddler", "child", "teen", "adult"]

var cfg: Dictionary
## Parent id -> {parent_id, building_id, conceived_t, due_t}.
var pregnancies: Dictionary = {}
var last_conception_t: Dictionary = {}
var _epoch_unix: float
var _birthdays: Dictionary = {}


func _init() -> void:
	cfg = SimData.lifecycle().duplicate(true)
	_epoch_unix = Time.get_unix_time_from_datetime_string(str(cfg.calendar_epoch))


func date_at(t: float) -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(floor(_epoch_unix + t * SECONDS_PER_HOUR)))


func time_at(date: Dictionary) -> float:
	return (float(Time.get_unix_time_from_datetime_dict(date)) - _epoch_unix) / SECONDS_PER_HOUR


static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0) else 28
	return 30 if month in [4, 6, 9, 11] else 31


## Add whole calendar months, retaining time of day and clamping to the target month's last day.
func add_months(t: float, months: int) -> float:
	var unix := _epoch_unix + t * SECONDS_PER_HOUR
	var date := date_at(t)
	var index := int(date.year) * MONTHS_PER_YEAR + int(date.month) - 1 + months
	date.year = int(floor(float(index) / MONTHS_PER_YEAR))
	date.month = posmod(index, MONTHS_PER_YEAR) + 1
	date.day = mini(int(date.day), _days_in_month(int(date.year), int(date.month)))
	return time_at(date) + (unix - floor(unix)) / SECONDS_PER_HOUR


func birthday(b: Being, years: int) -> float:
	var record: Dictionary = _birthdays.get(b.id, {})
	if record.is_empty() or record.born_t != b.born_t:
		record = {"born_t": b.born_t, "times": {}}
		_birthdays[b.id] = record
	if not record.times.has(years):
		record.times[years] = add_months(b.born_t, years * MONTHS_PER_YEAR)
	return float(record.times[years])


func is_adult(b: Being, t: float) -> bool:
	return t + SimWorld.STEP_EPS >= birthday(b, int(cfg.adult_age_years))


func stage(b: Being, t: float) -> String:
	if is_adult(b, t):
		return "adult"
	if t + SimWorld.STEP_EPS >= birthday(b, int(cfg.teen_age_years)):
		return "teen"
	if t + SimWorld.STEP_EPS >= birthday(b, int(cfg.child_age_years)):
		return "child"
	if t + SimWorld.STEP_EPS >= birthday(b, int(cfg.toddler_age_years)):
		return "toddler"
	return "baby"


func counts(beings: Array[Being], t: float) -> Dictionary:
	var out := {"baby": 0, "toddler": 0, "child": 0, "teen": 0, "adult": 0}
	for b in beings:
		var key := stage(b, t)
		out[key] += 1
	return out


func can_conceive(b: Being, t: float) -> bool:
	return is_adult(b, t) and not pregnancies.has(b.id)


func conception_cooldown_over(building_id: int, t: float, cooldown_h: float) -> bool:
	return not last_conception_t.has(building_id) \
			or t - float(last_conception_t[building_id]) > cooldown_h + SimWorld.STEP_EPS


func conceive(b: Being, building_id: int, t: float) -> void:
	assert(can_conceive(b, t))
	pregnancies[b.id] = {"parent_id": b.id, "building_id": building_id, "conceived_t": t,
			"due_t": add_months(t, int(cfg.pregnancy_months))}
	if int(cfg.pregnancy_months) > 0:
		last_conception_t[building_id] = t


## Caller removes a due pregnancy immediately before delivery, releasing its reserved population place.
func due(t: float) -> Array:
	var out: Array = []
	for record in pregnancies.values():
		if t + SimWorld.STEP_EPS >= float(record.due_t):
			out.append(record)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.due_t < b.due_t or (a.due_t == b.due_t and a.parent_id < b.parent_id))
	return out


func remove_being(id: int) -> void:
	pregnancies.erase(id)
	_birthdays.erase(id)
