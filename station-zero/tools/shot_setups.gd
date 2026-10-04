extends RefCounted
## Named sim setups for tools/shot.gd (--setup name). A setup is applied AFTER the fixed steps and the hour stepping
## (spec review nit 1), so stepping can never undo a staged state, and it changes the world only through the sim's own
## API. A "blank" setup runs on an empty world (SimWorld blank option); the others on the founder world.
## Being-related setups (suits, born pair, interiors) arrive with their view steps.

## Setups that need an empty world instead of the founders.
const BLANK: Array[String] = ["showcase", "showcase_offline", "showcase_door_habitat", "showcase_door_workshop"]
## Door setups: name -> kind of the building whose door opens.
const DOOR_KIND := {"showcase_door_habitat": "habitat", "showcase_door_workshop": "workshop"}
## Showcase buildings taken offline.
const OFFLINE_KINDS: Array[String] = ["habitat", "workshop"]


static func is_blank(name: String) -> bool:
	return name in BLANK


static func known(name: String) -> bool:
	return name == "founders" or name in BLANK


static func apply(name: String, world: SimWorld) -> bool:
	match name:
		"founders":
			# The default founder world, exactly as SimWorld builds it. Nothing to change.
			return true
		"showcase":
			_showcase(world)
			return true
		"showcase_offline":
			_showcase(world)
			for b in world.buildings.list:
				if b.kind in OFFLINE_KINDS:
					world.set_offline(b.id, true)
			return true
		"showcase_door_habitat", "showcase_door_workshop":
			_showcase(world)
			_miner_at_door(world, String(DOOR_KIND[name]))
			return true
	return false


## The six buildings of art.showcase, all built and online, no corridors.
static func _showcase(world: SimWorld) -> void:
	var art: Dictionary = SimData.load_json("art.json")
	for s: Dictionary in art.showcase.buildings:
		world.buildings.add(String(s.kind), int(s.tx), int(s.ty), 1.0, int(s.tw), int(s.th))


## A miner suiting up inside the building of `kind`: state to_door, suit_up, with a pit to go to. The door rule of the view
## (spec 5.2) opens that building's door.
static func _miner_at_door(world: SimWorld, kind: String) -> void:
	var tile := float(SimData.buildings().tile_px)
	for b in world.buildings.list:
		if b.kind != kind:
			continue
		var g := world.add_being(b.id, "builder")
		g.state = "to_door"
		g.suit_up = true
		g.mine_intent = world.resources.add_pit(b.door(tile).x + tile * 4.0, b.door(tile).y + tile * 6.0)
		return
