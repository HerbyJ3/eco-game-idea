# Ages spec review: designer-feel (Eric Barone lens), 2026-10-05

Good: announce-only plus private window means the age arrives like a season change; four distinct lines in both directions ("settled again" differing from "settled" is lovely); regression as drama fits ice-as-pressure; the no-digit/no-% log test is the right guard.

MUST-FIX
1. The fall-back line is too flat and slightly scolding ("The easy days are over..."). It declares game state, not what people feel, and the player has done nothing wrong. Gentle, not grim. Candidates: (a) "The water runs thin and the colony tightens its belt. Everyone is back to counting." (b) "Hard days have come back to Jezero. The colony pulls close and gets on with it." (c) "The routines slip. People are watching the ice again, and each other." Recommend (b), or (a) to name ice. Never "back to Landing", "regressed", "failed".
2. Pop 0: freeze the age, log nothing new. A fall-back line in an empty colony would be a joke at the corpse's expense; existing death events carry that moment.
3. Landing and settled lines say "founders" in a way that breaks once Mars-born exist; word them around "the colony" and "people".

CANDIDATES (no numbers, colony voice; pick one per event, never rotate randomly)
Landing: "The founders have landed at Jezero. For now, air and water and warmth are all there is to think about." / "Landfall at Jezero, at dawn. Everything depends on the next breath."
Settled: "Nobody is only surviving now. There are families here, and meals shared, and a place to come home to." / "The colony has stopped holding its breath. Jezero is starting to feel like somewhere people live." / "Children born under Martian skies are growing up here. The colony has settled."
Settled again: "The colony has found its footing again. Life has a rhythm once more." / "The hard stretch has passed. Meals, work and sleep keep their old order." / "Jezero breathes easier. People are settling back into their days."

SHOULD-FIX
4. A small human touch with no new state: the season at the change from the sim's Ls (4 short season phrases in ages.json, highest value per line); optionally a named colonist (lowest-id living Mars-born) on the settled line only, if the HUD lets the player find them; name no one on bad news.
5. Pacing: at 1x a sol is about 25 s real; first 100 sols read as landing, about 43 quiet sols, Settlement near sol 44-55, then (dry seeds) silence until the ice crisis near 150-180, then one fall-back line: about three lines in 300 sols, a readable story. The log panel must hold the line at 100x (view note).
6. 40-sol window and 20-sol dwell feel right, but the dwell is nearly invisible work (the dead band already gives a 13-sol minimum round trip).

SCOPE: smallest Task 3 that delivers the feeling: per-sol sample, 40-sol window, entry rule, one exit rule, four log lines, age name on the HUD, stats.age. Cut order if time runs out: (1) the advance wall-time budget and profiling (not an ages feature); (2) the probe's 243-combination candidate grid (keep raw per-sol recording and the self-replay check); (3) test 14's five synthetic families (keep square waves and data sanity); (4) min dwell as a separate mechanism; (5) the exit.recent_sols clause; (6) age_history (derivable from the log; keep sols_in_age and age_changes); keep the ice_min_sols clause.
Resist any banner or pop-up; log only.
Citation note: Stardew references are to shipped-game structure (seasons, calendar), not quotes.
