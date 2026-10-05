# Ages spec review: designer-emergence (Will Wright lens), 2026-10-05

Good: announce-only, private window, no digits in log text; the 0.9 entry / 0.6 exit band with dwell is sound; falling back is drama not failure; ice read against current use; nobody reads ages in Task 3, so no feedback loop yet.

MUST-FIX
1. The sample is colony-wide stock-and-flow, colonists are absent. Oxygen, food and power pass on every sample of every seed (spec 4.2 says so), so the sample is effectively "ice >= 2 sols"; Settlement is the ice gauge plus "5 Mars-born alive": a hidden threshold script posing as emergence. Add colonist-derived clauses to the same ok sample (the 36-of-40 / last-3 / 5 Mars-born / dwell rule untouched), as shares of the living population: (a) no one in distress (nobody below an energy floor while awake, nobody stranded or exhausted outside, max share about 0.1); (b) a rested majority (share who slept this sol >= X); (c) shared life (at least one conversation or habitat gathering this sol, from a private per-sol snapshot).
2. Mars-born >= 5 is a headcount, not a family: five orphans in different habitats would trip it. Prefer "at least N Mars-born beings alive whose parent or habitat-mate is also alive", or "at least 2 distinct habitats each hold a Mars-born being". If births do not record parents, record parent_ids now.
3. Falling back is only drama if the player can see why and can act. The log must at least say which pressure it was (by kind, not number).

SHOULD-FIX
4. Keep the fall-back wording gentle by default; the risk is a line that sounds final when no god power answers ice.
5. Landing is sticky: enter at 36/40, leave at 24/40, so a colony that ever has an ice crisis rarely reaches Council (Task 5). Task 5 should not gate on the Settlement entry count; record both ages and let Task 5 choose.
6. No god power touches an ice clause (Good fortune cannot raise ice, Grace raises births which raises ice use, Inspire only points at a building). Feed the sample with something the god can nudge: the colonist clauses in item 1 give the god an indirect lever (rested majority, shared life).
7. The instant ice read at the boundary can miss a dip; record min ice over the sol as a read-only stat from the start.
8. Pop 0 frozen is fine, but log a separate non-age line from the existing death log ("The last of them is gone"); do not make it an age.

IDEAS (record the data now)
- age_history entries and age_began lines carry private extra fields: cause (failing clause names), pop, mars_born, births_in_age, deaths_in_age by cause, ids of Mars-born alive.
- Record parent_ids and birth_age on each being at birth (cannot be reconstructed later).
- Later: dwell read from the colony's steady-trait mean.

Feedback loops if ages later change behaviour: (1) Settlement unlocks growth, pop rises, ice clause fails, fall-back withdraws the bonus: a flapping engine; read a lagged copy of the age and keep growth effects out of it. (2) Council support must survive a fall-back (agreements are history). (3) Keep the age out of the sample's inputs, always.
Hidden gates to name honestly as "floors": the 5 Mars-born clause; no entry before sol 44 by construction.
Citation note: reviewer unsure of a specific published statement for the cause-visible point.
