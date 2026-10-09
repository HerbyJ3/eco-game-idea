# Building catalog for the owner's 2D redesign

There are six implemented building types. Four are present at landing; the colony can construct more of these and the two expansion types. Facts come from `data/buildings.json`, `data/beings.json`, `sim/world.gd`, and `sim/colony.gd`.

The activity examples below are suggestions for describing the new interiors. Existing indoor animation supports walking, idle, talking, and sleeping; dedicated console, seated, cooking, gardening, reading, and bench-work actions still need design and assets. Keep movement and activities dependent on the approved room layout.

| Building | When present | Current gameplay purpose | Interior and Sim activity ideas to describe |
| --- | --- | --- | --- |
| Reactor | Starting colony, central building | Automatically supplies power. An operator is not required. | Generator, safe service aisles, monitoring consoles; a Sim checks readings or inspects equipment. |
| Habitat | Starting colony, right of Reactor | Preferred sleeping destination when powered; conception/birth home. Pregnancy now lasts nine calendar months. | Beds, seats, shared table, kitchenette, family space; sleeping, sitting, conversation, meal preparation. Specify actual usable bed count. |
| Workshop | Starting colony, below Reactor | An adult builder inside a powered Workshop enables construction readiness. Construction happens outdoors. It does not manufacture goods automatically. | Tool racks, benches, equipment and material staging; preparing tools, inspecting components, leaving for a construction site. |
| Green room | Starting colony, left of Reactor | Automatically produces food and oxygen while powered. A gardener is not required. | Enclosed growing beds, grow lights, tanks, pipes and accessible aisles; checking crops, tending plants, inspecting environmental controls. |
| Archive | Later construction | A room colonists can visit; curiosity influences visits. No research, education, or knowledge-production system is implemented. | Owner to define its identity: records, books, terminals or displays; possible reading, browsing records, studying or discussion. |
| Comms | Later construction | A room colonists can visit; curiosity influences visits. No operator-dependent communications or message system is implemented. | Owner to define terminals, screens, radio equipment and seating; possible checking transmissions, using a console or coordinating people. |

Seven founders start in the colony: four in Habitat, two in Reactor, one in Workshop. Their starting location is not a permanent staffing assignment. More than one copy of each type can exist.

## Other structures and locations

- **Connecting tunnels:** enclosed travel links between buildings, not a separate building type.
- **Construction sites:** unfinished versions of the six types where adult builders perform outside work; not an extra finished room.
- **Ice fields and regolith deposits:** outdoor mining locations, not interior buildings.
- **Dome:** a Council proposal and pledge; not currently a constructible building with an interior.
- **Solar arrays, landing pads, landers and rovers:** present in the supplied concept, but not implemented game buildings or systems.

## Description format

For each room, supply its main purpose; exterior shape and identity; furniture/equipment and where it belongs; the Sim's intended activities; and usable seats, beds or workstations. Indicate what the Sim approaches, how it uses it, and where it leaves space to walk. State whether an action is visual ambience or should affect gameplay.

The owner requires strictly 2D artwork. See [mars-colony-redesign.md](mars-colony-redesign.md) for the proposed camera/style direction, [starting-buildings.md](starting-buildings.md) for existing starting-room observations, and [interior-animation.md](interior-animation.md) for the short design-dependent handoff.
