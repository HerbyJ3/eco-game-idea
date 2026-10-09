# Continuation handoff

## Current owner direction

- The game and graphics redesign must stay strictly **2D**. Use illustrated angled cutaway rooms consistent with the owner's orange Mars-colony reference.
- The owner will manually render **two interior concepts for each of the six building types** in **Higgsfield Seedream 5.0 Pro**. No concept images have been generated in this session.
- Settle interior/exterior designs before detailed animation work. When designs are ready, develop movement and room activities together with the art-director and animator.
- Keep the simulation clock unchanged. Pregnancy lasts nine calendar months; growth uses human calendar birthdays.

## Completed work

- Removed the generic translucent outer rectangle from completed buildings; exterior shadows fade as roofs open.
- Documented the starting buildings' actual gameplay purposes, existing room layouts, and design discrepancies.
- Added calendar pregnancy scheduling, pending housing reservations, and baby/toddler/child/teen/adult stages. Defaults: 0–1, 1–3, 3–13, 13–18, and 18+ years. Reproduction, outside jobs, construction readiness, and Council voices share the adult boundary.
- Added a brief design-dependent animator role and handoff, without new indoor activity animations.
- Prepared and validated 12 unique interior prompts, with materially different A/B layouts per building. Both Habitat alternatives provisionally show five usable beds; the final room design and bed-capacity implementation remain open.

## Files for the next session

- [All 12 copy-ready prompts](../art/interior-concepts-seedream-5-pro.md)
- [JSON concept manifest](../art/interior-concepts-seedream-5-pro.json)
- [Six-building catalog](../art/building-catalog.md)
- [2D art-director review](../art/mars-colony-redesign.md)
- [Starting-building design brief](../art/starting-buildings.md)
- [Short animation handoff](../art/interior-animation.md)
- [Lifecycle specification](../specs/lifecycle.md)
- [Other owner ideas and outstanding design questions](owner-direction-notes.md)

Existing interior/exterior reference images are in `station-zero-handoff/assets/raw/` at repository root. Existing screenshots are in `station-zero/docs/shots/`. They show previous artwork, including old bed counts, placeholder exteriors, and the former translucent outer layer. Use them for equipment and gameplay context, while the owner's attached Mars concept guides the new style. That attachment is not stored as a repository image.

Save manual concept exports separately under `station-zero/docs/art/concepts/seedream-5-pro/`, using the manifest's target filenames. Review layout, bed counts, aisles, viewpoint, and interior/exterior compatibility before replacing active game assets.

## Outstanding work and validation

Usable beds do not yet limit simultaneous sleepers. New furniture-aware routes, seated/equipment actions, childhood artwork, caregiver behavior, signs, rebellion, and breakaway settlements remain unimplemented. Archive and Comms are visitable rooms; research and message mechanics remain open. The Dome is a Council proposal, not a buildable interior.

The last full Godot 4.5 run executed **734 tests and 42,775 checks: 640 tests passed; 94 existing mood-system tests failed** because Task 6's mood implementation is absent. There were no script errors or additional failing tests. Headless game startup passed. Visual verification of the proposed redesign remains pending; no new art has been integrated.

See the repository [README](../../README.md) for import and test commands. Keep the renderer separate from the simulation and preserve simulation RNG when implementing cosmetic animation.
