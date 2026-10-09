# Task 4 relationships tick profile (spec docs/specs/relationships.md section 13, item 9)

Target: under 1 ms median per hourly tick at pop 159 to 160. Tool: `tools/relationships_profile.gd`. Equivalence:
`tools/relationships_equiv.gd` plus the reference digests `docs/perf/task-4-equiv-reference-seed{42,7}.txt`.

## Method

- `godot --headless --path station-zero --script res://tools/relationships_profile.gd -- --ticks 200`
- World (built by `relationships_equiv.build`): blank world, 159 beings, 101 awake and spread over 8 habitats (63 to 78
  co-present pairs each, about 630 growing pairs a tick), 58 asleep in the reactor, 5,278 pairs stored (all in-room pairs
  plus seeded random pairs, bonds 0.15 to 0.85, roughly half friends, a share close). 200 ticks keep the pair count at 5,278
  (no forgetting inside the window).
- A: the shipped path, `Relationships.on_step` (`last_tick_ms`). B: a copy of `_tick` in the tool timing each part by calling
  the module's own part methods in tick order. "Grouping" is a replica of the co-presence loop timed on its own and
  subtracted from `_growth`. Reading runs once a sol, not per tick, and is not part of the tick figure.
- Host is the same slow, noisy one as the Task 3 profile; run-to-run spread is about 10 percent. Numbers are medians in ms.

## Before (commit 0a6cf6c)

| part | median ms | max ms |
| --- | --- | --- |
| info + deaths + births | 0.6 | 1.4 |
| grouping (co-presence) | 0.13 | 3.1 |
| growth loop (630 pairs) | 2.1 | 4.8 |
| decay walk (sort keys, decay, flag step, events) | 20.1 to 20.4 | 36 |
| lines / events | 0.08 | 0.25 |
| whole tick (A) | 23.4 to 24.0 | 41.7 |
| reading (once a sol) | 7.4 to 7.7 | 15 |

The decay walk is 87 percent of the tick: for each of 5,278 pairs it sorted the key array, did about 12 string-key
Dictionary reads, a config lookup chain (`float(dc.per_h)` and so on, per pair) and a function call (`_flag_step`).

## After

| part | median ms | max ms |
| --- | --- | --- |
| info + deaths + births | 0.47 | 0.96 |
| grouping (co-presence) | 0.13 | 0.41 |
| growth loop | 0.75 | 4.1 |
| decay walk | 3.25 | 7.7 |
| lines / events | 0.06 | 0.18 |
| whole tick (A) | 4.5 to 5.0 | 9.9 |
| reading (once a sol) | 2.3 | 5.8 |

Whole tick: 23.7 ms to 4.7 ms median (about 5x); max 41.7 to about 10 ms, under the 8 ms advance slice in the median.
**The 1 ms target is not reached (4.7 ms).** Result and split are reported; no behavior-changing fallback was applied.

## What changed (sim/relationships.gd; behavior identical)

- Slot mirror of `pairs`: packed arrays (key, low id, high id, bond, flag bits) plus the pair dictionary per slot. The decay
  pass walks the packed arrays only; every module write to a bond or flag goes through `_set_bond`, `_flag_step`,
  `_get_or_make` and `_remove_pair`, which keep the mirror in step (it is rebuilt if the pair count ever disagrees).
- The decay arithmetic is the same expression in the same order (so bonds are bit-identical); config values are hoisted
  out of the loop; the per-tick trait reads are packed arrays indexed by id instead of a Dictionary of arrays.
- No per-tick key sort of every pair. Pairs whose flags can change are found by a cheap bond-and-flag test in the pass and
  only those (plus the pairs that grew) are sorted and processed in ascending key order, which is what the counters and
  event order depend on. Forgotten pairs are removed after the pass.
- Growth: one function for rooms and crews with the affinity inlined, packed trait reads, no per-pair `[place, building]`
  array (a grown pair stores a group index).
- Reading: union-find over packed arrays, walking the flag mirror (7.5 to 2.3 ms; once a sol).

## Where the remaining 4.7 ms is

Per-pair cost in the GDScript interpreter on this host (micro-benchmark, 5,278 pairs): a Dictionary string-key read about
0.24 us, a write about 0.18 us, a packed-array element read or write about 0.05 us.

- Decay pass 3.25 ms: about 1.2 ms is the one `pair.bond = b` Dictionary write per pair, which cannot be dropped while
  `pairs[key].bond` is what tests and the spec read; the other 2.0 ms is about 12 packed reads or writes and the arithmetic
  per pair (0.4 us a pair).
- Growth 0.75 ms (630 pairs, 1.2 us a pair), info/deaths/births 0.47 ms (159 beings: trait Dictionary reads), grouping
  0.13 ms, events 0.06 ms.
- To go below 1 ms the decay of 5,278 pairs a tick has to stop being done per pair per tick. Exact options all change
  something: lazy closed-form decay changes bond bits (and could move a flag drop by a tick); slicing the decay is the
  spec's fallback (`decay.slices`) and needs a spec revision; `tick_h` 2.0 halves everything and also needs one. Not done.
  A cheaper non-behavioral step would be storing bonds only in the packed mirror and exposing `bond` through an accessor,
  which removes the 1.2 ms dict write (to about 3.5 ms total) but changes the `pairs[key].bond` test contract.

## Equivalence

`tools/relationships_equiv.gd --seed S --steps 60000 --every 5000` runs the real world to sol 121 and prints a digest every
5,000 steps (every pair: key, bond to 17 decimals, five flags; counters; queues; `stats.relationships`; the whole log), then
600 ticks of the padded world. Old module (0a6cf6c) and new module give byte-identical output on seeds 42 and 7
(`task-4-equiv-reference-seed{42,7}.txt` hold the old output; the new run is `cmp`-equal). Also unchanged: all 61 tests of
`tests/test_relationships.gd`, and `tests/relationships_hash_proof.gd` MATCH on all five seeds (42, 7, 99, 1234, 2026) for
both checks.
