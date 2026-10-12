# Review of influence-powers.md rev 1: designer-clarity (Korppoo lens)

Date: 2026-10-09. Saved in substance; wording condensed.

**C1 (blocking). Nothing warns that water is trending to trouble, and nothing links the warning to Guide.** Add a HUD line "Water: steady / falling / low / dry (N sols)" computed from stock against consumption. Log a line when ice first drops below 50% of target. Mark the button: "[F5] Guide ready - ice low". Same for Fortune when a building is dark.

**C2 (blocking). Acceptance needs a warning criterion.** Criterion 4: a warning appears at least N sols before the first thirst death on each unattended seed. Add a slow 2-sol bot. Report power-use counts (near-constant recasting means the powers are a chore).

**C3 (blocking). Guide's implicit target is hidden, and a stale selection can redirect it to a pit.** Name the target in the note and the log (which field, how much ice is left) and highlight it. Simplest fix: Guide always picks the richest live ice field, and a selection only chooses among ice fields.

**C4. Feedback.** At expiry log the effect ("Guidance ended: 5 trips, 38 hauled"). Inspire and Grace get outcome lines. Show active powers with time remaining.

**C5.** Split `bad_target` into specific reasons. Log failures.

**C6.** Fortune reports the buildings it brought back online.

**Advisory.** Move the Influence line near the colony/water panel. Say "2.0 sols until ready". Consider auto-pause on the first "low" warning.
