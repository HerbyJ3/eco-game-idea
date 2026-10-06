# Task 3 step profile (SimWorld.step at scale)

Spec: `docs/specs/ages.md` section 11; plan step 10. Tool: `tools/step_profile.gd`. Measurement first; a fix is allowed only
if the five old-column balance table hashes stay byte-identical.

## Method

- `godot --headless --path station-zero --script res://tools/step_profile.gd -- --seed 42 --sol 300 [--steps 1500]`
- Builds the seed-42 world and steps it to sol 300 (step 147959: pop 164, 53 buildings, 799 footprints; 3 to 5 minutes).
  Then:
  - Pass A: 1500 plain `SimWorld.step()` calls, each wrapped in `Time.get_ticks_usec`. This is the headline step cost
    (nothing instrumented inside the step). Pop is 167 by then.
  - Pass B: the next 1500 steps through `_timed_step`, a copy of `step()` in the tool that calls the same phase methods in
    the same order with a timer around each phase (spec section 5, phase 11 split into 11a to 11e), and around every
    `Being.update` call, bucketed by what the being is about to do (sleep, idle waiting, idle that will call `decide`,
    to_door waiting, to_door that will call `_door_action`, transit, eva, work, mining). `sim/` carries no hooks.
    `--check` runs 6000 steps through both paths on two worlds and compares a state digest (they are identical).
  - Micro-benchmarks of the functions the beings call (BFS, scans, config lookups), read-only on the live world.
- Pass B is slower than pass A (instrumentation: two timer reads, a bucket call, an append per being, about 3 us per
  being). Its per-bucket medians for the cheap states (idle waiting 4 us, to_door waiting 4 us, sleep 6 us) are mostly
  that overhead. Use pass A for totals and pass B for shares and for the expensive states.
- Phase 6 also contains the work of `decide`, `go_sleep`, `next_hop`, `choose_site`, footprints and so on; those are
  not separately timed in pass B. Their costs come from the micro-benchmarks and from the `idle_decide` bucket.

## Machine caveat

This host is slower than the one used for Tasks 1 and 2 (the two view-model timing tests that passed at 1.2 to 1.6 ms
there run at about 2.4 ms here, and fail their 2.0 ms limits here). Absolute numbers below are for this host only.
Before and after were measured on the same idle host (`uptime` load 0.0 to 0.1, nothing else running), the same seed and
the same step range, so the world is the same at every step. Two before runs and two after runs agree to about 1 percent
on the plain step mean (the first before run's per-pass numbers differ more because the host was in a slower state; the
repeat is the one quoted).

## Headline (seed 42, sol 300 colony, pop 167, 53 buildings, 1500 steps)

| | median | mean | p95 | max |
| --- | --- | --- | --- | --- |
| Before (plain `step()`) | 3541 us | 3807 us | 5651 us | 13735 us |
| After fix 1 (plain `step()`) | 2253 us | 2650 us | 4344 us | 9637 us |
| Change | -36 % | -30 % | -23 % | |

(The first before run gave 3552 / 3807 / 5789 us; the first after run 2277 / 2633 / 4190 us.) The Task 2 report's
4.7 to 6.8 ms per step were measured on a faster machine with the view attached; the plain headless step here at pop 167
is 3.8 ms before. With the 8 ms budget that is about 2 steps per call before, 3 after; the real speed multiple is
steps per frame times 0.05 h per step over the frame time (see the speed readout).

## Phase table (pass B, before the fix; 1500 steps)

Step total in pass B: median 4170 us, mean 4443 us, p95 6086 us (includes about 1 ms of instrumentation, all of it in phase 6).

| Phase | median us | p95 us | mean us | share of step |
| --- | --- | --- | --- | --- |
| 1 clock advance | 2 | 4 | 2 | 0.0 % |
| 2 stocks | 56 | 104 | 64 | 1.2 % |
| 3 sol boundary + power (manage_power) | 81 | 149 | 92 | 1.7 % |
| 4 air/food warnings | 5 | 9 | 6 | 0.1 % |
| 5 ice drain + scouting | 108 | 184 | 120 | 2.2 % |
| 6 update_beings (instrumented) | 2104 | 3395 | 2306 | 51.9 % |
| 7 births | 6 | 10 | 24 | 0.4 % |
| 8 build decision | 4 | 6 | 6 | 0.1 % |
| 9 construction progress | 53 | 106 | 46 | 0.9 % |
| 10 shortage check | 6 | 10 | 7 | 0.1 % |
| 11a expire_footprints (2000 to 2200 prints) | 1196 | 2322 | 1389 | 31.3 % |
| 11b power stats | 105 | 185 | 115 | 2.1 % |
| 11c being stats | 332 | 445 | 344 | 7.7 % |
| 11d sol samples (3 sols) | 96 to 152 | | 144 | once per sol |
| 11e age hook (`Ages.on_sol`, 3 sols) | 548 | 1114 | 714 | once per sol, about 1.4 us per step amortised |

