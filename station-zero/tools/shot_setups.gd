extends RefCounted
## Named sim setups for tools/shot.gd (--setup name). A setup is applied AFTER the fixed steps and the hour stepping
## (spec review nit 1), so stepping can never undo a staged state, and it changes the world only through the sim's own
## API. A "blank" setup runs on an empty world (SimWorld blank option); the others on the founder world.
## Being setups stage beings directly through the sim's own fields (no stepping), so a shot shows exactly that state.

## Setups that need an empty world instead of the founders.
const BLANK: Array[String] = ["showcase", "showcase_offline", "showcase_door_habitat", "showcase_door_workshop",
		"showcase_suits", "showcase_born_pair", "showcase_lamp_dusk", "showcase_interior_habitat", "showcase_interior_comms",
		"showcase_interior_workshop", "showcase_interior_talk"]
## Door setups: name -> kind of the building whose door opens.
const DOOR_KIND := {"showcase_door_habitat": "habitat", "showcase_door_workshop": "workshop"}
## Interior setups: name -> [kind, [[role, state], ...]] of the beings placed inside that building.
const INTERIORS := {
	"showcase_interior_habitat": ["habitat", [["builder", "idle"], ["curious", "sleep"], ["social", "idle"],
			["tender", "sleep"], ["builder", "sleep"], ["social", "idle"]]],
	"showcase_interior_comms": ["comms", [["social", "idle"], ["curious", "idle"], ["builder", "idle"], ["tender", "idle"]]],
	"showcase_interior_workshop": ["workshop", [["builder", "idle"], ["builder", "idle"], ["curious", "idle"]]],
}
## Showcase buildings taken offline.
const OFFLINE_KINDS: Array[String] = ["habitat", "workshop"]


static func is_blank(name: String) -> bool:
	return name in BLANK


static func known(name: String) -> bool:
	return name == "founders" or name == "dead_colony" or name == "council_pledge" or name in BLANK


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
		"showcase_suits":
			_showcase(world)
			_suits(world)
			return true
		"showcase_born_pair":
			_showcase(world)
			_born_pair(world)
			return true
		"showcase_lamp_dusk":
			_showcase(world)
			_lamp_row(world)
			return true
		"council_pledge":
			_council_pledge(world)
			return true
		"dead_colony":
			# Every being gone, stocks as they were: the HUD hides the age at pop 0.
			world.beings.clear()
			return true
		"showcase_interior_talk":
			_showcase(world)
			_interior_talk(world)
			return true
		"showcase_interior_habitat", "showcase_interior_comms", "showcase_interior_workshop":
			_showcase(world)
			_interior(world, String(INTERIORS[name][0]), INTERIORS[name][1])
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


## A being outside at (x, y) in the open ground between the showcase rows, in the given suit state. `kind` picks the suit:
## eva (state eva), mining (EVA, digging), builder (construction suit, welding).
static func _outside(world: SimWorld, role: String, kind: String, x: float, y: float, heading: float,
		earth_born: bool = true) -> Being:
	var g := world.add_being(world.buildings.list[0].id, role)
	g.earth_born = earth_born
	g.x = x
	g.y = y
	g.heading = heading
	g.air_h = 4.0
	match kind:
		"mining":
			g.state = "mining"
			g.wait_h = 1.0
		"builder":
			g.state = "work"
			g.construction_suit = true
			g.wait_h = 1.0
		"carry":
			g.state = "eva"
			g.load = 1.0
		_:
			g.state = "eva"
	return g


## Three suit kinds and a jumpsuit in a tunnel: a miner digging, a builder welding, an ice carrier, and a colonist
## halfway down a tunnel (the green room is given a corridor from the reactor).
static func _suits(world: SimWorld) -> void:
	_outside(world, "curious", "mining", 92.0, 112.0, 0.0)
	_outside(world, "builder", "builder", 118.0, 106.0, 0.0)
	_outside(world, "tender", "carry", 144.0, 112.0, 0.0)
	_tunnel_being(world)


