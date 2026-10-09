# Task 2 performance report (plan step 17)

Everything below was measured by `tools/perf_run.gd` (rerun with the command at the end). No code in sim/, view/ or data/ was changed for the measurements. The "After LOD" section at the end records the follow-up fix.

## Setup

- Machine: 4 CPUs, Godot 4.5-stable, OpenGL 4.5 compatibility through xvfb on Mesa llvmpipe (CPU renderer, so frame numbers are pessimistic). Viewport 1280x720, res://view/main.tscn (HUD included).
- World: seed 42 stepped headless-style to sol 300 (147,959 steps, 201.7 s to build). Population 164, 53 buildings (Reactor 10, Habitat 33, Workshop 1, Green room 7, Archive 1, one site), 799 footprints, 10 thirst deaths, 8 beings outside at the start (4 to 7 during the scenarios).
- One roof open: the first habitat (id 2) selected with peek, fully eased open. Cameras: zoom 0.6 centred on the colony; zoom 2 and 6 centred on the open habitat. Day is mars hour 12, night is hour 0 (lamps, window and accent lights on).
- Per scenario: 600 calls of `vm.update(1/60)` timed alone (sim paused, camera rect set as the view does), then 600 live frames in the real renderer. Warm-up 30 frames each.
- Two full runs were made (run 1 and run 2, same seed, same script). Run 1 numbers are in the tables; run 2 agreed within noise (draw calls identical or within 1, model median within 0.25 ms, wall within 1.5 ms).

## Budget (art.json perf, spec section 10)

| budget | limit |
|---|---|
| view-model update, 160 beings, median | 2.0 ms |
| draw calls per frame | 150 |
| nodes | 300 |
| texture memory | 48 MB |
| frame time (informational) | 8 ms |

## Scenario tables (run 1, 600 frames each)

| scenario | pop | outside | model median ms | model p95 ms | model max ms | draw calls median (min-max) | nodes | process ms | render cpu ms | frame wall ms median (p95) | RENDER_TEXTURE_MEM_USED MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| day zoom 0.6 | 164 | 4 | 0.849 | 1.109 | 3.455 | 292 (290-292) | 28 | 39.40 | 5.07 | 32.9 (39.0) | 26.2 |
| day zoom 2 | 164 | 4 | 0.986 | 1.602 | 3.021 | 87 (87-88) | 28 | 35.00 | 2.13 | 27.3 (32.6) | 26.2 |
| day zoom 6 | 164 | 4 | 1.088 | 1.644 | 2.610 | 34 (34-35) | 28 | 28.55 | 1.66 | 22.9 (27.4) | 27.1 |
| night zoom 0.6 | 163 | 7 | 1.244 | 1.540 | 2.295 | 370 (369-372) | 28 | 45.03 | 8.04 | 37.6 (44.6) | 29.7 |
| night zoom 2 | 163 | 7 | 1.253 | 2.334 | 4.181 | 114 (113-114) | 28 | 35.29 | 2.38 | 29.5 (34.8) | 29.7 |
| night zoom 6 | 163 | 7 | 1.201 | 2.385 | 3.150 | 36 (35-37) | 28 | 29.68 | 1.39 | 23.3 (28.2) | 29.7 |

Notes on the columns: "process ms" is Performance.TIME_PROCESS, which under llvmpipe includes the software draw work, so it can exceed the wall time per frame. "render cpu" is the viewport measured CPU render time. Nodes is OBJECT_NODE_COUNT for the whole tree including the HUD (the world view itself is 1 + 10 layer nodes). Draw calls are Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME read after frame_post_draw.

Model update with the sim stepping at 1x (zoom 2, 600 frames at dt 1/60, so one sim step every third frame): median 1.477 ms, p95 2.417 ms, max 4.659 ms (run 1); run 2: median 1.259, p95 2.011, max 4.026. `world.advance` itself at 1x: median 0.001 ms, p95 3.2 ms, max 4.8 ms (a step costs 3 to 5 ms, see 1000x below).

### Texture memory

| measure | MB |
|---|---|
| manifest, real entries (42), x1.34 mipmaps | 27.01 |
| manifest, plus 24 placeholder files (66 files) | 40.92 |
| engine baseline before the scene (RENDER_TEXTURE_MEM_USED) | 7.1 (video mem 13.2) |
| RENDER_TEXTURE_MEM_USED with the view, peak scenario | 29.7 |
| view delta over the baseline, peak | 22.7 |

The spec's hand estimate is 44.2 MB; the manifest gives 27.0 MB real, 40.9 MB if every placeholder file counts. Textures load lazily (26.2 MB by day at zoom 0.6, 29.7 MB once the night masks are used).

