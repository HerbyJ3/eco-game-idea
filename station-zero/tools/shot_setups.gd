extends RefCounted
## Named sim setups for tools/shot.gd (--setup name). Each takes a built SimWorld and may change it
## through the sim's own API, before the steps run. Later steps register more names here.

static func apply(name: String, world: SimWorld) -> bool:
	match name:
		"founders":
			# The default founder world, exactly as SimWorld builds it. Nothing to change.
			return true
	return false
