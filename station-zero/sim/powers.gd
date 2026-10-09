class_name Powers
extends RefCounted
## God-power hooks. In Task 1 only the Good fortune supply multiplier (spec sections 2 and 7.2).
## Grace, Inspire and signs land here in Task 3+.

## Supply is multiplied while the world clock is below this. Never-set sentinel.
var power_multiplier_until: float = Buildings.NEVER
## Weak: Buildings holds this Powers, so a strong ref back would leak both.
var _buildings: WeakRef


func _init(buildings_in: Buildings) -> void:
	_buildings = weakref(buildings_in)


## Raises supply until `until_t` and resets the 3 h re-online hold.
func set_power_multiplier(until_t: float) -> void:
	power_multiplier_until = until_t
	var b: Buildings = _buildings.get_ref()
	if b != null:
		b.clear_short_hold()