Phase 6 by being action (first before run, per call; the cheap rows are mostly instrumentation):

| Bucket | median us | p95 us | mean us | calls per step |
| --- | --- | --- | --- | --- |
| sleep | 6 | 13 | 7 | 17.5 |
| idle, waiting | 4 | 7 | 5 | 80.7 |
| idle, entering `decide` | 179 | 1307 | 365 | 0.79 |
| to_door, waiting | 4 | 8 | 5 | 22.8 |
| to_door, `_door_action` | 10 | 25 | 12 | 0.57 |
| transit | 9 | 19 | 10 | 24.5 |
| eva | 13 | 48 | 19 | 14.4 |
| work | 26 | 58 | 30 | 0.36 |
| mining | 13 | 33 | 16 | 5.4 |

`decide` is entered 0.79 times per step but costs 365 us per call on average: 0.29 ms per step, about 8 percent of the
plain step, and its p95 of 1.3 ms is what makes the step p95 high. Per-being functions that are view (fit, blits) are
excluded by construction.

## Phase table after fix 1 (pass B)

Pass B step total: median 2911 us, mean 3305 us, p95 5124 us (from 4170 / 4443 / 6086). Phase 11a is now median 6 us,
mean 7 us (0.2 %); every other phase is within noise of the table above. Phase 6 is now 76 % of the instrumented step
and is the next target.

## Top hot spots (before)

