# Starting buildings: purpose and visual design brief

This brief describes the four buildings in the shipped starting colony. Gameplay facts come from `data/buildings.json`, `data/colony.json`, `data/beings.json`, `sim/colony.gd`, and `sim/world.gd`. The visual requirements below guide future artwork; they do not add gameplay systems. The [indoor animation handoff](interior-animation.md) is provisional until the relevant building design is settled. The current-layout observations below must be reviewed again if artwork changes.

## Colony at landing

The central Reactor connects to the Habitat on the right, Workshop below, and Green room on the left. Seven founders start here: four in the Habitat, two in the Reactor, and one in the Workshop. Nobody starts in the Green room. An empty Green room still produces resources. Colonists subsequently move between buildings.

| Building | Description for players | Implemented purpose | Starting power |
| --- | --- | --- | --- |
| Reactor | The colony's power plant. It supplies electricity to the connected settlement. | Each finished Reactor supplies 14 power units. It does not produce oxygen or food, and staffing does not control output. Reactors cannot be shut down by the overload system. | Supplies 14 |
| Habitat | A shared home where colonists sleep, spend time together, and raise the next generation. | Online Habitats are preferred sleeping destinations and locations for births. Birth eligibility uses five capacity places per online Habitat plus a colony-wide bonus of two; this is a birth gate, not a limit on people entering the room. | Uses 3 |
| Workshop | A construction preparation room with tools, equipment, and room to stage building materials. | A builder inside an online Workshop makes the colony eligible to start a construction site, subject to its other checks. Builders perform construction outside at that site. The Workshop does not automatically create regolith or manufactured goods. | Uses 4 |
| Green room | The colony's food and oxygen garden. Its powered growing systems help keep everyone alive. | Each online Green room produces 1.4 oxygen and 1.0 food per simulation hour and adds 150 oxygen and 120 food storage capacity. Production is automatic; there is no gardener staffing requirement. | Uses 4 |

Starting demand is 11 of the Reactor's 14 power units. With seven founders, net production is +1.05 oxygen and +0.755 food per simulation hour before storage caps. Ice is consumed separately; the Green room does not currently process ice into a modeled water supply.

## Reactor

**Exterior:** An industrial pressure shell with visible power infrastructure, reinforced access, and a distinct amber accent. Roof equipment and cable connections should suggest a power plant. Preserve the exterior's bottom access point and align the cutaway room with it.

**Interior:** The existing image has a large central glowing generator, a hazard boundary, cooling lines, two side consoles, and an entry at the bottom. Keep this spatial language. The core and its hazard area are machinery, not floor space. Provide a continuous safe route from the entrance to the side consoles and service panels. A seated operator's hands, feet, and chair must align with the console rather than the generator.

**Activity design:** Checking a console, watching readings, or inspecting a wall panel. These are cosmetic activities; don't imply that the plant stops generating when the operator leaves. Don't place casual seating, beds, or indoor welding on the core.

## Habitat

**Exterior:** A residential pressure module with a softer cyan identity, small windows, and a clear entry. Match the interior's outline, wall thickness, and entry; roof equipment should suit a living module.

**Interior:** The current room has three visible beds at the upper left, lockers, a kitchenette at the upper right, a four-seat table on the right, and a lounge at the lower left. Keep an unobstructed route from the bottom doorway to these areas. Meals belong at the table; conversation belongs at seats or the lounge; sleep poses belong on mattresses.

**Capacity discrepancy to resolve in the next art revision:** The image and slot map provide three bunks, while four founders start here and the birth gate counts five places per Habitat. The owner's new requirement is that usable beds limit simultaneous sleepers: five beds means no more than five sleepers in that building. The bed count for the revised room is still a design choice. Current sleep routing and floor fallbacks do not enforce this limit; matching the art requires a separate simulation change. See the [owner direction notes](../design/owner-direction-notes.md).

**Activity design:** Lie down in a bunk, sit at the table, chat in the lounge, or briefly use the kitchenette. Eating and cooking animations are proposed ambience; current food consumption is colony-wide, without individual meal jobs. Don't animate standing sprites across furniture to simulate sitting.

## Workshop

**Exterior:** A practical fabrication/service module with a broad roll-up access door, cyan accents, and recognizable industrial equipment. The large door must match the interior's entry and staging area.

**Interior:** The current art has tool benches across the top and left, a work desk at the lower left, a central hazard-marked staging area beneath a crane, and equipment/storage along the right. Separate walkable aisles from benches and machinery. Keep the entrance-to-staging route clear. Hazard markings alone do not make the empty staging floor an impassable machine; the crane supports and equipment footprints need explicit collision boundaries.

**Activity design:** Check a tool rack, prepare equipment at a bench, inspect a component, and leave for an outdoor construction site. Existing construction-suit weld frames are for outdoor site work; an indoor jumpsuit bench action needs its own pose. Don't portray the Workshop as a mineral mine or claim that a fabrication job exists in the simulation.

## Green room

**Exterior:** A greenhouse/life-support module, distinguishable by its green accent, growing-system structure, and environmental equipment. Match the enclosed hydroponic room rather than implying open-air agriculture on Mars.

**Interior:** The current art has dense growing beds, overhead grow lights, a tank and plumbing at the upper left, and a potting/packing bench at the lower left. Its aisles are narrow. Reserve navigation paths between the entry, bench, and accessible bed edges; plant beds, the tank, and workbench are obstacles. Characters interact from aisle positions, not from inside the plants.

**Activity design:** Inspect a crop, check the tank, or tend plants at an accessible edge. Tending and harvesting are proposed visual actions. Food and oxygen continue to be generated by the powered building without a colonist stationed here.

## Shared art requirements

- Pair each exterior with its own interior, using a consistent scale, shell, entry, and accent family. Test the pair in the actual game at closed, transitioning, and fully open roof states.
- Preserve transparent PNG backgrounds and clean silhouettes. Completed buildings now draw without the generic translucent footprint rectangle, and exterior shadows fade with the roof. Don't bake a replacement rectangle or an exterior ghost into the artwork.
- Include unobstructed walking aisles and clear activity locations when designing each interior. Define anchors, facing, and foreground layers after the room design is settled, using the brief animation handoff.
- Reserve sleep for bunks, social sitting for seats, and equipment actions for reachable service points. A colonist's simulation role expresses tendencies, not a fixed employee assignment.
- Archive and Comms are later expansion buildings, outside this starting-building brief.

## Review checklist

Check that the room's main function is readable without its label; the interior and exterior entry match; a full-size colonist can navigate every intended aisle; equipment and furniture are not walkable; and each proposed action has a reachable anchor. Agree on the actual usable bed count and keep it consistent with the future sleeping-capacity rules.
