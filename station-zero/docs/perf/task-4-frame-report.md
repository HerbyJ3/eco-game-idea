# Task 4 view-step frame measurement (spec docs/specs/relationships.md section 13, triggers 3a, 3b, 3c)

Tool: `tools/view_frame_report.gd` (rendering run, never `--headless`):

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
  --script res://tools/view_frame_report.gd -- [--seed 42] [--pop 120] [--frames 600] [--warmup 60]
```

## Method

- Seed 42, shipped data, module on, both pulls 0.0. The sim runs headless-fast to the first sol with pop above 120 (sol 207,
  pop 121, 2,173 stored pairs); then `res://view/main.tscn` is attached, one habitat roof is opened (peek), zoom 2.
- Each condition holds 600 frames (spec: at least 300), after a 60-frame warmup. The game's own path is used: the Sim autoload
  host's `_process` is switched off and the tool makes the identical call (`world.advance(delta x speed x hours_per_second)`),
  timed on its own, so the sim's share of the frame is separable from rendering.
- A frame "contains a tick step" when `relationships.ticks` moved during it. Per frame: wall ms between consecutive
  `frame_post_draw`, and the `advance()` ms.
- Conditions: (a) camera still, 1x; (b) camera panning (colony to roof) and zooming (0.6 to 6) continuously, 1x;
  (c) 1000x (the fastest preset), steady; (d) catch-up. **The game has no separate long-absence catch-up path** (ages.md defers
  it), so (d) is the fastest speed right after an unpause (paused 60 frames, then 1000x), as the spec allows.
- Host: 4 cpus, Mesa llvmpipe (a CPU renderer), Godot 4.5. **Every frame, tick or not, costs about 60 to 80 ms of wall time
  here because 1280x720 is rendered in software** (about 15 fps; the earlier perf report calls llvmpipe pessimistic). The
  16.7 ms and 33 ms thresholds therefore cannot be met by any frame on this host and cannot separate tick frames from plain
  ones by wall time. The `advance()` columns are the renderer-independent reading and are what a faster machine adds to a
  frame.

## Results

Frame wall ms (process + software render), split by "frame contains a tick step":

| condition | frames (tick / plain) | tick frames p95 / max | plain frames p95 / max | steps per frame (tick / plain) | tick median / max ms | stored pairs median (min-max) | pop | sim hours dropped by the budget |
|---|---|---|---|---|---|---|---|---|
| a. camera still, 1x | 600 (31 / 569) | 63.8 / 73.5 | 59.1 / 69.1 | 1.1 / 1.0 | 4.16 / 6.83 | 2289 (2164-2331) | 122 | 0.0 |
| b. camera panning and zooming, 1x | 600 (34 / 566) | 81.2 / 84.8 | 75.6 / 88.8 | 1.2 / 1.2 | 4.21 / 6.30 | 2372 (2317-2428) | 122 | 0.0 |
| c. 1000x steady | 600 (143 / 457) | 68.7 / 109.9 | 67.1 / 79.3 | 3.3 / 5.2 | 3.79 / 9.73 | 2109 (1921-2486) | 120 | 34,999 |
| d. 1000x right after an unpause | 600 (143 / 457) | 67.7 / 71.5 | 63.9 / 71.2 | 3.6 / 5.1 | 4.54 / 7.12 | 2575 (1973-2946) | 122 | 33,815 |

`advance()` ms alone (the sim's share of a frame, no render), same split:

| condition | tick frames p95 / max | plain frames p95 / max |
|---|---|---|
| a. camera still, 1x | 9.5 / 10.2 | 3.0 / 7.3 |
| b. camera panning and zooming, 1x | 8.7 / 8.9 | 3.8 / 6.1 |
| c. 1000x steady | 13.4 / 18.1 | 9.5 / 14.7 |
| d. 1000x right after an unpause | 14.1 / 14.7 | 9.4 / 12.4 |

Facts worth tying to the table:

- Tick median 3.8 to 4.5 ms (spec restated budget (1): at most 8.0 ms), max 9.7 ms, at 1,921 to 2,946 stored pairs. This run reaches
  pop 120 to 122 only (it stops measuring at the first window above 120), so the pair count is below the earlier real-run
  figure (median 2,876 at pop above 120 over the whole of later play).
- At 1x the host runs one step per frame (frames are longer than the 50 ms step); at 1000x it runs 3 to 5 steps per frame
  and drops the rest of the hour backlog at the budget (about 34,000 sim hours dropped over 600 frames, as designed).
- A tick frame costs `advance()` about 5 to 6 ms more than a plain frame at p95 at 1x (9.5 against 3.0, 8.7 against 3.8) and
  about 4 to 5 ms more at 1000x (13.4 against 9.5; 14.1 against 9.4). No `advance()` call exceeded 18.1 ms.

## Trigger verdicts (spec rule: attributable means the frame has a tick step and the non-tick frames of the same condition do not show the same excess)

| trigger | verdict by the spec's rule | note |
|---|---|---|
| 3a: frame p95 over 16.7 ms attributable to tick steps | **not tripped on this host, but not decidable by wall time** | Wall p95 is over 16.7 ms in tick and plain frames alike (59 to 81 ms), so by the rule it is a view cost (software rendering), not attributable. The sim's own share: tick-frame `advance()` p95 8.7 to 14.1 ms, plain 3.0 to 9.5 ms. On a machine whose render plus model update is small, a tick frame would sit near or somewhat above 16.7 at 1000x (14 ms of `advance()` plus the view update of about 2 ms); that needs a run on real GPU hardware to settle. |
| 3b: any single frame over 33 ms attributable to a tick step | **not tripped** | Every wall frame is over 33 ms here, tick and plain, so none is attributable. Largest tick-frame wall max 109.9 ms (c) against plain max 79.3 ms in the same condition: that one excess (30 ms) is a candidate hitch, not matched by plain frames' max, but it is also not above the software-render noise (plain frames in (b) reach 88.8 ms); its `advance()` was at most 18.1 ms, under 33. Reported, not a trigger by the rule as written; it should be re-read on hardware. |
| 3c: more than 8,000 stored pairs, or tick median over 8 ms | **not tripped by this run** | Max stored pairs 2,946; tick median 3.8 to 4.5 ms (max 9.7 ms). The trigger is judged on a later calibration run at larger pop; the balance log (docs/balance/task-4-calibration.md) records 4,389 max pairs and 5.97 ms median at pop above 120. |

No remedy was built (no packed mirror, no tick scheduling change). Caveat for the owner: the wall-time thresholds cannot be
judged on a software renderer; the verdicts above are "no trigger under the rule's own definition", with the one
tick-frame wall outlier (c, 109.9 ms) and the `advance()` columns recorded so a hardware rerun of the same tool can confirm.