### 1000x sim speed with the view attached (run 1, zoom 2, 120 frames)

| measure | value |
|---|---|
| advance() cap (max_steps_per_frame) | 2000 steps |
| cap hit | 119 of 120 frames, median 2000 steps per frame |
| sim hours dropped by the cap | 1,085,365 (over 1,110 s) |
| achieved speed | 10.7 sim hours per real second against 1000 requested (215 steps/s) |
| advance() per frame | median 9,334 ms, p95 12,837 ms, max 14,310 ms |
| cost per step at sol 300+ | median 4.67 ms (frames of 2000 steps) |
| frame wall median | 9,323 ms |
| steps a steady 60 Hz frame would ask | 334 (below the cap) |
| advance() with fixed 1/60 s delta, 60 calls, view idle | median 2,286 ms, p95 2,617 ms, max 2,722 ms (6.8 ms per step) |

So the cap is hit, but only because the sim is far too slow to keep up: one frame of 334 steps already takes 2.3 s, the next real delta is then seconds long, and every following request exceeds 2000 steps (a death spiral that the cap turns into slow-motion rather than a stall). The view is not the cost here. For comparison the whole build to sol 300 averaged 1.36 ms per step (201.7 s over 147,959 steps), so step cost grows strongly with population and buildings (4.7 to 6.8 ms per step at population about 160 and 53 buildings). I did not measure the headless step cost at this size separately from xvfb, so some of that may be CPU contention with llvmpipe threads.

### Layer probe (night, run 2, one layer hidden at a time, 60 frames each; wall times are noisy by about 3 ms)

| zoom | layer hidden | draw calls | wall ms median |
|---|---|---|---|
| 0.6 | none | 371 | 39.5 |
| 0.6 | entities | 204 (-167) | 28.7 |
| 0.6 | lights | 215 (-156) | 30.7 |
| 0.6 | terrain | 344 (-27) | 33.5 |
| 0.6 | tint | 370 | 33.4 |
| 0.6 | transit | 359 (-12) | 38.0 |
| 0.6 | corridors | 368 | 37.2 |
| 2 | none | 113 | 30.4 |
| 2 | entities | 62 (-51) | 23.0 |
| 2 | lights | 68 (-45) | 22.9 |
| 2 | terrain | 111 | 25.4 |
| 2 | tint | 113 | 26.1 |

Hiding shadows changed nothing at night (their alpha is 0 then). Footprints, dust, selection cost no measurable draw calls.

## PASS / FAIL

| budget | measured | verdict |
|---|---|---|
| view-model update median <= 2.0 ms | worst scenario median 1.253 ms (run 1), 1.391 ms (run 2); at 1x stepping 1.477 ms | PASS (margin 0.5 ms or more) |
| draw calls <= 150, zoom 0.6 day | 292 | FAIL by 142 (1.95x the budget) |
| draw calls <= 150, zoom 0.6 night | 370 (371 in run 2) | FAIL by 220 (2.47x the budget) |
| draw calls <= 150, zoom 2 day / night | 87 / 114 | PASS |
| draw calls <= 150, zoom 6 day / night | 34 / 36 | PASS |
| nodes <= 300 | 28 (whole tree) | PASS |
| texture memory <= 48 MB | 27.0 MB manifest (40.9 MB with placeholders), 29.7 MB RENDER_TEXTURE_MEM_USED | PASS |
| frame time 8 ms (informational) | 22.9 to 37.6 ms wall under llvmpipe, 2.9x to 4.7x over; render cpu 1.4 to 8.0 ms | not graded |
| 1000x with view attached (not a spec budget) | cap hit in 119 of 120 frames, 10.7 h/s instead of 1000 | reported, sim-bound |

Caveats on what the view-model PASS means: the spec's test case has about 20 beings outside; this world had 4 to 7 outside, so beings drawn outside are fewer than the budget assumes (the model still loops all 164 beings every update). The p95 of the model update is above 2 ms in several runs (up to 2.4 ms) and the max reaches 4 to 5.7 ms, so a frame can occasionally spike; the budget only grades the median. I did not count interior beings drawn for the open roof, and the pool-overflow counter named in spec section 10 is not exposed by the view (`vm.skipped` was 0).

## Top 3 costs and suggested fixes