| # | Where | Share of the plain step | Cause |
| --- | --- | --- | --- |
| 1 | `Resources.expire_footprints` (phase 11a) | about 31 % (1.2 to 1.4 ms) | Every step it walks the whole footprint list (up to the cap of 2200 prints) reading `f.t` on each RefCounted object, builds a new typed array of the survivors with 2000+ `append` calls and replaces `footprints`, to drop only the few prints that faded this step (about 2 to 5). O(n) per step with n at its cap; the answer is almost always "no change". |
| 2 | `Buildings.next_hop` BFS, reached from `decide` (`go_sleep`, `_try_join_construction`, `_head_for_launch`) | about 5 to 8 % on average (the bulk of `decide`'s 365 us mean), the main contributor to the step p95 | For each node dequeued it scans the whole `list` of 53 buildings: O(V x E) = 53 x 53 = 2800 inner iterations with `b.corridor`, `b.finished()` and a dictionary `first.has` each. First-to-last costs 1.65 ms measured; last-to-first (found early) 37 us. Plus two linear `get_building` calls up front. |
| 3 | `SimWorld._sample_being_stats` (phase 11c) | about 7.7 % (330 to 390 us) | Per being, three `_stat_add` calls (and one `_stat_max`), each doing two dictionary reads and two writes by string key: about 8 dictionary operations on 167 beings every step, plus `t - float(b.sleep_started_t)` for sleepers. |
| 4 | `Being.update` fixed overhead (phase 6, all non-decide buckets) | about 25 % of the step including instrumentation, roughly 0.6 to 0.9 ms uninstrumented | Per being per step: `_cfg()` (a function call into `SimData.beings()`, a dictionary lookup) and `.energy` chain, `drain_per_h()` repeating `_cfg()` and the `match`, `is_outside()` and `_can_turn_back()` calls, `Being.is_night` (`clock.mars_hour`, `fposmod`, two dictionary reads) in sleepers. About 1 to 2 us each, times 167. |
| 5 | Power helpers: `Buildings.supply/draw/demand/count_online`, called from phases 2, 3, 5 (via `reachable_ice_count`), 11b | about 7 to 8 % together (2: 56 us, 3: 81 us, 5: 108 us, 11b: 105 us) | Each is a full scan of the 53 buildings with a dictionary read per building (`cfg.kinds[kind].draw`); `step_stocks` scans four times for `green_rooms()`; `reachable_ice_count` runs `launch_for` per field every step (scouting) and `launch_for` builds a `Vector2` door per building. |

Also measured, not hot: the age hook (`Ages.on_sol`, once per sol) costs about 0.5 to 0.9 ms on the sol boundary step
(`Ages.sample` 220 us, `family_mars_born` 120 us), about 1 to 1.5 us per step amortised, so under 0.05 percent of the
step. `beings.duplicate()` is 0.4 us; `beings.has(b)` per being is 6 us worst case (last being) and about 3 us average
(about 0.5 ms of the instrumented phase 6, in the loop of `_update_beings`; see proposal 4).

## Fixes and proposals

### Fix 1 (implemented): expire_footprints works on the faded prefix only

- Reason: prints are appended with `t = w.t`, which never decreases, so the prints that have faded
  (`t - f.t > fade_h + STEP_EPS`) are always a prefix of the list. The loop now stops at the first print that has not
  faded and `pop_front`s the prefix: cost is the number that expire (a few) instead of the number kept (2000+).
- Why it is output-identical: it keeps exactly the prints the old loop kept, in the same order, using the same
  comparison expression. `add_footprint` tracks whether the list is still in t order (`_fp_sorted`; it goes false if a
  print is ever added with an earlier t than the last, and true again when the list is empty); when false, the old full
  pass runs (and re-derives the flag). No RNG, no float evaluation order change, no dictionary iteration. The list is
  mutated in place instead of replaced; nothing in `sim/` or `view/` holds the array across steps (the old code
  replaced it every step, so no one could).
- Tests: `tests/test_footprint_expiry.gd` compares against the original algorithm at every step for 3000 sorted steps and
  400 out-of-order steps, and checks the exact-age boundary and the clear case.
- Measured: plain step mean 3807 to 2650 us (-30 %), median 3541 to 2253 us (-36 %), p95 5651 to 4344 us. Expire phase
  1389 us to 7 us. Build time to sol 300 dropped from 322 s to 176 s.
- Hashes: seeds 7 and 2026 reproduced 830c7d0c441823f5 and 2645033a417ec400 after the fix; all five at the end of the
  task (see the task report).

### Proposals not implemented (the 30 percent goal was met by fix 1)

2. next_hop with one adjacency pass. Build `adj` (id to neighbour ids) in one pass over `list` (appending in list order),
   then run the same BFS over it. Discovery order is identical because for a given node the neighbours appear in list
   order in both versions, and the early return on `to_id` is the same. Cost per call about 40 to 60 us instead of up to
   1.7 ms. Estimated saving: 150 to 250 us per step on average (4 to 6 %), and the p95 of the step drops by about 1 ms.
   Also replace the two `get_building` scans by one pass. Risk: low; needs a differential test over random corridor
   graphs against the old BFS.
3. `_sample_being_stats` accumulating into locals: `acc = stats.energy_sum`, `acc += b.energy` per being in order, write
   back to both `stats` and `stats.window` (each from its own starting value, same additions in the same order, so the
   floats are bit-identical); integer counters added once per step. Estimated saving 200 to 250 us (5 to 6 %). Risk:
   low but the float order must be preserved exactly (do not sum the energies first, then add).
4. Phase 6 fixed overhead: hoist `_cfg().energy` and `drain_per_h()` lookups (cache the `SimData.beings()` sub-dictionaries
   in `static var` fields, same objects, so a test that edits the cached JSON in place, as `balance_lib.apply_param`
   does, still takes effect), and `_update_beings`: replace `beings.has(b)` by an alive flag only if the order and the
   dead-being skip stay the same. Estimated saving 150 to 300 us (4 to 8 %). Risk: medium; `apply_param` mutates
   the cached dictionaries in place, so any caching of values (rather than of the dictionaries) would be wrong.
5. Power scans: one pass computing `green_rooms` once in `step_stocks`, and a `launch_for` that inlines `online()` and
   `door()` (same arithmetic, still `distance_to`, not squared distance). Estimated saving 100 to 150 us (3 to 4 %).
   Caching `supply`, `draw` or `launch_for` across steps was rejected (below).

### Refused: not provably identical

- Caching `next_hop`, `launch_for`, `supply/draw/demand` results between steps: building state (`built`, `offline`) is
  written directly from several places (construction progress, `set_offline`, tests), so a cache needs an invalidation
  hook in each, and a missed one changes behaviour silently.
- Comparing squared distances in `launch_for` and `nearest_online_habitat`: two different squared distances can round to
  the same `sqrt`, which changes the tie rule (lowest id wins). Not provably identical.
- Skipping `beings.duplicate()` in `_update_beings`, or iterating a different order: births and deaths during the phase,
  and update order feed the RNG stream.
- A distance or `trip_time` cache per ice field: depends on the live set of online buildings; same invalidation problem.