## Corridor reactor to green room (x = 48) and a jumpsuit being at its middle, walking south.
static func _tunnel_being(world: SimWorld) -> void:
	var tile := float(SimData.buildings().tile_px)
	var reactor: Buildings.Building = world.buildings.list[0]
	var green: Buildings.Building = world.buildings.list[3]
	var p1 := Vector2(48.0, (reactor.ty + reactor.th) * tile)
	var p2 := Vector2(48.0, green.ty * tile)
	green.corridor = {"parent_id": reactor.id, "p1": p1, "p2": p2, "len": p2.y - p1.y,
			"rect": Rect2i(int(48.0 / tile) - 1, reactor.ty + reactor.th, 2, green.ty - reactor.ty - reactor.th)}
	var g := world.add_being(green.id, "social")
	g.earth_born = true
	g.state = "transit"
	g.corridor_id = green.id
	g.from_a = true
	g.transit_t = 0.5


## An Earth-born and a Mars-born EVA being of the same role, side by side.
static func _born_pair(world: SimWorld) -> void:
	_outside(world, "builder", "eva", 120.0, 108.0, 0.0, true)
	_outside(world, "builder", "eva", 134.0, 108.0, 0.0, false)


## EVA beings facing the three directions in a row, for comparing the helmet lamp at different hours.
static func _lamp_row(world: SimWorld) -> void:
	_outside(world, "builder", "eva", 100.0, 108.0, PI * 0.5)
	_outside(world, "curious", "eva", 128.0, 108.0, 0.0)
	_outside(world, "tender", "eva", 156.0, 108.0, -PI * 0.5)


## Beings inside a building: the roles and states of the INTERIORS table. The view places them (slots are cosmetic).
static func _interior(world: SimWorld, kind: String, who: Array) -> void:
	for b in world.buildings.list:
		if b.kind != kind:
			continue
		for w: Array in who:
			var g := world.add_being(b.id, String(w[0]))
			g.earth_born = true
			g.state = String(w[1])
		return


## Relationships 10.1 shot: six idle beings in the habitat; the first two (ids lowest) are made friends through the module's
## test seam so the shot can show friends talking the whole pause against strangers who mostly stand. Shot staging only; the
## game never calls debug_set_bond.
static func _interior_talk(world: SimWorld) -> void:
	for b in world.buildings.list:
		if b.kind != "habitat":
			continue
		var ids: Array[int] = []
		for role in ["social", "tender", "builder", "curious", "social", "builder"]:
			var g := world.add_being(b.id, role)
			g.earth_born = true
			g.state = "idle"
			ids.append(g.id)
		world.relationships.debug_set_bond(ids[0], ids[1], 0.9)
		world.relationships.debug_set_bond(ids[2], ids[3], 0.9)
		return


## The Council age with a made pledge and four later age entries: the HUD shows the Council word and the strip pins the
## pledge among the latest two chapters (council.md 9). Texts come from the data files; only stats are staged.
static func _council_pledge(world: SimWorld) -> void:
	var ah: Dictionary = SimData.ages()
	var cd: Dictionary = SimData.council()
	var sol_h: float = world.clock.sol_h
	var hist: Array = []
	var seq := [["landing", "landing", 1, str(ah.landing.log_start)], ["settlement", "settled", 12, str(ah.settlement.log_enter)],
			["council", "council", 40, str(cd.text.enter)], ["landing", "fell_back", 90, str(ah.landing.log_fall_back)],
			["settlement", "settled_again", 110, str(ah.settlement.log_enter_again)],
			["council", "council_again", 130, str(cd.text.enter_again)]]
	for e: Array in seq:
		hist.append({"age": e[0], "how": e[1], "cause": null, "text": e[3], "pop": world.colony.pop(), "family_mars_born": 0,
				"t": (int(e[2]) - 1) * sol_h, "sol": int(e[2]) - 1, "clock_sol": int(e[2])})
	world.stats.age_history = hist
	world.stats.age = "council"
	var ptxt := str(cd.dome.text.pledge).replace("{a}", "Lena").replace("{place}", "in the green room").replace("{why}", "because the children need a roof")
	world.stats.council.chapters = [{"kind": "pledge", "topic": "dome", "text": ptxt, "t": 69.0 * sol_h, "sol": 69, "clock_sol": 70}]
