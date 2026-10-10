# Task 6a: tick, boundary and view cost (plan step 8, spec emotions.md section 11)

Tool: `tools/mood_profile.gd` (timers outside sim/; plain `SimWorld.step()`, no copy of the step). One idle host, headless, Godot 4.5; numbers are machine-specific.

## Why a padded world
The shipped data never reaches pop 120 any more (peak 12 to 13 since the lifecycle rebaseline: seed 42 and 1234 end 300 sols at pop 12 and 13). The pop > 120 filters of section 11 therefore match no step of a real run (`n 0`). The budgets are measured on the padded pop-159 world with 5,278 pairs of `tools/relationships_equiv.gd` (the same one the Task 4 profile used), 300 ticks, three runs. This is pessimistic: all beings awake-or-asleep in 8 rooms, 4,918 stored pairs.

## Results (three runs of `--padded`)
| Item | Budget | Measured | Verdict |
| --- | --- | --- | --- |
| Mood tick median | 0.5 ms | 0.92, 0.96, 0.96 ms | **over** (about 1.9x) |
| Mood tick max | 1.5 ms | 2.45, 2.53, 2.90 ms (p95 1.19 to 1.74) | **over** |
| Mood sol hook (`on_sol`) | 0.05 ms | median 17 to 19 us, max 58 to 157 us | within (max once 0.157 ms) |
| `friend_pairs()` copy per boundary (estimate 0.02 to 0.05 ms) | boundary rule below | median 1.57 to 1.80 ms, max 3.7 to 5.6 ms | **estimate wrong by about 40x** |
| Relationships tick median (Task 4: 3.8 to 4.5 ms) | rises at most 0.5 ms | 3.95, 4.20, 4.15 ms | within the old range (the feed cost is not separable: it is unconditional in the tick) |
| Whole step, moods on vs off (the layer's share of mean step, budget 1 percent) | 1 percent | on 1.97 to 2.02 ms, off 1.90 to 1.92 ms; difference 75 to 94 us (3.8 to 4.6 percent) | **over**; the tick amortised over 20 steps is about 0.046 ms of it, the rest is the `friend_pairs` copy per sol and noise |
| Per-being-step terms (0.5 us per being-step, 0.1 ms summed at pop 160) | | not separable at gains 0.0: the terms are one member read and one compare against 0.0. Their upper bound is the whole-step difference above. | not judged |

Boundary rule (the slice adds at most about 1 ms to any boundary step): on a boundary step the slice adds `on_sol` (0.02 ms) plus the `friend_pairs` copy (1.6 to 1.8 ms median, up to 5.6 ms) and, on 1 boundary in 20, the mood tick (0.9 to 2.9 ms) and the feed. That is **about 1.7 to 2 ms on a typical boundary and up to about 9 ms on the worst padded one: over the 1 ms rule at this padded size.** At real sizes (pop 12 to 13) all of it is tiny: a 300-sol seed-42 run steps at 200.4 us mean with moods on and 196.1 us off (2.2 percent, noise-level at this size), and boundary steps never come near 16.7 ms.

The sim-side remedies of section 11 are the owner's call and not made in this view step: (1) move the mood tick one step after the relationships tick; (2) drop `company`; (3) compute `sd` every fifth sol; and, newly, (4) have the Council read `friend_pairs()` without the three packed-array copies (the copy, not the walk, is what the 1.6 ms is; 4,918 pairs here is above the 600 to 1,500 friend pairs the estimate assumed). Because the colony no longer reaches this size on shipped data, nothing here is a regression a player can see today.

## View cost (what step 8 adds)
- Per frame: `_update_panel` is a few comparisons; the lines are rebuilt at most 2 times a second (`refresh_hz`) and only with a colonist selected.
- `BeingPanel.lines` (the only heavy call, dominated by `friends_of`): real colony (pop 12): median 42 us, p95 73 us, max 0.58 ms. Padded pop 159, 4,918 pairs: median 4.4 ms, p95 7.1 ms, **max 16.3 ms** (estimate 0.3 to 0.6 ms per call: also wrong at this size). At 2 Hz that is a 4 ms cost on the refresh frames of a selected colonist, one frame in about 30; a refresh landing on a slow call can miss one 60 Hz frame. Not a risk at pop under 50; flagged for the day the colony grows.
- Tap hit test (`BeingHit.pick`, once per tap): 7 us at 12 records, median 77 us and max 144 us at 159.
- Outline: built once per sprite frame and cached (`selection_draw.gd`), not per frame.
- `advance()` 8 ms wall budget: the view change touches no sim step, so the sim side of `advance()` is as measured above; the panel work happens in `_process`, outside `advance()`.