1. Draw calls at far zoom (the only failing budget). At zoom 0.6, entities cost 167 calls and lights 156 calls at night (about 5 to 6 calls per finished building by day: pad stylebox, base, door halves, dim mask; 2 to 4 more by night: accent and window masks with halos, ground strip). Terrain adds 27. The textures are separate files, and the z-sorted draw order alternates textures, so Godot cannot batch them. Fix: add a far-zoom level of detail (below about zoom 1 skip doors, door glow, window and accent halos and ground strips, which are sub-pixel there), draw the pads into the terrain layer, and draw each light mask kind in one pass sorted by texture (or pack the masks into one atlas). Removing doors, halos and pads at zoom 0.6 alone is about 53 x 4 = 200 calls, enough to land under 150 by day and close at night.
2. Sim step cost, which decides the 1000x result. A step costs 4.7 to 6.8 ms at population 164 and 53 buildings (about 1.4 ms averaged over the whole run), so even 334 steps per frame at 1000x takes 2.3 s. Fix: profile `SimWorld.step()` at this size (it is outside the view and not changed here); give `advance()` a wall-time budget (for example stop after 8 to 10 ms of stepping) in addition to the step cap, and clamp the real delta fed to it so one slow frame cannot ask for thousands of steps; cap the speed presets by what the machine sustains.
3. Fill and full-screen layers under llvmpipe (frame wall 23 to 38 ms against 8 ms informational). Hiding the multiply tint quad saves about 4 to 6 ms per frame, the terrain about 5 to 6 ms, lights about 8 ms at zoom 0.6, the entities layer about 11 ms at zoom 0.6 (probe noise about 3 ms). Fix: skip the tint quad when the combined colour is near white by day, draw the tint and lights layers at half resolution or in a SubViewport, and bake terrain into one large pre-scaled texture. A GPU will do far better than llvmpipe, so confirm on real hardware before spending effort.

Not in the top 3 but worth watching: the model update median is 0.85 to 1.4 ms and its p95 is 1.5 to 2.4 ms, with spikes to 5.7 ms; it loops every being and builds pose dictionaries per visible being each refresh. Fix if it grows: refresh by sim step delta, skip pose work for beings that did not change state.

## After LOD (far-zoom level of detail)

Change: below `art.lod.detail_min_zoom` (1.0) the world view skips the foundation pad, door leaves, accent and window halo copies, ground strip, door glow, being shadows and helmet lamp glows. A finished building draws its base (plus the offline dim when offline); the light layer draws one accent mask and one window mask per building, grouped by kind so same-texture draws are consecutive and batch. Building shadows are grouped by kind too at far zoom. Construction phases, offline dimming, comms beacon and sprites stay at every zoom. At zoom 1.0 and above nothing changed. Same world, seed, cameras and command as above (one full run, 600 frames per scenario).

| scenario | draw calls before | draw calls after (min-max) | budget 150 | model median ms before / after | frame wall ms before / after (llvmpipe, noisy) |
|---|---|---|---|---|---|
| day zoom 0.6 | 292 | 99 (97-99) | PASS | 0.849 / 0.979 | 32.9 / 27.5 |
| night zoom 0.6 | 370 | 101 (100-103) | PASS | 1.244 / 1.036 | 37.6 / 28.5 |
| day zoom 2 | 87 | 87 (87-88) | PASS, unchanged | 0.986 / 1.068 | 27.3 / 28.0 |
| night zoom 2 | 114 | 113 (113-114) | PASS, unchanged | 1.253 / 1.288 | 29.5 / 30.4 |
| day zoom 6 | 34 | 34 (34-35) | PASS, unchanged | 1.088 / 1.116 | 22.9 / 23.7 |
| night zoom 6 | 36 | 37 (36-37) | PASS, unchanged | 1.201 / 1.312 | 23.3 / 23.0 |

Layer probe at zoom 0.6, night (draw calls with that layer hidden; none hidden: 102, before 371):

| layer hidden | before | after |
|---|---|---|
| entities | 204 (-167) | 60 (-42) |
| lights | 215 (-156) | 90 (-12) |
| terrain | 344 (-27) | 73 (-29) |
| transit | 359 (-12) | 90 (-12) |

Both zoom 0.6 scenarios are now under the 150 budget (about 100 calls). Zoom 2 and 6 draw calls are the same within 1 call (the day-to-day variation of beings). Remaining far-zoom cost is terrain (29), the y-sorted building bases and beings (42) and transit (12). Shots: s02 to s27 and the other 32 shots at zoom 2 and above are byte-identical to the pre-change renders; only the two zoom 0.6 shots (s28_zoom_min, sol100_zoom_out) differ, by design (no pads under buildings, no door leaves, so the dark door opening of the base art shows).

## Rerun

```
xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero \
  --script res://tools/perf_run.gd -- [--seed 42] [--sols 300] [--frames 600] [--warmup 30] \
  [--speed-frames 120] [--probe true --probe-frames 60]
```

The world build takes about 200 s; the six scenarios about 8 minutes under llvmpipe; the 1000x test about 20 minutes at this population (use `--speed-frames 0` to skip it, or a smaller number such as 10 for a quick read).
