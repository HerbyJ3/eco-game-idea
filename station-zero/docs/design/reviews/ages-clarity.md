# Ages spec review: designer-clarity (Karoliina Korppoo lens), 2026-10-05

Good: announce-only, private window, dwell and hysteresis; the log is the right channel (the only text the player already reads: view/main.gd _log_text, last 8 lines); ice judged against current use is legible in-world.

MUST-FIX
1. Age lines are cause-blind and get lost. A fall-back after about 17 failing sols with "The easy days are over" looks like a bug. LOG_LINES is 8 and routine lines come about 1 per sol, so the age line is evicted from view in roughly 8 sols, instantly at 100x or 1000x. Fix A: a private "dominant failing clause" for the window (most failures, fixed tie order ice, food, oxygen, power, death), per-cause text keys appended to the age line (no digits), e.g. ice: "The ice fields are failing them. Water is on everyone's mind again."; oxygen: "The air has grown thin. Every breath is counted again."; food: "The larders are bare. Meals are rationed and tempers are short."; power: "The lights keep failing. The reactors cannot carry the colony."; death: "Too many have been lost to want. The colony is mourning and fearful." Entry also names a positive cause. The pure decide stays untouched; the cause derives from stored clause names. Test: no digit and no % in every cause line. Fix B: pin age lines (a short "chapters" strip of the last 3 age lines never evicted by routine lines).
2. HUD speed labels are dishonest at scale. With the budget the sim runs 3x-6x at 164 beings but the HUD says "1000x". Show achieved speed beside the label, e.g. "Speed: 1000x (running about 5x)", from sim hours per real second, plus one plain line when throttled ("colony too large for this speed"). Dropped hours must never appear as lost sol time; the clock simply advances slower.
3. Empty colony: a dead colony reading "Landing" forever over an empty crater is misleading. Recommend one terminal log line once (not an age change, kind colony_ended: "The colony has fallen silent.") and the HUD age text reads nothing while pop is 0.

SHOULD-FIX
4. At 1000x one real second can hold a fall-back, a settle-again and four routine lines; keep the chapters strip; a view-only flash of the age line; optionally an off-by-default view setting that drops to a lower speed on an age change (owner call; the game never auto-pauses). Long-absence summary is a later task; keep age_history complete.
5. The private window is too opaque for a curious player: add one qualitative word to an existing HUD resource line when that stock is the cause of a bad sample ("Ice 5.9 (target 120) +0.00 /h  running low"), computed in view from stocks with the same thresholds as sample.* (o2_min_fraction, ice_min_sols); never print counts of failing sols; the view never reads last_sample.
6. Settle wording must not read as a reward or congratulation; fall-back must not blame the player. "easy days are over" is false on seeds that fell back; prefer "back to simply getting by".
7. The landing line scrolls away by sol 3 at 10x; the chapters strip keeps the first age visible as context.
8. HUD age line placement: put it in the clock line ("Jezero Crater | Year 1, Sol 21 | Landing") so a screenshot shows it.
9. At 160 colonists a fall-back caused by ice reads the same as at 12; the cause text is the only scale-neutral explanation; no per-being or per-building detail in the age line.

IDEAS
10. Pair the age with the season word already in the HUD ("northern spring | Landing") so players read the third word as the colony's mood.
11. Debug-only: expose the window as a read-only dev overlay behind the existing M flag, never in the player HUD.
12. Add a 3-frame shot strip in docs/shots/task-3 (just before fall-back, the log line, just after).
Citation note: Cities: Skylines advisor/notification messages naming the failing service, recalled in general terms, not quoted.
