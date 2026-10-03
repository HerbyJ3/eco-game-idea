class_name SimData
extends RefCounted
## Loads tunables from res://data/*.json. The sim never hard-codes numbers.

const DATA_DIR := "res://data/"

static var _cache: Dictionary = {}


static func load_json(file_name: String) -> Variant:
	if _cache.has(file_name):
		return _cache[file_name]
	var path := DATA_DIR + file_name
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("SimData: cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("SimData: invalid JSON in %s" % path)
	_cache[file_name] = parsed
	return parsed


static func calendar() -> Dictionary:
	return load_json("calendar.json")


static func signs() -> Array:
	return load_json("signs.json")


static func persona() -> Dictionary:
	return load_json("persona.json")


static func sim() -> Dictionary:
	return load_json("sim.json")
