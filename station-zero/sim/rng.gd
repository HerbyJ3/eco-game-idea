class_name SimRng
extends RefCounted
## The one seeded RNG for the simulation. All sim randomness goes through here
## so a run can be repeated exactly from its seed.

var _rng := RandomNumberGenerator.new()
var seed_value: int


func _init(seed_in: int = 0) -> void:
	reseed(seed_in)


func reseed(seed_in: int) -> void:
	seed_value = seed_in
	_rng.seed = seed_in


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(p: float) -> bool:
	return _rng.randf() < p


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[_rng.randi_range(0, items.size() - 1)]
