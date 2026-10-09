# Continuation handoff

## Current owner direction

- The game and graphics redesign must stay strictly **2D**. Use illustrated angled cutaway rooms consistent with the owner's orange Mars-colony reference.
- **Twelve interior concepts are rendered and committed** from Higgsfield Seedream 5.0 Pro, two for each of the six building types. See the [render record](../art/concepts/seedream-5-pro/README.md) and [contact sheet](../art/concepts/seedream-5-pro/contact_sheet.jpg). These first renders remain unreviewed; no new artwork is integrated into the game.
- Settle interior/exterior designs before detailed animation work. When designs are ready, develop movement and room activities together with the art-director and animator.
- Keep the simulation clock unchanged. Pregnancy lasts nine calendar months; growth uses human calendar birthdays.

## Completed work

- Removed the generic translucent outer rectangle from completed buildings; exterior shadows fade as roofs open.
- Documented the starting buildings' actual gameplay purposes, existing room layouts, and design discrepancies.
- Added calendar pregnancy scheduling, pending housing reservations, and baby/toddler/child/teen/adult stages. Defaults: 0–1, 1–3, 3–13, 13–18, and 18+ years. Reproduction, outside jobs, construction readiness, and Council voices share the adult boundary.
- Added a brief design-dependent animator role and handoff, without new indoor activity animations.
- Prepared and validated 12 unique interior prompts, with materially different A/B layouts per building. Both Habitat alternatives provisionally show five usable beds; the final room design and bed-capacity implementation remain open.
- Resumed from merge `801bec5` and completed the unchanged 1,500-sol Standard baseline: five balance, five relationships, and five Council runs. All colonies become extinct from thirst by sol 704. Four enter Settlement by sol 328, so the owner's Settlement adjustment trigger is not met. [Report and measurements](../balance/lifecycle-standard-baseline.md).

## Files for the next session

- [All 12 copy-ready prompts](../art/interior-concepts-seedream-5-pro.md)
- [Rendered concepts, references, and contact sheet](../art/concepts/seedream-5-pro/README.md)
- [JSON concept manifest](../art/interior-concepts-seedream-5-pro.json)
- [Six-building catalog](../art/building-catalog.md)
- [2D art-director review](../art/mars-colony-redesign.md)
- [Starting-building design brief](../art/starting-buildings.md)
- [Short animation handoff](../art/interior-animation.md)
- [Lifecycle specification](../specs/lifecycle.md)
- [Other owner ideas and outstanding design questions](owner-direction-notes.md)

Existing interior/exterior reference images are in `station-zero-handoff/assets/raw/` at repository root. Existing screenshots are in `station-zero/docs/shots/`. They show previous artwork, including old bed counts, placeholder exteriors, and the former translucent outer layer. Use them for equipment and gameplay context, while the owner's attached Mars concept guides the new style. That attachment is not stored as a repository image.

The existing concept exports and current-room reference screenshots are under `station-zero/docs/art/concepts/seedream-5-pro/`. Review layout, bed counts, aisles, viewpoint, and interior/exterior compatibility before replacing active game assets. The render record notes the camera is steeper than requested and furniture clearances/counts remain unverified.

## Outstanding work and validation

The authoritative task queue is [HANDOFF.md](../../../station-zero-handoff/HANDOFF.md), section 8. Next is an ice-supply and founder-job investigation, plus seed 2026's power outage, before emotions calibration. Keep mechanics and thresholds unchanged until the lead game designer/owner chooses a response. Generational verification and final Standard run-twice checks remain pending. `wip/6a-dormant` is still unfinished and unverified. Current continuation work is on `codex/lifecycle-standard-baseline`; GitHub API access blocks its PR workflow until the saved environment network draft is published.

Usable beds do not yet limit simultaneous sleepers. New furniture-aware routes, seated/equipment actions, childhood artwork, caregiver behavior, signs, rebellion, and breakaway settlements remain unimplemented. Archive and Comms are visitable rooms; research and message mechanics remain open. The Dome is a Council proposal, not a buildable interior.

The previously recorded full Godot 4.5 run executed **734 tests and 42,775 checks: 640 tests passed; 94 existing mood-system tests failed** because Task 6's mood implementation is absent. This is not a new full-suite result. Current import and lifecycle horizon checks passed (2 tests, 2 checks), and all fifteen Standard jobs completed without script errors. All five balance runs exit 1 due to the adult-floor failure; probe exits 0 indicate completion. Visual review of the proposed redesign remains pending; no new art has been integrated.

See the repository [README](../../README.md) for import and test commands. Keep the renderer separate from the simulation and preserve simulation RNG when implementing cosmetic animation.
