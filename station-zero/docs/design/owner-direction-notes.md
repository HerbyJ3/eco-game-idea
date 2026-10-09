# Owner direction: city, influence, pacing, and room capacity

Source: the owner's supplied `eco fixes and ideas_transcript.share.txt`, together with the request to keep animation planning dependent on final building designs. These notes record desired outcomes and ideas to consider. They do not define approved mechanics, balance numbers, or an implementation commitment for every proposal.

Confirmed direction: keep the game clock unchanged. Pregnancy lasts nine calendar months, and colonists grow by human calendar years. The implemented schedule is baby 0–1, toddler 1–3, child 3–13, teen 13–18, adult 18+. See [lifecycle.md](../specs/lifecycle.md). The graphics redesign must stay strictly 2D, following the owner's attached Mars-colony concept.

## Desired outcomes

| Concern | Owner direction | Current implementation / gap |
| --- | --- | --- |
| Player involvement | The player should influence colonists, and involvement should matter to a successful city. | The world largely develops autonomously. `sim/powers.gd` has a power-supply multiplier hook; there is no complete player-facing sign/response loop. Design the player's recurring contribution and feedback before adding systems. |
| Organic population growth | Keep the clock unchanged; give pregnancies a duration and colonists baby, toddler, teen, and adult stages. | Implemented: nine-month pregnancy scheduler, calendar birthdays, stage counts, and shared adult eligibility for reproduction, outside work, construction readiness, and Council voices. Character art and childhood activities remain design-dependent. |
| Sleeping capacity | A building's supported sleepers must match its usable beds: five beds means at most five simultaneous sleepers there. | The current birth-capacity formula is separate from bed occupancy. Sleep routing chooses a Habitat without reserving a free bed, and the view has floor/shared-slot fallbacks. The requested bed limit needs simulation support, not just a visual cap. |
| Placement | Colonists should sit/sleep at valid locations inside the actual room. | Generic floor slots and straight-line travel do not account for furniture. Map placement against the final room art; sitting requires a matching pose and anchor. |
| City art direction | Create a city-scale concept/reference for the lead graphic artist to evaluate. | The art-director reviewed the supplied concept and proposed a fixed angled 2D approach in [mars-colony-redesign.md](../art/mars-colony-redesign.md). New graphics and renderer changes are not implemented yet. |

## Gameplay ideas to review

The owner suggested colonists expecting a sign after doing what they believe is required. If no sign arrives within an appropriate period, some could become rebellious or pursue their own direction. A group might leave and establish a separate settlement, with a frontier / Wild West / Mad Max-like feeling.

Treat this as a proposed storyline/system, not a fixed rule that every unattended colonist rebels. The lead game-designer needs to resolve what creates an expectation, what the player can perceive and do, how colonists interpret a response, and what different choices lead to. The existing personality, relationship, and Council systems provide context to investigate; they do not already implement religious expectations, rebellion, or a second city.

A breakaway settlement would also need decisions about migration, shared/separate resources, spatial representation, and the player's relationship with it. Its visual direction should be reviewed by the art-director before commissioning buildings or animation.

## Design questions left open

- Which childhood activities and caregiver behaviors should be added after the room and character designs settle? Room dwell/animation timing remains a separate design decision.
- How does the player influence events while colonists retain agency? Is involvement essential throughout play or at particular moments?
- What signals tell the player that someone expects a response, and what constitutes a response? Any deadlines, effects, or costs need a separate specification.
- When all beds are occupied, what should a tired colonist do? Determine overflow behavior and reservation rules before enforcing the new limit. Floor sleeping must not silently bypass the agreed bed capacity.
- Which buildings contain beds, how many usable beds does each approved interior show, and how should housing capacity affect population growth?
- Is a new settlement a later expansion goal, and how should its frontier style relate to the main city's visual identity?

## Coordination and scope

The lead game-designer owns gameplay/pacing/capacity specifications; the art-director owns city and room design. The animator works with the art-director once those designs are settled, developing movement and activities together as requested. Keep that animation handoff brief until then.

Pregnancy is a timed state before a birth, not a life stage added to population. After birth, elapsed simulation time determines the baby → toddler → child → teen → adult sequence; founders remain adults. Keep those timers configurable, tied to simulation time so pause/speed controls work naturally. Coordinate childhood behavior, reproduction, and the Council's age gate around the same definition; visual changes wait for the settled character/building designs.

The existing rendering fix and starting-building descriptions remain valid. The lifecycle rules above are implemented with the clock unchanged. Bed occupancy, signs, rebellion, migration, new city artwork, and indoor animation cycles remain outstanding design or implementation work.
