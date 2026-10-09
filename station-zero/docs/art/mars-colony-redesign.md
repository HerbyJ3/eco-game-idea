# Mars colony redesign: art-director review

Status: proposed visual direction for the owner's attached Mars-colony concept. **The owner requires a strictly 2D game.** This is a design brief, not an implemented renderer or an approved set of final assets. Building functions remain grounded in [starting-buildings.md](starting-buildings.md).

## Feasibility and recommended approach

Godot 4 can support this look. The reference combines warm illustrated terrain, an elevated oblique camera, modular pressure buildings, enclosed connecting tubes, domes, dark outlines, and long coherent shadows. Its sky, distant mesas, and foreground rocks also make it a composed illustration; a playable, expanding colony needs reusable pieces rather than one background image.

Use a **fixed oblique 2D view**, with painted sprites, layered terrain, and separately drawn shadows. Preserve pan and zoom. First establish a common camera angle and asset sheet; do not generate buildings independently at slightly different angles. Depth comes from the artwork, overlapping layers, scale, and draw order. The camera keeps the illustrated viewing angle: rotating the canvas would rotate flat pictures rather than reveal new sides of buildings. Interiors require their own matching cutaway artwork.

The existing `view/model` and `view/world` already separate presentation from the headless simulation, and provide sprite fitting, depth sorting, selection, doors, lighting, and roof cutaways. Keep that separation. The current footprints, corridors, camera mapping, and interaction geometry are axis-aligned: replacing PNGs alone will improve style but will not produce a coherent isometric settlement. A stronger oblique projection needs one shared world-to-screen mapping and its inverse for picking, with matching corridor geometry, entity positions, bounds, culling, and depth order. Simulation coordinates and gameplay rules need not change.

## Visual direction

- Rust-orange soil with ochre highlights, layered red rock, sparse dust, and restrained ground variation. Keep important paths and resource sites readable.
- Warm off-white pressure shells, charcoal machinery, panel seams, rounded modules, small illuminated windows, and a consistent dark outline weight. Use accent colors sparingly to distinguish functions.
- One lighting direction across buildings, terrain, tubes, characters, and props. Keep building shadows separate from the base art so they can fade during roof opening and respond to the existing day/night presentation. Avoid baked long shadows that conflict with runtime shadows.
- Tube connectors must join actual door/port locations and retain a consistent diameter. Roof details must make each building's purpose visible at colony zoom.
- Use transparent final sprites with clean edges, without the translucent outer rectangle or a leftover exterior silhouette when interiors open. The established magenta-source keying pipeline may remain the production route; do not put soil or sky behind individual building sprites.
- Treat the sky, horizon, mesas, and foreground cliffs as optional 2D overview framing. A painted horizon has a fixed composition and cannot simply be attached to a freely panning colony map. Prioritize reusable ground and rock layers first; reserve a composed vista for a separately designed overview or presentation scene with deliberate camera limits.

The concept's perspective is oblique and illustrative; matching its mood does not require copying every perspective distortion. Adopt a consistent projection that supports interaction and expansion.

## Starting-building interpretation

| Existing building | Proposed exterior language | Interior requirements |
| --- | --- | --- |
| Reactor | Compact reinforced industrial module, amber service lights, heat-management equipment and visible power infrastructure. | Central generator, hazard perimeter, reachable consoles, and clear safe circulation. It continues supplying power without an operator. |
| Habitat | Light residential pressure module with small windows; a dome or rounded shell is a candidate to compare in the prototype. | Bunks, shared table, kitchenette, lounge, and an unobstructed entrance. Confirm the usable bed count before final composition. |
| Workshop | Squarer service module with broad access, vents, tool-storage details, and an exterior suited to material staging. | Benches, tools, crane/staging area, reachable equipment, and a clear route to the exit. Builders prepare here and build outside. |
| Green room | Enclosed greenhouse module with a protected transparent or segmented roof and visible life-support equipment. | Hydroponic beds, plumbing/tank, grow lights, bench, and aisles wide enough for colonists. Food and oxygen output remains automatic. |

Solar arrays, communications dishes, rovers, landing pads, and landers in the reference are **visual references**, not authorization to add energy, transport, exploration, or landing systems. If used in a mockup, label them as decorative candidates. The Reactor remains the starting power source; Archive and Comms remain later expansion buildings. The final art must not suggest open-air agriculture.

## Small visual prototype

1. Produce an art sheet with the four starting exteriors, two connector directions, several rock silhouettes, a ground swatch, and a full-size colonist silhouette under the same camera and light. Compare a rounded module and dome for the Habitat before choosing its shell.
2. Compose the existing starting colony: central Reactor, Habitat right, Workshop below, Green room left, preserving the connections and identities. Show it at ordinary play zoom and closer detail zoom. No extra functional buildings are needed.
3. Resolve one Habitat interior/exterior pair in that style. Check shell, entry, usable bed count, furniture scale, and walking space before extending the interior approach to the other three rooms.
4. Integrate only after the visual review. Validate selection, door alignment, projected connectors, foreground overlap, roof closed/open/transitioning states, and night visibility in Godot. Keep the headless simulation unaffected by art and view randomness.

This prototype should settle the camera angle, architecture, palette, lighting, and cutaway approach before the full asset set is commissioned.

## Asset and integration handoff

Retain the recognized target names for approved replacements: `reactor_exterior.png`, `habitat_exterior.png`, `workshop_exterior.png`, `greenroom_exterior.png`, and their matching `_interior.png` files under `station-zero-handoff/assets/raw/`. Keep exploratory variants outside these active replacement paths until approved.

Additional needs are a reusable ground treatment, coordinated rock/decal variants, modular connector art, separate shadow information, and any foreground wall/equipment layers required for interior occlusion. Connector, ground, and foreground-layer assets need new pipeline/rendering support; current support is not established merely by supplying PNGs. Existing selection, light, construction, and door masks must be regenerated and inspected against the new art.

Record shared projection, object scale, ground-contact pivot, door/port coordinates, shell footprint, and light direction. Preserve sprite proportions instead of stretching images into mismatched footprints. Test asset resolution at intended zoom: current pipeline output widths are 384 px for buildings and 512 px for interiors, which may need review for the new detail level.

Resolve the Workshop accent before final generation: the starting-building brief describes cyan accents, while `data/art.json` currently uses pink. Revise normalized door rectangles and automatic light-mask assumptions when the art changes rather than reusing measurements from old images.

## Animation scope

Keep [interior-animation.md](interior-animation.md) provisional. After the room design is agreed, the art-director and animator can align walkable aisles, furniture obstacles, activity positions, character facing, and foreground layers. Develop movement and activities together then. No detailed animation cycles, room routes, or age-specific character assets are commissioned by this brief.

No assets or application code were changed for this review.
