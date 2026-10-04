# Spec: sprite world view, art pipeline outputs, doors, lights (Task 2)

Source of truth: `station-zero-handoff/HANDOFF.md` sections 2, 6. Plan and owner decisions: `docs/tasks/task-2-plan.md`. Sim data read: `docs/specs/life-support-power.md` (sections 4, 6, 7, 8.5, 11). Visual reference: `station-zero-handoff/prototype/station-zero-wip.html` ("proto L<n>" = line n).
Label key: **A1, A2, A4, A5, A7, A10** are the ambiguity numbers of `docs/tasks/task-2-plan.md` section 4; **A9, A13** are the resolved ambiguities of `docs/specs/life-support-power.md` section 11 (interiors have no x,y; offline effects).
Every number below lives in `data/art.json` (path `art.<group>.<key>`, listed in section 13). Footprint fade (2.5 sols) and footprint cap (2,200) are read from `data/suits.json` (`footprint.fade_sols`, `footprint.cap`), tile size from `data/buildings.json` (`tile_px` = 8). They are not duplicated. Sol length (24.6597 h) comes from `data/calendar.json`. No GDScript or Python appears in this document; function-like names are contracts.

## 0. Locked decisions and how the view respects them
- **Influence-only god**: the view has no input that changes the sim. Its only inputs are camera, selection, roof open, debug-map toggle. No build, spawn or command UI.
- **Ages, not meters**: no progress bars, percentages or counters are drawn for construction (the prototype's L1132-1137 build bar and "% done" tag are not ported). Progress is shown by the building itself (section 5.5). The text HUD from Task 0/1 stays as is.
- **Per-being energy**: not drawn. Energy only drives sim states; the view reads `state`, never energy.
- **Power as a budget**: an offline building is visibly dark (section 5.4). Reactors never go offline.
- **Selection**: a silhouette outline that hugs the building, never a box. This includes the roof-open state, sites and placeholders (outline masks exist for all of them, section 3.6). The prototype's rounded-rect fallback (proto L1172-1175) is dropped.
- **Owner decisions (Herby, 2026-10-03)**: (1) missing art is generated now and goes through the same pipeline; placeholders are only the fallback when an image fails or is absent; (2) each sprite is scaled to fit inside the building footprint with its proportions kept, anchored at the door, never stretched (section 4.1); (3) the debug dot map stays, toggled by a key; the sprite view is the default (section 8).

## 1. Purpose
Turn the sim's plain data into the prototype's look: buildings with doors and lights, a Mars day/night cycle, construction that visibly rises, suited colonists with walk cycles and lamps, footprints, a selectable building with a roof that opens onto an interior. The view is read-only. Everything animated (walk phase, door openness, particles, pulses, interior positions, camera) is **view state**, keyed by being or building id, derived from sim data each refresh, never written back. The view never calls `SimRng` or any global random function; it owns `RandomNumberGenerator` instances seeded from ids (section 11 rule V-RNG).

Two layers of deliverable:
1. **Pipeline** (Python, `tools/`): raw PNGs to processed PNGs, masks, atlases, a manifest (section 3).
2. **View** (Godot): a view model (plain data in, plain data out, fully headless-testable) and a world view that draws it (sections 4 to 10).

## 2. State the view reads (no sim change)
Per being: `id`, `role` (`builder`, `social`, `curious`, `tender`), `earth_born`, `state`, `building_id`, `x`, `y`, `heading` (outside only, else null), `load`, `wait_h`, `after`, `returning`, `job`, `mine` (`site.kind`; it is nulled at the end of the return trip, so the view never depends on it for doors), `suit_up`, `corridor_id`, `transit_t`, `from_a`, `suit_kind()` (`none`, `eva`, `construction`), `lamp_on(world)`.
Per building: `id`, `kind`, `tx`, `ty`, `tw`, `th`, `built` (0..1), `offline`, `door(tile_px)` = `((tx + tw/2) x tile_px, (ty + th) x tile_px)` (bottom centre of the footprint; `tile_px` = 8 from `buildings.json`), corridor (`p1`, `p2`, `len`; a corridor has no `built` of its own, the view uses the **owning building's** `built`).
World: `t`, `w.clock.mars_hour(w.t)` in [0, 24), `buildings.site`, `resources.ice_fields` (`x`, `y`, `r`, `amount`, `start`), `resources.pits` (`x`, `y`, `r`, `dug`), `resources.footprints` (`x`, `y`, `heading`, `t`, `heavy`).
**A9**: beings inside a building have no `x`, `y`. Interior positions are invented by the view (section 7.3), cosmetic, deterministic by being id, never fed back. Beings in `transit` are drawn in the corridor at `p1 + (p2 - p1) x s` with `s = transit_t` if `from_a`, else `1 - transit_t` (proto L1095-1098).
Mars hour for light is `w.clock.mars_hour(w.t)`. The sim's **night** (`beings.night`: 21.5 to 5.5) drives `lamp_on`; the light curve of section 5.1 is a separate visual curve whose full-dark window (21:30 to 05:30) is exactly the sim's night.
**Owner decision (Herby, 2026-10-03), final day/night schedule:** "from 19:00 the screen starts a slow transition to dark; by 21:30 it gets dark. At 19:00 the lamp can start with a low-light version, then at 21:30 full brightness." Concretely, every time is in `art.json`: full day until 19:00 (`light.dusk_start_h`); a slow ramp to full dark from 19:00 to 21:30 (`light.dark_start_h`, which is when the sim's night begins); full dark until 05:30 (`light.dark_end_h`, when the sim's night ends); a slow ramp back to full day from 05:30 to 07:00 (`light.day_start_h`). **The dawn ramp is the coordinator's mirror of the owner's dusk and is an assumption to confirm with the owner.** Window glow, accents and the day, dusk and night tints all follow the same night factor. Helmet lamps (beings outside): intensity 1.0 whenever the sim's `lamp_on(w)` is true (21:30 to 05:30); otherwise `art.lamp.low` 0.3 + (1 - low) x ramp across the 19:00 to 21:30 ramp (low at 19:00, 1.0 at 21:30), and across the 05:30 to 07:00 ramp it falls from 1.0 to 0 (off at 07:00); 0 in daytime. Exact formula in 4.4. Aligning anything else in the sim's night is out of scope; `sim/` is untouched in Task 2.

## 3. Pipeline outputs
Command: `python3 tools/build_all.py` (raw to processed, one command, byte-identical on a second run). Raw inputs in `assets/raw/`, outputs in `assets/processed/`. Pillow only; Lanczos for every resize; no random numbers anywhere in the pipeline.

### 3.1 Raw names and kinds
Kind ids are the sim ids: `reactor`, `habitat`, `workshop`, `green_room`, `archive`, `comms`. Raw file names per kind are in `art.kinds.<kind>.raw_exterior` and `raw_interior` (for example `green_room` maps to `greenroom_exterior.png`). Sheets: `sheet_colonist_jumpsuit.png`, `sheet_eva_suit.png`, `sheet_construction_suit.png`. If a raw file is missing, the pipeline builds the placeholder (section 3.8) and flags it. Ice fields, pit and tunnels are procedural, no files.

### 3.2 Output files (all PNG, RGBA, 8 bits, lowercase snake_case)
```
assets/processed/
  manifest.json
  buildings/<kind>_base.png            exterior, door opening filled with the dark gradient
  buildings/<kind>_door.png            the door leaves only, cropped to the door rect
  buildings/<kind>_mask_accent.png     (absent mask = fully transparent PNG of the same size)
  buildings/<kind>_mask_windows.png
  buildings/<kind>_mask_outline.png
  buildings/<kind>_mask_shadow.png
  buildings/<kind>_mask_gray.png
  buildings/<kind>_mask_ghost.png
  buildings/<kind>_interior.png        top-down interior, fitted later inside the exterior rect
  buildings/<kind>_interior_outline.png
  characters/jumpsuit_<role>.png       4 pre-baked recolors (builder, curious, social, tender)
  characters/eva.png
  characters/construction.png
  characters/<sheet>.json              frame table, pivots, lamp anchors (section 3.5)
  characters/sleeping_<role>_<n>.png   4 roles x 4 poses (n = 0..3), optional (section 3.10)
  terrain/decal_<name>.png             ice, pit, rocks, crater, optional (section 3.10)
  placeholder/...                      same names, always built for every kind (section 3.8)
  _review/*.png                        contact sheets for humans, not in the manifest
```
All eight exterior images of a kind (`base`, five masks, plus `ghost`) have **identical** pixel size so one transform draws them. Door leaves are the size of the door rect in pixels.

### 3.3 Sizes, scale, pivot
- Buildings: keyed, cropped to the bounding box of alpha > 0, Lanczos-scaled to width `art.pipeline.building_width_px` = 384 px, height from the cropped aspect (rounded to an integer). Interiors: width `interior_width_px` = **512** px, aspect kept (1264x848 raw gives 512x343). Reason: at the maximum zoom (6) a 104 px footprint is 624 screen px, so 384 texels keeps the upscale below 2x; the interior (about 99 world px wide, 594 screen px at zoom 6) is upscaled about 1.2x at 512, acceptable, and 512 keeps the texture budget honest (section 10: a 768 px interior would push the sum to about 62 MB). At the minimum zoom 0.6 mipmaps are required (import setting).
- Pivot of a building sprite (stored in the manifest, normalized): `x` = horizontal centre of the door rect `(door_rect[0] + door_rect[2]) / 2`, `y` = 1.0 (the bottom edge of the image). The bottom edge is where the paved apron meets the footprint's bottom edge, which is the sim door's y. The door rect itself sits above the bottom edge (about 0.87 of the height) and is not the pivot, otherwise the sprite would hang outside the footprint.
- Interior pivot: `(interiors.<kind>.door[0], 1.0)`, the door gap at the bottom.
- Characters: one 4x4 atlas per sheet, cell `character_cell_px` = 128 px (atlas 512x512). One shared scale per sheet, chosen so the tallest frame's content is `character_height_in_cell_px` = 112 px; all frames use that scale (no per-frame bbox, so the walk does not jitter). Pivot (feet, bottom centre of the shared box) = `character_pivot_px` = (64, 120) in every cell. Every frame content must fit inside its cell (the widest frames are pickaxe and carry; test P-9).
- Frame names (rows from `art.sheets.rows`): `walk_front_0..3`, `walk_back_0..3`, `walk_side_0..3` (side faces right; mirror for left), then the four extras per sheet in `art.sheets.<sheet>.extras` order: jumpsuit `idle_front, idle_side, talk, carry` (carry = crate); eva `idle_front, idle_side, dig, carry` (carry = ice block); construction `weld_1, weld_2, carry, idle_front` (carry = steel beam). Construction has no `idle_side`; a missing frame falls back to `idle_front`.

### 3.4 Keying and cleaning (HANDOFF section 6, steps 3 and 4, with refinements)
Raw lookup: for each raw name the pipeline searches `pipeline.raw_dirs` in order (`assets/raw`, then `../station-zero-handoff/assets/raw`, relative to the project); the first match wins. Names in `pipeline.raw_ignore` (`old_pixel_habitat_test.png`) are never read.
1. **HANDOFF threshold, border-connected**: a pixel is key colour when R > `key.r_min` 150, B > `key.b_min` 150, G < `key.g_max` 120, and it is removed when it belongs to a 4-connected region of such pixels that touches the image border. Enclosed regions of threshold pixels are kept (workshop pink neon is art) unless rule 1b applies.
1b. **Near-pure magenta anywhere**: every pixel with R > `key.pure_r_min` 200, B > `key.pure_b_min` 200, G < `key.pure_g_max` 80 is removed wherever it is, including enclosed regions of any size (a gap between crane cables, a window). `key.enclosed_min_px` 200 additionally removes enclosed regions of threshold pixels that large. P-3 asserts no near-pure magenta pixel survives.
2. Erode the alpha edge `key.erode_px` 1 px, then de-fringe: edge pixels' colour is replaced by the nearest interior opaque colour so the mean of (R minus G) over alpha-edge pixels is at most `key.defringe_edge_r_minus_g_max` 20.
3. The interiors are on a gray background (plan A10): flood fill from the four corners with colour distance <= `key.gray_bg_tolerance` 24 from the corner colour, then crop. If a corner pixel is magenta (R > 150, B > 150, G < 120; generated interiors may use the magenta background), use the rule 1/1b magenta keying for that image instead. The outer wall must stay opaque: `key.wall_probe_points` 3 probe points on the wall are asserted opaque.
4. Sheets (plan A1): find separator lines from the column and row profile of pixels with luma < `sheet.separator_luma_max` 90 and not magenta, a line counts when at least `sheet.separator_min_run_frac` 0.6 of its length qualifies; if none, snap to multiples of `sheet.grid_snap_px` 256; inset each cell `sheet.cell_inset_px` 6 px; key; crop to content per cell for measuring only; scale shared; paste at pivot.

### 3.5 Sheet JSON (`characters/<sheet>.json`)
`{ "cell_px", "pivot_px", "scale", "frames": { "<name>": { "col", "row", "lamp_anchor_px": [x, y] | null } } }`. `lamp_anchor_px` is the helmet lamp in cell pixels (eva and construction sheets only): the centre of the brightest 3x3 block (`pipeline.lamp.block_px`, mean luma at least `lamp.luma_min` 235) inside the top `lamp.head_frac` 0.3 of the frame's opaque height; if none is found (the first front frame of the EVA sheet shows no lamp), the top-centre of the opaque bounding box, and back-view frames always use `art.sheets.lamp_anchor_back_frac` (0.5, 0.0) of the opaque box. Jumpsuit frames have null anchors.

### 3.6 Masks (per exterior, same size as `base`; interior outline same size as the interior)
Colour tests are in 8-bit RGB of `base`. A pixel is in a colour mask when the test holds and at least `masks.neighbor_min` 3 of its 3x3 neighbourhood (itself included) pass (noise removal, proto L995-998); it is written in the mask's colour at alpha 255, others alpha 0.
| Mask | Rule | Source |
| --- | --- | --- |
| accent | the accent class of the kind: `art.kinds.<kind>.accent` for real art (reactor amber, habitat cyan, workshop pink, comms cyan, archive violet, green room none) and `accent_placeholder` for placeholder art (comms amber, archive cyan, others as real); `none` = empty mask. violet: 120 <= R <= 190, B > 200, G < 150, colour (190, 150, 255). cyan: B > 185, G > 150, R < 150, B-R > 70, colour (90, 230, 255). amber: R > 200, 100 < G < 215, B < 120, R-B > 110, colour (255, 175, 60). pink: R > 200, G < 150, 70 < B < 170, R-G > 90, colour (255, 110, 140) | proto L1008-1009; pink (workshop neon) and violet (archive) new |
| windows | B > 130, R < 100, 55 < G < 175, B-G > 35, colour (255, 205, 140) | proto L1010 |
| outline | pixels with alpha < `outline.alpha_min` 100 within a disc of radius `outline.radius_px` 5 of a pixel with alpha >= 100, colour (255, 244, 222), alpha 255. The radius scales with image width: `round(radius_px x width / radius_ref_width_px)` = 5 at 384 px (exteriors), 7 at 512 px (interiors) | proto L1027-1039 (radius 4 at about 320 px) |
| shadow | every pixel with alpha > 0 becomes (28, 10, 4) at its own alpha | proto L1014 |
| gray ("unfinished") | luma l = 0.3R + 0.59G + 0.11B; out = (0.62 l + 30, 0.64 l + 32, 0.70 l + 38), alpha unchanged | proto L1013 (`masks.gray`) |
| ghost (blue blueprint) | out colour (110, 205, 255), alpha = min(alpha, l x 0.75) | proto L1012 |
| door leaves | the door rect of the kind, cut from the pre-fill image; mode `split` (two leaves, habitat, reactor, green room, archive, comms) or `rollup` (one panel, workshop) | HANDOFF 6 step 5 |
| door fill | vertical gradient from `door.fill_top_rgb` (20, 16, 22) to `door.fill_bottom_rgb` (52, 44, 48) painted into the door rect of `base` | HANDOFF 6 step 5 (the prototype ships a pre-made door image; L1046-1050 only draws the leaves) |
Door rects: `art.kinds.<kind>.door_rect` (normalized `[x0, y0, x1, y1]` to the keyed and cropped image). Habitat and reactor are HANDOFF values; workshop (0.323, 0.680, 0.677, 0.882) was read from the 1024 raw on the cropped bbox; green room, archive, comms are provisional copies of the habitat rect (the exterior style reference has the same door). The pipeline **measures** the rect from the art (largest rectangular region of door-leaf pixels around the estimate) and writes the measured rect to the manifest; the manifest wins at run time. If measurement fails, the pipeline falls back to the `art.json` rect and prints a warning (owner decision). P-6 asserts measured within `door.rect_tolerance` 0.04 of `art.json` per coordinate and, if `door_rect_provisional` is true, only that the measured rect lies inside the opaque area with its centre pixel luma <= `door.center_dark_luma_max` 90 after fill.

### 3.7 Recolor rule (jumpsuit, plan A2; also applied to the sleeping poses, 3.10)
A pixel of the gray jumpsuit sheet is "suit gray" when HSV saturation < `recolor.sat_max` 0.18, value between `recolor.value_min` 0.35 and `recolor.value_max` 0.95, and it is not outline (value < `recolor.outline_value_max` 0.30). Skin, hair, boots (dark), gold and outlines are excluded by these bounds. For role colour C: out = clamp(C x (pixel luma / mean luma of all suit-gray pixels of the sheet)) per channel, alpha kept. Role colours: builder `#d9733f`, curious `#8d70d6`, social `#3fb3c2`, tender `#6cb85a`. Four atlases are pre-baked (no shader). At least `recolor.min_changed_fraction` 0.95 of suit-gray pixels change; 0 pixels of the idle-front face region change; the carry crate tints (accepted, Q4).

### 3.8 Placeholders (fallback only)
Always built for **every** kind into `assets/processed/placeholder/` (so the fallback path is tested even when real art exists); `manifest.json` points a kind at the placeholder only when its raw is missing, and then sets `"placeholder": true`. Rules: `comms` = habitat base tinted `placeholder.comms.tint_rgb` (255, 200, 120) at strength 0.35, accent class amber (the habitat's accent-mask pixels recolored to the placeholder accent colour, since tinted cyan pixels would not pass the amber test), plus a blinking red beacon (section 5.3); `archive` = habitat base tinted (170, 130, 230) at 0.35 with its cyan accent kept; both keep the habitat door rect and the other masks recomputed on the tinted image. Missing interiors: dark floor `#2a272c`, 48 px tile pattern at alpha 0.03, a top bar of the kind colour (`art.kinds.<kind>.color`) `bar_h_px` 10 tall, the kind label (28 px) centred, the rounded silhouette is the outline mask, no furniture. A placeholder building looks different enough to be seen: `placeholder.min_unique_colors` 8 (the check that it is not a blank rectangle).

### 3.9 Manifest (`assets/processed/manifest.json`)
```
{ "schema": 1,
  "pillow_version": "<PIL.__version__>",
  "art_json_sha256": "<hash of data/art.json>",
  "entries": {
    "<id>": { "file": "buildings/habitat_base.png", "w": 384, "h": 244, "type": "building_base|building_door|building_mask|interior|interior_outline|atlas",
              "kind": "habitat", "mask": "accent",
              "pivot": [0.4995, 1.0], "door_rect": [x0,y0,x1,y1], "door_mode": "split|rollup",
              "placeholder": false, "raw": "../station-zero-handoff/assets/raw/habitat_exterior.png", "raw_sha256": "<hash of the raw, null when no raw>",
              "sha256": "<file hash, null when file is null>" } } }
```
`file` is null for an optional entry whose raw is absent (`placeholder: true`); the view then uses its procedural fallback. The view decides **only from the manifest**, never by probing for raw files. Ids: `building.<kind>.base`, `.door`, `.mask.<name>`, `.interior`, `.interior_outline`; `character.jumpsuit.<role>`, `character.eva`, `character.construction`, `character.sleeping.<role>.<n>`; `terrain.decal.<name>`; entries sorted by id, keys sorted, no timestamps (byte-identical rebuild). The verification report counts entries with `"placeholder": true`. Every kind must have an exterior and an interior entry (real or placeholder).

### 3.10 Optional and new raws (presence rule)
On **every** run the pipeline checks every raw named in `art.kinds.*` and `art.optional` (generated images arrive over time; eight are pending and blocked by the network for now). For each: found in `raw_dirs` gives a real entry with `raw` and `raw_sha256`; absent gives `placeholder: true`, `file: null` (or the placeholder file for kinds, 3.8). Dropping a raw in and re-running flips its entries from placeholder to real (test P-15). Nothing in the view probes the filesystem for raws.
- **Terrain decals** (`art.optional.raw_decals` = `terrain_decals.png`): a 2x2 grid on magenta, order from `optional.decals.order`: ice (top-left), pit (top-right), rocks (bottom-left), crater (bottom-right). Cut the four cells (separator detection as 3.4 rule 4), key, crop to content, Lanczos to width `decals.width_px` 256, aspect kept, written as `terrain/decal_<name>.png`. Use: an ice field draws the ice decal at width `2.6 x r` (`ice_width_over_r`) centred on the field, a pit draws the pit decal at width `1.5 x w` (`pit_width_over_w`, `w` from 5.8) centred on the pit; both replace the procedural blobs and rim and keep sparkles and the spoil heap. Rocks and craters are scattered by a view RNG with the fixed seed `scatter_seed` 4242, per world cell of `scatter_cell_px` 64 (seeded by hash(seed, cell x, cell y), so the scatter is stable when the bounds grow): expected `rock_per_cell` 0.5 rocks and `crater_per_cell` 0.06 craters per cell, widths `rock_width_px` [3, 6] and `crater_width_px` [12, 24], rotation random, rejected within `clearance_building_px` 12 of any footprint and `clearance_site_px` 20 of any ice field or pit. Missing decal: the procedural look of 5.8, rocks as `#7a4a30` ellipses and craters as `#4a2412` rings; the manifest entry is flagged `placeholder: true`.
- **Sleeping poses** (`art.optional.raw_sleeping` = `sheet_colonist_sleeping.png`): a 2x2 grid of four sleeping poses of the jumpsuit colonist on magenta. Slice into 4 poses, key, scale with the **jumpsuit sheet's scale** (so a sleeper matches a walker), paste centred in a `sleeping.cell_px` 160 cell with pivot `sleeping.pivot_px` (80, 80) (body centre), recolor per role with 3.7, write `characters/sleeping_<role>_<n>.png` (n = 0..3, 16 files). The sleep row uses `character.sleeping.<role>.<id mod 4>` when the manifest has it (real), no rotation; otherwise the fallback rotated `idle_front` of 4.4.

## 4. View model, geometry
View model = plain data in, plain data out; no Node, no sim write. Contract names below are the units tests call. Module split suggestion (file names are the engineer's call): `fit`, `light`, `doors`, `construction`, `facing_pose`, `footprints`, `interior_slots`, `selection`, `camera`, `particles`, `zsort`.

### 4.1 Fit rule (owner decision)
`fit_sprite(footprint, sprite_size, pivot_norm)`. Footprint rect F = `(tx x 8, ty x 8, tw x 8, th x 8)` px, expanded by `fit.box_pad_px` 0. Scale `s = min(F.w / sprite.w, F.h / sprite.h)` (one scale for both axes, never stretched). Size = `(sprite.w x s, sprite.h x s)`. Place the pivot at `(F.x + F.w/2, F.y + F.h)` (bottom edge centre = the sim door point). If `fit.clamp_inside` is true, shift horizontally so the sprite stays inside F (the door x may differ from 0.5 by under 1%). Result: the sprite never leaves F (tolerance `fit.epsilon_px` 0.001) and its door x equals the sim door x within the clamp. Leftover space (top, or both sides) is the foundation pad: F filled with `fit.pad_color` `#6f6157` at alpha 0.6, corner radius 2 px, drawn under shadows. Example: habitat 13x9 tiles is F 104x72; sprite 384x244 gives s = min(0.2708, 0.2951) = 0.2708, drawn 104x66, 6 px of pad above.
Side effects to check on shots s02, s07 and s08: (1) a 10x10 footprint (80x80) draws the same sprite at 80x51, so the pad is about 29 px tall, 36% of the footprint; (2) the drawn door sits about 8 px (world) above the sim door line, because the door rect's bottom is at about 0.87 of the sprite height and the apron fills the rest; beings leaving the door appear on the apron, not inside the door frame.
The same transform draws all of `base`, the masks, ghost, gray, outline and shadow, and the door rect: `door_world = origin + door_rect x size`. The footprint rect stays the logic rectangle (tap hit test, site stakes, work area).
Interiors fit inside the **exterior sprite rect** with the same rule (pivot `(interiors.<kind>.door[0], 1.0)` at the exterior sprite's bottom centre). Aspect ratios differ, so the interior may leave a pad strip; interior slots (normalized to the interior image) transform with it.
Sim sizes are 10..14 x 8..10 tiles (aspect 1.0 to 1.75) against a roughly 1.57 art aspect: the limiting side changes with the rect; this replaces the "stretch up to 25%" resolution of plan A4.

### 4.2 Facing (A7)
`facing(heading_rad)`: `vx = cos`, `vy = sin` (y down). If `|vy| > |vx| x walk.vertical_dominance` (1.25): `front` if `vy > 0`, `back` if `vy < 0`; otherwise `side` with `mirror = vx < 0`. Tunnel transit: direction from `p1` to `p2` if `from_a`, else `p2` to `p1`, same test. Idle (not moving) uses `front` (proto L1454), work, mining and talk poses use `side` with mirror from the last horizontal sign of the heading (`face`, view memory, +1 at birth of the view record; when `|cos| < 1e-6` keep the old value).

### 4.3 Walk phase and moving
`moving` = a position change of at least `walk.min_move_px` 0.004 px was seen within the last `walk.moving_hold_s` 0.15 s of **real** time. Phase advances by `walk.phase_per_px` 1.25 rad per px of **distance moved** (never per frame, never per sim step), with the advance of a single refresh clamped to `walk.max_advance_px_per_refresh` 8 px: a refresh that moved 30 px advances the phase by 8 x 1.25, `moving` stays true and there is **no pose jump** and no teleport special case, so at 100x and 1000x the legs keep moving without spinning. (Deviation from the prototype: proto L1446 ignored any move of 8 px or more, `dd<8`, which froze the legs at high speed.) Frame index = `floor(phase / (2 pi) x walk.frames) mod 4`. Rendered position is interpolated from the last two sim samples over the real time between them, clamped to `walk.interp_sample_interval_s` [0.016, 0.5] s; paused sim means no new sample and a still sprite while pulses and doors keep animating. Bob: `walk.bob_walk_px` 0.32 x |cos(phase)| lift when walking, else `bob_idle_px` 0.06 x sin(real_time x `bob_idle_rate_rad_s` 2.2 + id).

### 4.4 Pose and frame selection
`pose_frame(state, suit_kind, load, wait_h, after, returning, moving, facing, real_time)` returns `{sheet, frame, mirror, rotate_deg}`. `wait_h > 0` means "pausing in place" (sim `mining` and `work` pause with `wait_h > 0` and move when it is 0, section 8.3/7.5 of the sim spec; compare against `STEP_EPS` 1e-9).
Sheet by `suit_kind`: `none` = jumpsuit recolored by `role`; `eva` = eva; `construction` = construction.
| Case (first match) | Frame | Notes |
| --- | --- | --- |
| state `sleep` (inside only), manifest has `character.sleeping.<role>.<n>` (real) | that pose, n = being id mod 4, no rotation, centred on the slot | generated sheet (3.10) |
| state `sleep` (inside only), no sleeping pose in the manifest | `idle_front` rotated `colonist.sleeper_rotation_deg` -90, offset `sleeper_offset_px` (-3.2 x scale, -0.6 unscaled) | proto L1461 (`translate(-3.2*Sc, -0.6)`: only x scales) |
| construction, `work`, `wait_h > 0` | alternate `weld_1`, `weld_2` at `walk.weld_hz` 6 Hz, side view | welding sparks from section 5.6 |
| eva, `mining`, `wait_h > 0` | alternate `dig` and `idle_side` at `walk.dig_hz` 2 Hz, side view | dust or frost from section 5.6 |
| eva, `load > 0` | `carry` (ice block), side view, walk bob while `moving` | regolith loads also show the ice block (Q4) |
| construction, `eva`, `after == work`, not `returning` | `carry` (beam), side view, walk bob while `moving` | cosmetic: the sim has no beam; outbound builders carry one |
| jumpsuit, interior pause with another non-sleeping being within `interior.talk_radius_px` 10 | alternate `talk` and `idle_front` every `interior.talk_phase_s` 0.45 s (lower id speaks first) | cosmetic |
| `moving` | `walk_front_k`, `walk_back_k`, or `walk_side_k` by facing, k from section 4.3 | transit and interior walks included |
| otherwise | `idle_front` (`idle_side` is used only inside the dig alternation) | construction suit uses its `idle_front` |
Scale: `colonist.height_px` 7.6 world px for Earth-born; `earth_born == false` multiplies by `colonist.mars_born_scale` 1.1 (8.36 px). The pivot (feet) stays on the position, so a Mars-born being grows upward only; shadow ellipse (`colonist.shadow`: rx 1.8, ry 0.55, dy 0.15 px, alpha 0.33, colour `#1e0a04`) and lamp radii scale with it. Sprite scale = `height_px x born_factor / character_height_in_cell_px`. Inside an open building the being is drawn at `colonist.interior_scale` 1.9 x its normal size (the interior art is drawn at human scale, a bunk is 2.4x a sleeper otherwise).
Helmet lamp: when the lamp target (below) is on and the being is outside with suit not `none`, an additive glow at the frame's `lamp_anchor_px` (mirrored with the sprite): outer disc `lamp.outer_r_px` 2.2 at alpha 0.22 `#fff1cf`, core `lamp.core_r_px` 0.55 at alpha 0.95 white, ground pool `lamp.ground_r_px` 2.6 at alpha 0.07, offset `lamp.ground_offset_px` 2.6 px in the facing direction at the feet. The glow alpha terms above are multiplied by the lamp intensity `lamp_level`, which eases toward its target with `lamp.fade_s` 0.4 s (smoothing the step at 19:00 and at on/off edges). **Target** (owner decision, section 2), with `N` the night factor of 5.1 and `h` the Mars hour: 0 for a being inside; else 1.0 if `lamp_on(w)`; else `lamp.low + (1 - lamp.low) x N` for 19 <= h < 21.5 (0.3 at 19:00, 1.0 at 21:30); else `N` for 5.5 <= h < 7 (1.0 at 05:30, 0 at 07:00); else 0. Values: 18.99 gives 0, 19.0 gives 0.3, 20.25 gives 0.65, 21.5 gives 1.0, 2.0 gives 1.0, 5.5 gives 1.0, 6.25 gives 0.5, 7.0 gives 0. Proto L1609-1613 drew the lamp when `night > 0.15` scaled by the continuous night factor; the port adds the low-light start and the sim's `lamp_on` as the full-brightness rule. Dropped from the prototype: the mining and weld glints (proto L1608 and L1614, random bright flashes while digging or welding); the weld arc flash of 5.6 and dig dust cover them.

## 5. Buildings: doors, light, offline, construction, sparks
### 5.1 Light curve (proto L1063-1065, L1075)
`light(h)` with `h` = Mars hour:
Owner schedule (section 2), replacing the prototype's 5/7/17/19 curve. The **night factor** `N(h)` (0 = full day, 1 = full dark):
- `N = 0` for `day_start_h` 7.0 <= h <= `dusk_start_h` 19.0 (full day through 19:00 inclusive; the ramp starts just after);
- `N = (h - 19) / (21.5 - 19)` for 19 < h < `dark_start_h` 21.5 (slow dusk ramp, linear);
- `N = 1` for h >= 21.5 or h <= `dark_end_h` 5.5 (full dark, the sim's night);
- `N = (7 - h) / (7 - 5.5)` for 5.5 < h < 7 (slow dawn ramp; **the dawn ramp is an assumption to confirm with the owner**).
- `L = 1 - N` (daylight); `dusk = dusk_bump_gain x N x (1 - N)` = 4 N (1 - N), a blue bump that peaks (1.0) mid-ramp and is 0 at full day and full dark.
Full-screen multiply tint layers, in this order: day `#ffe6cc` at alpha 0.18 x L; dusk `#7e98dc` at alpha 0.42 x dusk (skipped when dusk is 0); night `#262b52` at alpha 0.86 x N. Windows, accents, door strip, door glow and corridor lamps use the same `N`. Expected values, checked by T-L1:
| h | N | L | dusk |
| --- | --- | --- | --- |
| 3 | 1 | 0 | 0 |
| 5.5 | 1 | 0 | 0 |
| 6 | 0.666667 | 0.333333 | 0.888889 |
| 6.25 | 0.5 | 0.5 | 1 |
| 7 | 0 | 1 | 0 |
| 12 | 0 | 1 | 0 |
| 18.99 | 0 | 1 | 0 |
| 19 | 0 | 1 | 0 |
| 20.25 | 0.5 | 0.5 | 1 |
| 21 | 0.8 | 0.2 | 0.64 |
| 21.5 | 1 | 0 | 0 |
| 23 | 1 | 0 | 0 |
Shadow vector: `dx = clamp((h - 12)/6, -1.4, 1.4) x 9` px, `dy = -6` px, alpha `0.32 x L`. Building shadow = the shadow mask drawn at offset `(dx, dy x 0.6)` and alpha `shadow.alpha x L x 1.4`; corridor shadow offset scaled 0.4, colour `#320e04`. At h = 12 dx is 0; at 6 it is -9; at 18 it is +9; at 4 it is -12.0 (not yet clamped: -1.333 x 9); at 3 it clamps to -12.6 (-1.4 x 9).

### 5.2 Doors (proto L1040-1060)
`door_open` per building, 0..1, per real frame: `open += (want - open) x min(1, dt x door.ease_rate_per_s)` with `dt` the real frame time clamped to `door.max_dt_s` 0.1 and ease rate 4 per s. Independent of sim speed and of pause. `want` = 1 when any being satisfies: (a) state `to_door`, `suit_up` true, `suit_kind()` is `none` inside but the being has `mine_intent` or `mine` (miner) and `building_id` = this building (suiting up inside; builders suit up too but at the tunnel end, so a `to_door` + `suit_up` being with a `job` is excluded); or (b) outside with `suit_kind() == "eva"` and `building_id` = this building (the building it left from, which stays set outside), and distance from its position to this building's `door(tile_px)` below `door.radius_px` 18 (leaving or returning, including a turn-back and a haul). The rule never reads `mine`, which is nulled at the end of the return trip. Builders have `suit_kind() == "construction"` and leave by the tunnel hatch, not the door, so they never open it. Only finished buildings (`built == 1`) animate doors; offline buildings still animate (doors are manual).
Drawing: leaves are clipped to the door rect. `split`: left half of the leaf image slides left, right half slides right, each by `open x half-width x door.travel_frac` 0.92. `rollup`: the single panel slides up by `open x door height x 0.92`, clipped to the rect. When `open > door.glow_min_open` 0.05, an additive warm glow at the bottom centre of the door rect, radius `door.glow_radius_frac` 0.6 x door width, colour `#ffe2b0`, alpha `0.25 x open x (0.4 + night)` (`glow_alpha`, `glow_night_base`).
Edge: with `built < 1` there is no door. A door cannot be above 1 or below 0.

### 5.3 Lights: accents, windows, strip, beacon (proto L1561-1593)
Applies to finished online buildings, scaled by `power` (5.4) and visibility `vis = 1 - cut` (cut from section 9.2). `pulse = 0.5 + 0.5 sin(real_time x rate + id x 1.7)`, rate 1.8 rad/s for reactors, 1.1 otherwise (`light.accent.pulse_rate_rad_s`).
- Accent mask additive at alpha `((0.08 + 0.22 pulse) + night x (0.30 + 0.45 pulse)) x vis`, plus a halo copy scaled up by `halo_expand_px` 1.5 px each side at alpha x 0.35.
- Windows mask, only when `night > 0.05`: alpha `0.85 x night x vis`, halo copy expanded 1 px at alpha `0.3 x night x vis`.
- Door strip, when `night > 0.2`: rect (footprint x, bottom edge y, width, 3 px) `#ffbf73` at alpha 0.10 x night, and a second strip expanded 2 px, below, at 0.05 x night. (Prototype also drew this for offline buildings; the port does not, an offline building is dark.)
- Corridor lamps (built corridors only): 1 px `#ffcf8a` dots every 14 px starting 6 px from `p1`, ending 3 px short of `p2`, alpha 0.85 x night.
- Beacon (comms placeholder only): at `placeholder.comms.beacon.pos_frac` of the sprite rect, `#ff4a3a` disc radius 1.6 px alpha 0.9, visible while `sin(real_time x 3) > 0.3` (about 40% duty).
All of the above are drawn after the tint layer (additive), so they are not darkened by it.

### 5.4 Offline = dark (sim spec A13, power as a budget)
`power` per building eases linearly toward 1 (online) or 0 (offline) over `offline.fade_s` 0.5 s of real time (`power` is 1 for a building that never went offline). Accent, windows, strip and door glow alpha are multiplied by `power`, so a fully offline building has none of them. An offline exterior has the shadow mask overlaid at alpha `offline.dim_alpha` 0.5 x `power_off` x (1 - cut) (proto L1325-1329); an open interior is dimmed with black at `offline.interior_dim_alpha` 0.55. Spark flicker (proto L1567): at a rate of `offline.flicker_per_s` 1.2 per real second (the prototype's 2% per frame at 60 fps), a `#ffd27a` disc radius 2 px alpha 0.9 appears for `flicker_life_s` 0.08 s at a random point of the footprint (x inset 4 px, y within the top 60%), additive. Reactors cannot be offline. Sleepers inside an offline habitat are unaffected visually apart from the dimming.

### 5.5 Construction phases (proto L1334-1371, L1405 on)
A building with `built < 1` is a site. With `built` as `b`: `p = max(0, (b - 0.4) / 0.6)` (`construction.start_built` 0.4, `span_built` 0.6), wall reveal `f = clamp((p - 0.15) / 0.75, 0, 1)`, paint `g = clamp((p - 0.45) / 0.55, 0, 1)`, scaffold `sa = p/0.08` if `p < 0.08`, `max(0, (1 - p)/0.12)` if `p > 0.88`, else 1. Draw order inside the sprite rect `(X, Y, W, H)` (the fit rect of 4.1):
1. **Survey stakes and ghost** (always while a site): four stakes `#e8d9a8`, 1 x 3 px, at the **footprint** corners (bottom pair raised by 3 px); the ghost mask over the sprite rect at alpha `0.22 + 0.08 sin(real_time x 2.5)`.
2. **Slab** when `p > 0`: rect `(X + 2, Y + 0.18 H, W - 4, 0.8 H)` `#8b8178` at alpha `min(1, p/0.12)`, with 0.6 px lines `#9c9289` every 7 px.
3. **Gray walls** when `f > 0`: the gray mask clipped to `y >= Y + H x (1 - f)` (rising from the bottom), clip rect padded 2 px.
4. **Painted panels** when `f > 0` and `g > 0`: the `base` image clipped to `y >= Y + H x (1 - g)`. (Since `g <= f` for every `p` the paint never passes the gray wall.)
5. **Scaffolding** when `sa > 0`: `#c99a3c`, line width 0.55: vertical lines at about 12 px spacing (count = max(2, round((W - 6)/12))) from `Y + 0.12 H` to `Y + H - 2` at alpha 0.85 x `sa`; horizontal lines every 9 px; diagonals every 24 px, 12 px run, at alpha 0.45 x `sa`; inset 3 px from each side.
Corridor: the tunnel reveals during the first 40% of the build, length fraction `min(1, b / 0.4)` (`construction.corridor_built_frac`), with a dashed outline of the full path at alpha 0.55 while `b < 1`, coloured with the owning building's kind colour (`art.kinds.<kind>.color`, proto L1219), `corridor.unbuilt_color_fallback` `#e8d9a8` if the kind is unknown. `b` is the owning building's `built` (corridors have none of their own).
Thresholds in `built`: nothing but stakes, ghost and tunnel until 0.40; slab at 0.40+; slab opaque at 0.472; walls start 0.49; paint starts 0.67; scaffolds start to come down at 0.928; finished drawing at 1. Values for tests T-C1:
| built | p | f | g | sa |
| --- | --- | --- | --- | --- |
| 0, 0.3, 0.4 | 0 | 0 | 0 | 0 |
| 0.5 | 0.16667 | 0.02222 | 0 | 1 |
| 0.6 | 0.33333 | 0.24444 | 0 | 1 |
| 0.7 | 0.5 | 0.46667 | 0.09091 | 1 |
| 0.9 | 0.83333 | 0.91111 | 0.69697 | 1 |
| 0.95 | 0.91667 | 1 | 0.84848 | 0.69444 |
| 1.0 | finished art, no scaffold | | | |
Placing a site's sprite uses the finished kind's art at the same fit rect. The being work points are uniform in the footprint (sim deviation 3), so the seam is a view-only emitter (5.6).

### 5.6 Particles (view-only, proto L1523-1558)
One pool, cap `particles.cap` 600 (new ones are dropped, never evicted). Real-time clock. Own RNG: stream per source, seeded from `hash(source kind, being or building id)` (V-RNG). **Emission is deterministic by accumulator**: each source keeps `acc += rate x dt`, emits `n = floor(acc)` particles and sets `acc -= n` (dt clamped to `door.max_dt_s` 0.1); the RNG only draws each particle's position, velocity and life. So over T seconds a source emits `floor(rate x T)` particles, +-1, independent of frame rate.
- **Weld sparks at the hand**: a being in the weld pose (construction, `work`, `wait_h > 0`) emits `weld_hand.rate_per_s` 38 per second at offset (2.3 x face x scale, -4.2 x scale) from its feet; velocity x = U(-10, 10) + face x U(4, 14), y = U(-20, 4) px/s; life U(0.22, 0.6) s; gravity 48 px/s^2. Drawn additive as a line from previous to current position, width 0.38, colour `#ffe9a8` while more than half the life is left, else `#ff9a3c`, alpha = fraction of life left. Plus the arc flash: a `#9fd4ff` disc radius 2.6 x f at alpha 0.35 x f and a white core radius 0.6 at 0.95 x f, with `f = U(0.55, 1)` each frame.
- **Weld sparks at the rising seam** (new): while a site has `f` strictly between 0 and 1 and at least one `work` being with this job, it emits `weld_seam.rate_per_s_per_crew` 10 x min(crew, `max_crew` 3) per second from a random x across the sprite width at `y = Y + H x (1 - f)` (the top edge of the gray wall), x velocity U(-8, 8), y velocity U(-14, 2), life U(0.15, 0.4) s, same spark look. Crew count = beings in `work` with `job` = this site.
- **Dig dust and frost**: a being in the dig pose emits `dig.rate_per_s` 7 per second at offset (2.5 x face, -0.4), velocity x = U(-5, 5) + face x 3, y = U(-7, -1), life U(0.6, 1.3) s, radius U(0.5, 1.2) growing 1.4 px/s, velocity damped by 0.96 per 60 Hz frame (`0.96^(60 x dt)`), alpha 0.45 x life left; colour `#eaf8ff` for an ice site, `#c98b5c` for the pit. Not additive; drawn above beings, below the tint.
Particle emission uses the real `dt`, so at 1000x sim speed the particle count does not scale with the sim.

### 5.7 Footprints (proto L1085-1093)
Read `resources.footprints`. `age = (world.t - f.t) / (fade_sols x sol_hours)` with `fade_sols` from `suits.json`. Not drawn when `age >= 1`. Alpha = `(heavy ? 0.42 : 0.32) x (1 - age)`. Shape: ellipse rx 0.75, ry 0.42 px, colour `#4a1e0d`, rotated by `heading`; plus a heel rect `(0.45, -0.35, 0.25, 0.7)` `#d18a5e` at alpha x 0.6. Batched (one baked footprint texture, one instance per print, per-instance rotation and alpha) so 2,200 prints cost one draw. Drawn count within the camera rect must equal the sim's count of prints with age < 1 inside it.

### 5.8 Terrain (decals when present, procedural fallback)
Ground colour `#5a2a16`, no noise. With the decals of 3.10 present in the manifest, ice fields and pits draw their decal and rocks and craters are scattered; this section describes the procedural fallback (flagged `placeholder`) and the parts kept on top of decals (sparkles, spoil heap). **Ice field** from `resources.ice_fields`: `blob_count` 6 blobs per field with `dx, dy` U(-1, 1), `rr` U(0.35, 0.6), generated from a view RNG seeded by the field's rounded `x` and `y` (stable across refreshes); base ellipse at `(x + dx r 0.7, y + dy r 0.7)` radii `(r rr left, r rr 0.65 left)` `#b9c9cc`; highlight ellipse offset (-1, -1), scale (0.7, 0.45) `#e4eff0`; `left = 0.45 + 0.55 amount/start`; six white 0.8 px sparkles at angle `i x 1.7 + x`, radius `0.5 r x ((i x 37) mod 10)/10` (`sparkle_hash_mul` 37, `sparkle_hash_mod` 10), y offset squashed by `sparkle_y_squash` 0.6 (proto L1416), visible when `sin(2 real_time + 2i) > 0.6`. Dry fields are removed by the sim, so the view draws no dry state. **Regolith pit** from `resources.pits`: `w = 10 + 1.6 sqrt(dug)`, `h = 0.7 w`; rim rect `#c27a4c` (expanded 2 px), hole `#5a2614`, darker top 35% `#3e190c`, stripes `#7a3a1e` every 3 px, spoil heap ellipse `#b8683c` at (+6, 0) offset, radii `(5 + 0.5 sqrt(dug), 3 + 0.3 sqrt(dug))`, upper half. **Tunnels**: edge rect 7 px (y - 3.5), body 5.5 px `#a89e92` (from y - 3), highlight 1.2 px `#d4ccc0`, 1 x 6 px ribs `#887e73` every 6 px starting 3 px in, edge `#6e655c`; vertical corridors the same rotated (proto L1215-1240).

## 6. Draw order and z-sorting
Back to front (world space unless noted):
| Layer | Content |
| --- | --- |
| L0 | ground colour |
| L1 | ice fields, pits, scattered rocks and craters (decals or fallback) |
| L2 | footprints |
| L3 | tunnels (finished and growing, with dashed unfinished paths), tunnel shadows |
| L4 | beings in `transit` (jumpsuit), y-sorted; they emerge from under buildings |
| L5 | building shadows (shadow masks) |
| L6 | **y-sorted entities**: foundation pads, sites, finished buildings (exterior or interior with open roof, door leaves, offline overlay) and outside beings (shadow, sprite), see below |
| L7 | dust and frost particles |
| L8 | tint (screen space, multiply): day, dusk, night |
| L9 | additive lights: accents, windows, strips, door glow, lamps, corridor lamps, beacon, offline flicker, sparks, arc flashes |
| L10 | selection outline (pulse) |
| L11 | text HUD (screen space, existing) |
Sort key in L6: `(base_y, kind_order, id)` ascending; building `base_y = (ty + th) x 8` (bottom of the footprint), being `base_y = y`; `kind_order` building 0, being 1, so a being exactly at the door line (y equal) draws above the building and one even 1 px north of the bottom edge draws below it (behind). Deviation from the prototype (proto L1099-1100 drew every outside being above every building). Exception: a being whose position lies inside the footprint of a site (`built < 1`) draws above that site (builders work on it). Pad and shadow of a building are drawn with it (pad below its sprite, shadow in L5). Ties among beings: lower id first. Interior beings (roof open) are sorted by their interior y inside their building's entry, above the interior art and below the roof (the roof is crossfaded out, section 9.2).
Multiply (L8) must precede additive lights (L9) so lights and lamps are not darkened.

## 7. Interiors and interior beings
### 7.1 Art
`interior` image fitted inside the exterior sprite rect (4.1). Crossfades with the exterior by `cut` (9.2): exterior alpha `1 - cut`, interior alpha `cut`. Outline for selection while open: `interior_outline` mask.
### 7.2 Slots (`art.interiors.<kind>` override path; kinds without an entry use `art.interiors.default`)
Adding an `art.interiors.<kind>` entry (door plus slots) overrides the default for that kind with no code change; this is how generated interiors get real slots. The default grid has no bunks, so sleepers in kinds without an entry lie on the floor, which is fine for now.
Each slot: `id`, `type` (`bunk`, `seat`, `sofa`, `kitchen`, `stand`), `pos` normalized to the interior image; `door` normalized is the entry point. Habitat and comms slots were measured by eye from the raw interiors and are provisional until the pipeline overlay `_review/interiors.png` confirms them. The default has six floor points on a 3x2 grid.
### 7.3 Interior being model (sim spec A9, cosmetic)
For each building with `cut > 0` (and only those in the camera rect), beings with `building_id` = it whose state is `idle`, `to_door` or `sleep` (never `transit`, outside states), at most `interior.being_cap` 25 (lowest ids first).
- Sleepers (`sleep`): bunk slots in ascending being id order; extra sleepers lie at floor slots ("on the floor", also used when the building has no bunks); drawn with the sleeping pose (3.10) or, without it, the sleep rotation.
- Others: each holds a slot (no two beings in one slot), walks to it at `interior.walk_px_s` 10 world px per real second (reach `slot_reach_px` 0.8), pauses `interior.pause_s` U(1.5, 5) s, then picks a new free non-bunk slot with its own RNG seeded `hash(being id, building id)`. A `to_door` being with `suit_up` heads for the door point; when the sim moves it outside it is simply removed from the interior.
- A being that enters appears at the door point; a being that leaves is removed. Slot assignment is a pure function of (sorted ids inside, states, RNG sequence), so a repeated run with the same inputs and real-time steps gives the same positions.
- None of this is fed back; sim interior timers (section 6.2 of the sim spec) are unrelated.

## 8. Camera and input (`art.camera`)
- View toggle: **M** (`camera.keys.toggle_debug_map`) switches between the sprite view (default) and the existing debug dot map; the text HUD, speed keys (1 to 4) and space stay as they are. The toggle changes nothing in the sim. Camera keys apply to the sprite view only.
- Pan: left drag (after a `drag_threshold_px` 6 px move; below that a release is a tap), arrow keys or WASD at `pan_speed_screen_px_s` 520 screen px per second (world speed = that divided by zoom). Camera centre is clamped to the union of all building footprints expanded by `pan_margin_px` 240 world px (default bounds are the founder layout when there are no buildings).
- Zoom: `zoom_min` 0.6, `zoom_max` 6.0, default 2.0. Wheel: `wheel_step` 1.12 per notch (multiplicative, out is the inverse), the world point under the cursor stays fixed (proto L1649-1656); `+`/`=`/keypad plus and `-`/keypad minus at `key_zoom_per_s` 1.8 (zoom multiplier per second held), centre-anchored. Clamped to [min, max] after every change. (Prototype max was 9; 6 matches the 384 px art; accepted by the owner.)
- Reset (Home): zoom 2.0, centre on the centroid of the building footprints. Follow selected (F, toggle): the camera eases toward the selected building's centre at `focus_ease_per_60hz_frame` 0.08 per 60 Hz frame (`1 - 0.92^(60 dt)`), done when position is within `focus_done_pos_px` 0.5 and zoom within `focus_done_zoom_eps` 0.002; any user pan or zoom cancels follow. Escape deselects.
- Initial camera: default zoom, centre on the founder layout centroid.

## 9. Selection and roof
### 9.1 Select
A tap (press and release without passing the drag threshold) hits the building whose footprint contains the world point (footprints never overlap; the sim keeps a 2-tile margin). Tap an unselected building: select it, peek off for the previous one. Tap the selected building: toggle `peek`. Tap empty ground: deselect. `peek` is ignored while `built < 1` (a site can be selected but its roof does not open). Selection persists through completion (peek false).
### 9.2 Roof cut
`zoom_cut = clamp((zoom - 4.6) / 0.8, 0, 1)` for every building (`selection.zoom_cut_start`, `zoom_cut_span`): below 4.6 closed, above 5.4 open. `peek_cut` for the selected building eases linearly toward 1 (peek on) or 0 (off) at `1 / selection.roof_fade_s` per second (0.25 s). `cut = max(zoom_cut, peek_cut)` per building. Exterior alpha `1 - cut`; interior and its beings alpha `cut`; accent and window lights scale by `1 - cut`.
### 9.3 Outline
Outline mask (exterior when `cut < 0.5`, interior outline otherwise: `selection.silhouette_cut_below` 0.5) drawn at the sprite rect with alpha `pulse`, and a halo copy expanded `halo_expand_px` 1.6 px each side at alpha `0.3 x pulse`, where `pulse = 0.62 + 0.38 sin(real_time x 3.2)` (proto L1165-1171). Sites use the exterior outline at the same fit rect. No rectangle is ever drawn.

## 10. Performance budget (plan A5, `art.perf`)
- View model update for `perf.population_test` 160 beings (about 20 outside, the rest inside, six buildings, one open): at most `model_update_ms_max` 2.0 ms per refresh (median of 200 refreshes after warm-up, headless, release-like settings not required but the number is printed with the machine note).
- Refresh by sim step delta, not per frame; redraw only when the camera or sim step changes, or an animation is active.
- Total node count at most `node_count_max` 300 (pooled sprites, no per-footprint node); outside-being sprite pool grows on demand up to `outside_sprite_pool_max` 120; beings above the pool cap are not drawn and a counter reports it (must be 0 in the test).
- Draw calls at most `draw_calls_max` 150 (counted from the rendering info, informational under llvmpipe, printed).
- Particles at most 600; footprints at most 2,200 (sim cap), one batched draw.
- Interior beings at most 25 per building, only for buildings with `cut > 0` inside the camera rect.
- Texture memory at most `texture_memory_mb_max` **48 MB** (the number P-1 and T-PERF assert), computed from the manifest entries with a file (placeholders excluded unless that set is active) as `sum(w x h x 4) x mipmap_overhead 1.34`. Hand estimate (`texture_memory_mb_expected` 44.2): six kinds x seven exterior images of 384x244 = 15.7 MB; six interiors and six interior outlines of 512x343 = 8.4 MB; atlases (4 jumpsuits, eva, construction at 512x512) 6.3 MB; 16 sleeping poses of 160x160 = 1.6 MB; four decals about 256x256 = 1.0 MB; sum 33.0 MB x 1.34 = 44.2 MB. With 768 px interiors it would be about 62 MB, over the limit, hence 512.
- Frame time under xvfb is reported against `frame_ms_info` 8 ms and is informational only (llvmpipe).
- 1000x sim speed: the sim steps many hours per frame; the model refreshes once per rendered frame and walk phase is clamped (4.3), so view cost does not grow with sim speed.

## 11. Headless tests (prove every rule)
Godot tests in `tests/test_view_model.gd` and `tests/test_assets_import.gd` (run by `godot --headless --path station-zero --script res://tests/run_tests.gd`); Python tests in `tools/tests/test_assets.py`; shot checks in `tools/shots.sh` plus Python sampling. No test may have zero checks. World fixtures use `SimWorld.new(seed, {blank: true})` and direct field writes (sim spec section 2); the view model takes plain dictionaries.
### Pipeline (Python, `tools/tests/test_assets.py`)
- **P-1 Manifest**: every manifest entry exists, size equals `w`, `h`; mode RGBA; alpha contains both 0 and 255; sha256 matches; ids sorted; `art_json_sha256` matches `data/art.json`; `pillow_version` and `schema` present; every entry has `raw_sha256` (equal to the hash of the resolved raw, or null exactly when `placeholder` is true and no raw exists); every kind has exterior and interior entries; manifest texture memory at most 48 MB (`perf.texture_memory_mb_max`); count of `placeholder: true` is printed.
- **P-2 Determinism**: `build_all.py` twice gives byte-identical files and manifest.
- **P-0 Raw lookup**: with a file present only in `../station-zero-handoff/assets/raw`, it is found; present in both, `assets/raw` wins; `old_pixel_habitat_test.png` is never read.
- **P-3 Key**: no pixel with alpha > 0 and R > 150, B > 150, G < 120 in a region touching the border or an enclosed region of at least 200 px; **no pixel with alpha > 0 and R > 200, B > 200, G < 80 anywhere, enclosed or not**; corners transparent; mean R-G over alpha-edge pixels <= 20; the workshop neon strip pixels survive (at least one pixel of the pink accent mask exists).
- **P-4 Sizes**: building `base` width 384 and height = round(384 x cropped aspect); interior width 512; atlases 512x512; sleeping poses 160x160; decals width 256; all of a kind's exterior images the same size; door leaf size = door rect x base size (+-1 px).
- **P-5 Pivot**: manifest pivot y = 1.0 and x = door-rect centre; character pivot (64, 120) and feet baseline (lowest opaque row of idle and walk frames) equal across a sheet within `feet_baseline_tolerance_px` 1; all 16 cells non-empty and the same size; content inside the cell.
- **P-6 Doors**: measured door rect inside the opaque area; centre pixel of the door in `base` after fill is dark (luma <= 90) and in `door` is not; habitat and reactor rects within 0.04 of art.json per coordinate; modes: workshop `rollup`, others `split`; when measurement is forced to fail on a fixture the `art.json` rect is used and a warning is emitted.
- **P-7 Masks**: masks nonzero only where `base` alpha > 0; **the accent mask is non-empty for every kind whose accent is not `none`**, for the real set (reactor amber, habitat cyan, workshop pink, comms cyan, archive violet) and for the placeholder set with `accent_placeholder` (comms amber, archive cyan), a missing real raw being skipped with a printed note; windows non-empty for habitat; exterior outline pixels all outside `base` alpha >= 100 and within 5 px of it, interior outline within 7 px; shadow equals `base` alpha; ghost and gray values match the formulas on 100 sampled pixels; `none` accent gives an empty mask.
- **P-8 Recolor**: at least 95% of suit-gray pixels changed; 0 changed pixels in the face region; changed pixels were all suit-gray before; the mean luma of a recolored suit within 5% of the original mean luma ratio rule; the four atlases differ pairwise.
- **P-9 Slices**: grid detection on all three sheets finds 16 cells; widest frame fits in 128 px.
- **P-10 Interiors**: corners transparent, 3 wall probes opaque (plan A10); interior outline non-empty; a fixture with a magenta background takes the magenta keying path.
- **P-11 Placeholders**: every kind has a placeholder set; each has at least 8 unique colours; flagged `placeholder: true` when substituted (test by building with one raw temporarily renamed in a temp copy).
- **P-12 Lamp anchors**: eva and construction non-back frames have anchors inside the upper 30% of the opaque box; jumpsuit anchors null.
- **P-13 Decals**: with `terrain_decals.png` present: four files `terrain/decal_{ice,pit,rocks,crater}.png`, width 256, RGBA, corners transparent, no near-pure magenta, each non-empty, and the four contents come from the matching quadrant (ice top-left, pit top-right, rocks bottom-left, crater bottom-right, checked with a synthetic 2x2 fixture of four distinct colours); absent: entries `terrain.decal.*` have `placeholder: true`, `file: null`.
- **P-14 Sleeping**: with `sheet_colonist_sleeping.png` present: 16 files `characters/sleeping_<role>_<n>.png`, 160x160, pivot (80, 80) in the manifest, content inside the cell, drawn at the jumpsuit sheet scale (same scale value in the JSON), recolor obeys P-8 (at least 95% of suit-gray pixels changed, none outside suit-gray); a synthetic 2x2 fixture checks the slice order n = 0..3 (top-left, top-right, bottom-left, bottom-right); absent: the 16 entries are `placeholder: true`, `file: null`.
- **P-15 Presence flip**: in a temp copy, build without an optional raw (decals, sleeping, one kind exterior): entries are placeholder; drop the raw into the first `raw_dirs` entry and rebuild: the same entries become `placeholder: false` with a non-null `file`, `raw` and `raw_sha256`; remove it again and they flip back; all other entries' hashes are unchanged.
### View model (Godot, `tests/test_view_model.gd`)
- **T-F1 Fit**: for 100 random footprints (10..14 x 8..10 tiles) and the real manifest sizes: sprite rect inside the footprint (+-0.001), scale equal on both axes, bottom edge equals footprint bottom, door x equals sim door x within the clamp; habitat 13x9 gives scale 0.2708 and 104 x 66 (+-0.1).
- **T-F2 No stretch**: width/height ratio of the drawn rect equals the image ratio within 1e-6 for every kind and rect.
- **T-FA Facing**: headings 0, 90, 180, 270 degrees give side right, front, side mirrored, back; 60 degrees (|vy|/|vx| = 1.73 > 1.25) is front, 45 degrees is side; idle (not moving) is front; transit direction follows `from_a`.
- **T-W1 Walk phase**: moving 10 px in one refresh advances phase by 8 x 1.25 (clamped; `moving` is true, the pose stays a walk frame, no jump), moving 30 px does the same, moving 2 px advances 2.5; moving 6 px in 1 or in 100 equal refreshes gives the same phase (7.5 rad); zero distance gives zero advance; at simulated 1000x (30 px per refresh for 100 refreshes) the frame index still changes every refresh; zero distance gives zero advance; frame index 0..3 across one cycle.
- **T-W2 Interpolation**: render position is the lerp of the last two samples; with no new sample it holds the last.
- **T-P1 Pose table**: one row per case of 4.4 (state, suit_kind, load, wait_h, after, returning, moving) to the expected `{sheet, frame, mirror, rotate}`; weld alternates at 6 Hz (frames at t = 0 and t = 1/12 s differ); dig alternates at 2 Hz; sleep uses `character.sleeping.<role>.<id mod 4>` unrotated when the manifest entry is real and the rotated `idle_front` (-90) when it is a placeholder; missing `idle_side` for construction falls back to `idle_front`.
- **T-P2 Scale**: `earth_born == false` is exactly 1.1 x the Earth-born scale; the feet position is unchanged; interior scale 1.9 x.
- **T-LAMP Lamp**: target level for a being outside (lamp_on taken from the sim rule, true for hours >= 21.5 or < 5.5): 18.99 gives 0, 19.0 gives 0.3 (`lamp.low`), 20.25 gives 0.65 (midpoint), 21.0 gives 0.86, 21.5 gives 1.0, 23 gives 1.0, 2.0 gives 1.0, 5.5 gives 1.0, 6.25 gives 0.5 (midpoint of the falling ramp), 7.0 gives 0, 12 gives 0 (1e-6). A being inside gets 0 at every one of those hours. The level eased with `lamp.fade_s` 0.4 s reaches the target within 1% after 2 s and never overshoots; the glow is requested only for suit_kind eva or construction, at the frame's lamp anchor; glow alpha scales with the level.
- **T-L1 Light**: `N`, `L`, `dusk` equal the table in 5.1 at every listed hour (1e-6); explicitly full day (`N` = 0) at 18.99 and at 7.0, the ramp starting after 19.0 (`N` at 19.01 is 0.004), full dark (`N` = 1) at 21.5 and at 5.5; `N` is monotone non-decreasing over 19 to 21.5 and non-increasing over 5.5 to 7; tint alphas follow (night tint 0.86 x N, day 0.18 x L, dusk 0.42 x dusk); window glow alpha at hour 20.25 is half of its value at 23 (same `N`); shadow `dx` at 12, 6, 18, 4, 3 = 0, -9, 9, -12.0, -12.6 (the clamp case).
- **T-D1 Door**: open 0 stays 0 with no being; a miner in `to_door` with `suit_up` in this building sets want 1 (a builder with a `job` doing the same does not); an outside being with `suit_kind() == "eva"` and `building_id` = this building within 17.9 px of `door(8)` sets want 1, at 18.1 px want 0, and still 1 on the return trip when `mine` is null (fixture with `mine = null`); a construction-suit builder never does; per 1/60 s frames the door reaches at least 0.95 within 44 frames (0.73 s) and returns below 0.05 within 44 frames; the result is identical for sim speeds 1x and 1000x (it depends only on dt); `dt` above 0.1 is clamped.
- **T-D2 Door geometry**: `split` leaf offsets at open 0.5 are half-width x 0.5 x 0.92 each way; `rollup` offset at open 1 is 0.92 x door height up; offsets clip to the rect.
- **T-A1 Accent pulse**: alpha at hour 12 stays between 0.08 and 0.30 over a pulse period and at hour 23 between 0.38 and 0.83 (before `vis`); the reactor pulse period is 2 pi / 1.8 s, others 2 pi / 1.1 s; two buildings with different ids are out of phase.
- **T-O1 Offline**: with `offline` true, after 0.5 s of model time accent, windows, strip and door-glow alphas are 0 and the dim overlay is 0.5; before that they are linearly between; back online restores them; reactor never offline in the fixture; the flicker count over 1,000 s of model time (accumulator emission, 5.6) is 1,200 +-1, each lasting 0.08 s, at positions drawn from the seeded RNG inside the footprint.
- **T-C1 Construction table**: the table in 5.5 within 1e-4 for `p`, `f`, `g`, `sa`; `g <= f` for 1,000 values of `built`; corridor fraction 0.5 at built 0.2, 1 at 0.4 and above; the draw list for built 0.3 has stakes, ghost and tunnel only; for 0.7 has slab, gray (clip top at `Y + H x 0.5333`), paint (clip top at `Y + H x 0.9091`), scaffold; for 1.0 has none of them.
- **T-C2 Sparks**: with a crew of 2 and `f = 0.5`, over 10 s of model time (any frame rate: 60, 30 and 7 irregular frames) the seam emitter creates exactly `floor(10 x 2 x 10)` = 200 sparks (+-1); with crew 5 it is capped at 3 crews' worth, 300 (+-1); with `f` 0 or 1, none; a hand emitter makes 380 (+-1) over 10 s (38 per s); the pool never exceeds 600; same seed and dt sequence gives identical particles, different dt sequences give the same counts; the pool never exceeds 600; same seed and dt sequence gives identical particles.
- **T-FP Footprints**: alpha at age 0, 0.5, 0.99 for light and heavy equals 0.32, 0.16, 0.0032 and 0.42, 0.21, 0.0042; age >= 1 not drawn; a 3-sol-old print not drawn; count of drawn prints in a camera rect equals the count computed directly from the sim list.
- **T-Z Sort**: two beings with different y sort by y; a being at `y = bottom edge` sorts after its building, at `bottom - 1` before it; a builder inside a site rect sorts after the site regardless; equal keys sort by id; transit beings are in a separate earlier layer.
- **T-I Interior**: slots deterministic: the same fixture twice gives the same slot per being; sleepers occupy bunks in ascending id (3 bunks, 5 sleepers: 2 on the floor); no slot shared; at most 25 beings drawn; positions stay inside the interior rect; a being leaving disappears the same refresh; the sim state hash is unchanged after 10,000 refreshes.
- **T-S Selection**: tap on a footprint selects; tap again sets peek; tap another building moves selection and clears peek; tap empty deselects; drag over 6 px is not a tap; peek ignored on a site; `cut` at zoom 4.6, 5.0, 5.4 = 0, 0.5, 1; `peek_cut` goes 0 to 1 in 0.25 s; outline source is exterior at `cut` 0.49 and interior at 0.5; pulse stays within 0.24 and 1.0.
- **T-CAM Camera**: zoom clamps at 0.6 and 6.0 from both directions; wheel zoom about a cursor keeps the world point under it fixed within 1e-6; pan clamp keeps the centre inside the bounds; Home resets; follow eases and cancels on user input; key map matches `camera.keys`.
- **T-DBG Toggle**: pressing M flips the active view and leaves the sim state hash unchanged; default is the sprite view.
- **T-RNG No sim contact (V-RNG)**: stepping the view model 10,000 frames on a seed 7 world leaves the Task 1 sim state hash unchanged; a source scan of `view/**` finds no `SimRng`, `randomize`, or global `randf`/`randi` (only methods on a view-owned `RandomNumberGenerator`); same seed and inputs give identical view state.
- **T-DATA Tunables**: every leaf of `data/art.json` is named (as `art.<group>.<key>` or by its group path) in section 13 of this spec; no numeric literal other than 0, 1, 2 and array indices appears in `view/**` outside a data lookup (reviewer check backed by a grep test listing exceptions).
- **T-IMP Import** (`tests/test_assets_import.gd`): every manifest entry loads as `Texture2D` with the manifest size; mipmaps and linear filter on for buildings, interiors and atlases.
- **T-PERF**: at 160 beings the model update median is at most 2.0 ms; node count at most 300; texture memory at most 48 MB (hand estimate 44.2 MB); pool overflow 0; draw calls and node count printed.
### Shots (`tools/shots.sh`, `data/art.json shots.list`, approach in section 3 of the plan)
- **S-1** every shot is 1280x720 and not uniform (at least 50 distinct colours).
- **S-2** day vs night: mean frame luma falls along `s04` (18.99) > `s05` (20.25) > `s06` (23); `s04` equals `s02` within noise (full day at 18.99); mean luma of the window-mask region is higher in `s06` than `s02` by at least 20 levels and at `s05` is between the two.
- **S-3** offline: in `s10` the offline habitat's accent-mask region is darker than the online reactor's.
- **S-4** doors: pixel difference inside the door rect between `s07` and `s08` is above a threshold (leaves moved).
- **S-5** construction: the opaque painted height is monotone over `s11` to `s15` (`s15` = full sprite minus scaffolding); `s12` has the stake colour `#e8d9a8`; `s13` contains the spark colours when crew >= 1.
- **S-6** Mars-born: in `s19` the bounding box height ratio of the two beings is 1.1 +-0.03.
- **S-7** footprints: `s21` count of footprint-coloured pixels above zero and the drawn-print counter equals the sim count.
- **S-8** selection: `s22` has outline-colour pixels `(255, 244, 222)` hugging the habitat and no straight rectangle (a sampled outline pixel at the bounding-box corner of the footprint is absent).
- **S-9** roof open: `s23`, `s24`, `s25` differ from `s02` inside the building rect and show beings; `s26` all six roofs open.
- **S-10** placeholder: `s27` comms differs from `s02`'s comms and carries the red beacon colour at least half the sampled frames.
- **S-11** lamps: in `s17` (19:00, low) the lamp glow pixels are dimmer than in `s18` (23:00, full) by at least 20% in mean brightness at the lamp anchor.
Shots are never a pass/fail gate except S-1; judgment is the main session and Herby.

## 12. Screenshot list (sim moments)
Harness (exists: `tools/shot.gd`, `tools/shots.sh`, `tools/shots.txt`, `tools/shot_setups.gd`). Command: `xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path station-zero --script res://tools/shot.gd -- --seed 42 --steps 0 --hour 12 --zoom 3 --center 212,108 --out path.png [--size 1280x720] [--setup name]`. Arguments: `--seed`, `--steps` (fixed sim steps first), `--hour` (then step until `Clock.mars_hour` reaches H, at most one sol, never writes `t`), `--zoom`, `--center x,y` (world px), `--out`, `--size`, `--setup` (a name registered in `tools/shot_setups.gd`, applied before stepping). There is **no `--hours`**. Not `--headless` (dummy renderer, no pixels). `tools/shots.sh` runs the lines of `tools/shots.txt` (`name | args`); output `docs/shots/task-2/<name>.png`, one summary line per shot (seed, sol, Mars hour, steps, size).
`data/art.json` `shots.list` is the data source for `tools/shots.txt`: each entry maps to the harness arguments (`setup`, `seed`, `steps`, `hour`, `zoom`, `center` resolved through `shots.centers` to numeric x,y, `size` from `shots.width_px` x `shots.height_px`). One sol is 493.19 steps (24.6597 h / 0.05 h), so "sol 3" is `--steps 1480`. Shots whose moment is a condition (a site at a given `built`, a being mining, a footprint count) use the entry's `until` (up to `shots.max_steps` 8,000). Four harness extensions are requested from the godot-engineer, none needed by the existing arguments: (1) `--until key=value` for the `until` predicates `site_built_ge`, `crew_ge`, `any_state`, `footprints_ge`; (2) symbolic `--center` values `site`, `footprints`, `being_outside` resolved from the world; (3) `--view key=value` for the view-side states in `view` (`debug_map`, `select`, `peek`, `art_set`), applied through a scene method such as `apply_shot_view` when present; (4) the named setups below. Until they land, those shots fall back to a fixed `--steps` count and the numeric centres.
Setups (`tools/shot_setups.gd`): `founders` (exists), `showcase` (a blank world with the six buildings of `art.showcase`: all built and online, doors at the bottom edges, no corridors), `showcase_offline` (habitat and workshop offline), `showcase_door_habitat` and `showcase_door_workshop` (a miner in `to_door` with `suit_up` in that building, so the door opens), `showcase_suits` (one EVA miner, one construction-suit builder, one jumpsuit in a tunnel, near `showcase_beings`), `showcase_born_pair` (an Earth-born and a Mars-born EVA being of the same role, side by side), `showcase_interior_habitat` (6 beings inside, 3 asleep), `showcase_interior_comms` (4 beings), `showcase_interior_workshop` (3 beings). All set state through the sim's own API; the view reads it like any other state.
| Id | Setup, moment | Zoom | Shows |
| --- | --- | --- | --- |
| s01 | founders, 480 steps, debug map on | 2.0 | HUD plus debug map still works |
| s02 | showcase, hour 12 | 2.6 | all six exteriors, day |
| s03 | showcase, hour 6.25 | 2.6 | mid dawn ramp |
| s04 | showcase, hour 18.99 | 2.6 | still full day |
| s05 | showcase, hour 20.25 | 2.6 | mid dusk ramp |
| s06 | showcase, hour 23 | 2.6 | night, windows and accents lit |
| s07, s08 | showcase, hour 12, habitat door closed; showcase_door_habitat, open | 6.0 | split door |
| s09 | showcase_door_workshop, hour 12 | 6.0 | roll-up door |
| s10 | showcase_offline, hour 23 | 2.6 | offline dark next to lit buildings |
| s11 to s15 | founders seed 42, first site (a reactor) at built 0.0, 0.30, 0.60 (crew at least 1), 0.90, 0.97 | 4.0 | stakes and ghost, slab and walls, paint and sparks, scaffold coming down |
| s16, s17, s18 | showcase_suits at hour 12, 19, 23 | 6.0 | three suit kinds; lamp off, low, full |
| s19 | showcase_born_pair, hour 12 | 6.0 | 1.1x |
| s20 | founders until a being is in state `mining` | 3.0 | mining trip with dust |
| s21 | founders, 1480 steps and at least 20 footprints | 2.5 | footprints |
| s22 | showcase, habitat selected | 4.0 | silhouette outline |
| s23, s24, s25 | showcase_interior_habitat, _comms, _workshop, roof open (workshop placeholder interior unless generated) | 4.0 | interiors and slots |
| s26 | showcase at zoom 5.6, no selection | 5.6 | zoom cut |
| s27 | showcase with `art_set: placeholder` | 2.6 | placeholder set |
| s28, s29 | founders 480 steps at zoom 0.6; showcase reactor at zoom 6.0 | 0.6, 6.0 | camera limits |
The `until` predicates are: `site_built_ge`, `crew_ge`, `any_state`, `footprints_ge`.

## 13. Tunables (JSON key path under `data/art.json`, unit, starting value)
`art.schema` (integer, 1) versions the file; a test fails if it is missing or not 1.
Kind table `art.kinds.<kind>`: `accent` (class for real art: reactor amber, habitat cyan, workshop pink, green_room none, archive violet, comms cyan), `accent_placeholder` (class for placeholder art: comms amber, archive cyan, others as real), `color` (hex, proto KINDS), `roof_color` (hex, proto L1244), `raw_exterior`, `raw_interior` (file names), `door_mode` (`split` or `rollup`: workshop rollup), `door_rect` (normalized, section 3.6), `door_rect_provisional` (bool).
| Path | Unit | Start |
| --- | --- | --- |
| pipeline.raw_dirs | ordered search list (first match wins) | ["assets/raw", "../station-zero-handoff/assets/raw"] |
| pipeline.raw_ignore | file names never read | ["old_pixel_habitat_test.png"] |
| pipeline.building_width_px / interior_width_px | px | 384 / 512 |
| pipeline.character_cell_px / character_height_in_cell_px | px | 128 / 112 |
| pipeline.character_pivot_px / atlas_grid | px / cells | [64, 120] / [4, 4] |
| pipeline.lamp.head_frac / luma_min / block_px | frac / luma / px | 0.3 / 235 / 3 |
| pipeline.key.r_min / b_min / g_max | 0..255 | 150 / 150 / 120 |
| pipeline.key.erode_px / enclosed_min_px | px | 1 / 200 |
| pipeline.key.pure_r_min / pure_b_min / pure_g_max | 0..255 | 200 / 200 / 80 |
| pipeline.key.defringe_edge_r_minus_g_max / gray_bg_tolerance / wall_probe_points | levels / distance / count | 20 / 24 / 3 |
| pipeline.sheet.grid_snap_px / separator_luma_max / separator_min_run_frac | px / luma / frac | 256 / 90 / 0.6 |
| pipeline.sheet.cell_inset_px / feet_baseline_tolerance_px | px | 6 / 1 |
| pipeline.recolor.sat_max / value_min / value_max / outline_value_max / min_changed_fraction | 0..1 | 0.18 / 0.35 / 0.95 / 0.30 / 0.95 |
| pipeline.recolor.roles.builder / curious / social / tender | hex | #d9733f / #8d70d6 / #3fb3c2 / #6cb85a |
| pipeline.door.fill_top_rgb / fill_bottom_rgb | rgb | [20,16,22] / [52,44,48] |
| pipeline.door.rect_tolerance / center_dark_luma_max | norm / luma | 0.04 / 90 |
| pipeline.masks.luma_weights / neighbor_min | weights / count | [0.3,0.59,0.11] / 3 |
| pipeline.masks.windows, accent_cyan, accent_amber, accent_pink, accent_violet | thresholds and colour | section 3.6 |
| pipeline.masks.outline.radius_px / radius_ref_width_px / alpha_min / color | px / px / alpha / rgb | 5 / 384 / 100 / [255,244,222] |
| optional.raw_decals / raw_sleeping | file names | terrain_decals.png / sheet_colonist_sleeping.png |
| optional.decals.grid / order / width_px | cells / names / px | [2,2] / ice, pit, rocks, crater / 256 |
| optional.decals.ice_width_over_r / pit_width_over_w | x | 2.6 / 1.5 |
| optional.decals.scatter_seed / scatter_cell_px / rock_per_cell / crater_per_cell | seed / px / per cell | 4242 / 64 / 0.5 / 0.06 |
| optional.decals.rock_width_px / crater_width_px / clearance_building_px / clearance_site_px | px | [3,6] / [12,24] / 12 / 20 |
| optional.decals.rock_fallback_color / crater_fallback_color | hex | #7a4a30 / #4a2412 |
| optional.sleeping.grid / poses / cell_px / pivot_px | cells / count / px | [2,2] / 4 / 160 / [80,80] |
| pipeline.masks.ghost.color / alpha_scale | rgb / x | [110,205,255] / 0.75 |
| pipeline.masks.gray.r_mul / r_add / g_mul / g_add / b_mul / b_add | x / levels | 0.62 / 30 / 0.64 / 32 / 0.70 / 38 |
| pipeline.masks.shadow_rgb | rgb | [28,10,4] |
| pipeline.placeholder.comms.tint_rgb / tint_strength | rgb / frac | [255,200,120] / 0.35 |
| pipeline.placeholder.comms.beacon.pos_frac / rate_rad_s / threshold / radius_px / alpha / color | frac / rad/s / sin / px / alpha / hex | [0.55,0.30] / 3 / 0.3 / 1.6 / 0.9 / #ff4a3a |
| pipeline.placeholder.archive.tint_rgb / tint_strength | rgb / frac | [170,130,230] / 0.35 |
| pipeline.placeholder.interior.floor_color / tile_px / tile_alpha / bar_h_px / label_font_px | hex / px / alpha / px / px | #2a272c / 48 / 0.03 / 10 / 28 |
| pipeline.placeholder.min_unique_colors | count | 8 |
| fit.box_pad_px / clamp_inside / epsilon_px | px / bool / px | 0 / true / 0.001 |
| fit.pad_color / pad_alpha / pad_corner_px | hex / alpha / px | #6f6157 / 0.6 / 2 |
| colonist.height_px / mars_born_scale / interior_scale | world px / x / x | 7.6 / 1.1 / 1.9 |
| colonist.shadow.rx_px / ry_px / dy_px / alpha / color | px / alpha / hex | 1.8 / 0.55 / 0.15 / 0.33 / #1e0a04 |
| colonist.sleeper_rotation_deg / sleeper_offset_px | deg / px | -90 / [-3.2,-0.6] |
| sheets.rows.* , sheets.<sheet>.extras, sheets.lamp_anchor_back_frac | row index / names / frac | 0,1,2,3 / section 3.3 / [0.5,0.0] |
| walk.frames / phase_per_px / max_advance_px_per_refresh | count / rad per px / px | 4 / 1.25 / 8 |
| walk.min_move_px / moving_hold_s / vertical_dominance | px / s / x | 0.004 / 0.15 / 1.25 |
| walk.bob_walk_px / bob_idle_px / bob_idle_rate_rad_s | px / px / rad/s | 0.32 / 0.06 / 2.2 |
| walk.dig_hz / weld_hz / interp_sample_interval_s | Hz / Hz / s | 2.0 / 6.0 / [0.016, 0.5] |
| lamp.outer_r_px / outer_alpha / outer_color | px / alpha / hex | 2.2 / 0.22 / #fff1cf |
| lamp.core_r_px / core_alpha / core_color | px / alpha / hex | 0.55 / 0.95 / #ffffff |
| lamp.ground_r_px / ground_alpha / ground_offset_px / fade_s | px / alpha / px / s | 2.6 / 0.07 / 2.6 / 0.4 |
| lamp.low | lamp level at the start of the 19:00 ramp (0..1) | 0.3 |
| door.ease_rate_per_s / max_dt_s / radius_px / travel_frac | 1/s / s / px / frac | 4 / 0.1 / 18 / 0.92 |
| door.glow_min_open / glow_radius_frac / glow_alpha / glow_night_base / glow_color | frac / x / alpha / x / hex | 0.05 / 0.6 / 0.25 / 0.4 / #ffe2b0 |
| light.dusk_start_h / dark_start_h | Mars h (full day until, then ramp to full dark at) | 19.0 / 21.5 |
| light.dark_end_h / day_start_h | Mars h (full dark until, then ramp to full day at; dawn is an assumption) | 5.5 / 7.0 |
| light.dusk_bump_gain | x (dusk = gain x N x (1 - N)) | 4 |
| light.day_tint / dusk_tint / night_tint (color, alpha) | hex, alpha | #ffe6cc 0.18 / #7e98dc 0.42 / #262b52 0.86 |
| light.shadow.dx_hour_divisor / dx_clamp / dx_scale_px / dy_px / alpha | h / x / px / px / alpha | 6 / 1.4 / 9 / -6 / 0.32 |
| light.shadow.building_dy_scale / building_alpha_scale / corridor_scale / color | x / x / x / hex | 0.6 / 1.4 / 0.4 / #320e04 |
| light.accent.pulse_rate_rad_s.reactor / default / id_phase_rad | rad/s / rad | 1.8 / 1.1 / 1.7 |
| light.accent.day_base / day_pulse / night_base / night_pulse | alpha | 0.08 / 0.22 / 0.30 / 0.45 |
| light.accent.halo_expand_px / halo_alpha | px / x | 1.5 / 0.35 |
| light.windows.night_min / alpha / halo_expand_px / halo_alpha | night / alpha / px / alpha | 0.05 / 0.85 / 1 / 0.3 |
| light.ground_strip.night_min / alpha / alpha_outer / h_px / outer_expand_px / color | night / alpha / px / hex | 0.2 / 0.10 / 0.05 / 3 / 2 / #ffbf73 |
| light.corridor_lamps.spacing_px / start_px / end_inset_px / size_px / alpha / color | px / alpha / hex | 14 / 6 / 3 / 1 / 0.85 / #ffcf8a |
| offline.fade_s / dim_alpha / interior_dim_alpha | s / alpha | 0.5 / 0.5 / 0.55 |
| offline.flicker_per_s / flicker_life_s / flicker_radius_px / flicker_alpha / flicker_color | 1/s / s / px / alpha / hex | 1.2 / 0.08 / 2 / 0.9 / #ffd27a |
| offline.flicker_x_inset_px / flicker_y_frac | px / frac | 4 / 0.6 |
| construction.start_built / span_built / corridor_built_frac | built | 0.4 / 0.6 / 0.4 |
| construction.survey.stake_color / stake_w_px / stake_h_px | hex / px | #e8d9a8 / 1 / 3 |
| construction.survey.ghost_alpha / ghost_amp / ghost_rate_rad_s | alpha / alpha / rad/s | 0.22 / 0.08 / 2.5 |
| construction.slab.color / line_color / fade_p / top_frac / bottom_frac | hex / p / frac | #8b8178 / #9c9289 / 0.12 / 0.18 / 0.8 |
| construction.slab.inset_px / line_spacing_px / line_h_px | px | 2 / 7 / 0.6 |
| construction.wall.start_p / span_p; paint.start_p / span_p | p | 0.15 / 0.75; 0.45 / 0.55 |
| construction.clip_pad_px | px | 2 |
| construction.scaffold.fade_in_p / fade_out_p | p | 0.08 / 0.88 |
| construction.scaffold.color / alpha / diag_alpha / line_w_px | hex / alpha / px | #c99a3c / 0.85 / 0.45 / 0.55 |
| construction.scaffold.top_frac / bottom_inset_px / edge_inset_px | frac / px | 0.12 / 2 / 3 |
| construction.scaffold.col_spacing_px / row_spacing_px / diag_spacing_px / diag_run_px / min_cols | px / count | 12 / 9 / 24 / 12 / 2 |
| particles.cap / gravity_px_s2 | count / px per s^2 | 600 / 48 |
| particles.weld_hand.rate_per_s / offset_px / vx / vx_facing / vy / life_s | 1/s / px / px/s / s | 38 / [2.3,-4.2] / [-10,10] / [4,14] / [-20,4] / [0.22,0.6] |
| particles.weld_seam.rate_per_s_per_crew / max_crew / vx / vy / life_s | 1/s / count / px/s / s | 10 / 3 / [-8,8] / [-14,2] / [0.15,0.4] |
| particles.spark.line_w_px / hot_color / cool_color / hot_above_life_left | px / hex / frac | 0.38 / #ffe9a8 / #ff9a3c / 0.5 |
| particles.flash.outer_r_px / outer_alpha / outer_color / core_r_px / core_alpha / core_color / flicker | px / alpha / hex / x | 2.6 / 0.35 / #9fd4ff / 0.6 / 0.95 / #ffffff / [0.55,1.0] |
| particles.dig.rate_per_s / offset_px / vx / vx_facing / vy | 1/s / px / px/s | 7 / [2.5,-0.4] / [-5,5] / 3 / [-7,-1] |
| particles.dig.life_s / radius_px / grow_px_s / damp_per_60hz_frame / alpha | s / px / px/s / x / alpha | [0.6,1.3] / [0.5,1.2] / 1.4 / 0.96 / 0.45 |
| particles.dig.dust_color / frost_color | hex | #c98b5c / #eaf8ff |
| footprint.light_alpha / heavy_alpha / rx_px / ry_px / color | alpha / px / hex | 0.32 / 0.42 / 0.75 / 0.42 / #4a1e0d |
| footprint.heel_color / heel_alpha_scale / heel_rect_px | hex / x / px | #d18a5e / 0.6 / [0.45,-0.35,0.25,0.7] |
| selection.pulse_base / pulse_amp / pulse_rate_rad_s | alpha / alpha / rad/s | 0.62 / 0.38 / 3.2 |
| selection.halo_expand_px / halo_alpha / roof_fade_s | px / alpha / s | 1.6 / 0.3 / 0.25 |
| selection.zoom_cut_start / zoom_cut_span / silhouette_cut_below | zoom / zoom / cut | 4.6 / 0.8 / 0.5 |
| interior.walk_px_s / pause_s / talk_radius_px / talk_phase_s | px/s / s / px / s | 10 / [1.5,5.0] / 10 / 0.45 |
| interior.being_cap / slot_reach_px | count / px | 25 / 0.8 |
| interiors.habitat / comms / default (door, slots) | normalized to interior image | file |
| corridor.edge_half_px / body_top_px / body_h_px / highlight_h_px | px | 3.5 / -3 / 5.5 / 1.2 |
| corridor.rib_w_px / rib_h_px / rib_spacing_px / rib_inset_px | px | 1 / 6 / 6 / 3 |
| corridor.shadow_half_px / shadow_w_px | px | 3 / 6 |
| corridor.edge_color / body_color / highlight_color / rib_color | hex | #6e655c / #a89e92 / #d4ccc0 / #887e73 |
| corridor.unbuilt_color_fallback / unbuilt_alpha / unbuilt_dash_px / unbuilt_line_w_px | hex / alpha / px / px | #e8d9a8 / 0.55 / [2,2] / 0.6 (dash colour is the kind colour, fallback only if unknown) |
| terrain.ground_color | hex | #5a2a16 |
| terrain.ice.* (blob_count, blob_dx, blob_dy, blob_rr, offset_frac, y_scale, base_color, highlight_color, highlight_offset_px, highlight_scale, left_min, left_span, sparkle_*: count, angle_step_rad, hash_mul 37, hash_mod 10, y_squash 0.6, radius_frac, threshold, size_px, rate_rad_s, color) | counts, ranges, colours | section 5.8 and the file |
| terrain.pit.* (base_w_px, w_per_sqrt_dug_px, h_over_w, rim_expand_px, colours, shade_frac, stripe_*, heap_*) | px, colours | section 5.8 and the file |
| camera.zoom_default / zoom_min / zoom_max | zoom | 2.0 / 0.6 / 6.0 |
| camera.wheel_step / key_zoom_per_s | x per notch / x per s | 1.12 / 1.8 |
| camera.pan_speed_screen_px_s / drag_threshold_px / pan_margin_px | px/s / px / world px | 520 / 6 / 240 |
| camera.focus_ease_per_60hz_frame / focus_done_zoom_eps / focus_done_pos_px | frac / zoom / px | 0.08 / 0.002 / 0.5 |
| camera.keys.* | key names | section 8 |
| lod.detail_min_zoom | zoom | 1.0 |
| perf.model_update_ms_max / node_count_max / draw_calls_max | ms / count / count | 2.0 / 300 / 150 |
| perf.outside_sprite_pool_max / texture_memory_mb_max / texture_memory_mb_expected / mipmap_overhead | count / MB / MB / x | 120 / 48 / 44.2 / 1.34 |
| perf.frame_ms_info / population_test / model_frames_test | ms / beings / frames | 8.0 / 160 / 10000 |
| showcase.buildings | tiles | six rects in the file |
| shots.width_px / height_px / crop_scale / max_steps | px / px / x / sim steps | 1280 / 720 / 2 / 8000 |
| shots.centers / shots.list | world px / entries | named centres / 29 shots |

## 14. Edge cases
- `built` jumps (a site completes between refreshes): the view switches from the site draw to the finished draw in the same refresh; no scaffold remains. A site can never go backwards; if it does (a test fixture), the phases follow `built`.
- A site that is removed without completing (sim cannot do this in Task 1): the view drops it.
- Selection on a building that becomes offline keeps its outline; selected building under construction has no peek.
- A being outside with `x` null, a corridor id with no corridor, or a `suit_kind` the sheet lacks: skip drawing, increment a skipped counter (must be 0 in tests).
- Zero buildings: camera bounds fall back to the founder layout; draw nothing else.
- More than 25 beings inside one open building: the lowest 25 ids are drawn.
- Two beings at the same position: sorted by id, drawn both.
- A being drawn inside an open interior is not also drawn outside; a `to_door` suit-up being appears outside at the door only after the sim gives it `x, y`.
- `cut > 0` for several buildings at once (high zoom): each building's interior beings are modelled only if the building is in the camera rect.
- The tint layer and lights at dt = 0 (paused): still drawn from `world.t`.
- Missing manifest entry or hash mismatch: the world view refuses to start with a clear error (art out of date, run `build_all.py`).
- High-DPI: the 384 px art is minified at zoom below 3.1 screen-px-per-world-px; mipmaps required (T-IMP).
- Colonist carrying regolith shows the ice block frame (Q4).
- Interiors for kinds with no art yet: placeholder (3.8); roof-open still works and shows the slots of `default` (or the `art.interiors.<kind>` override).
- An optional raw (decals, sleeping poses) that appears later: the pipeline is rerun, the manifest flips to real, the view uses it with no code change.
- A 10x10 footprint leaves a tall pad above the sprite and the drawn door sits about 8 px above the sim door line (4.1 side effects); judged on s02, s07, s08.

## 15. Open questions, all decided (owner and coordinator)
- **Q1** Keying: HANDOFF threshold for border-connected regions, plus near-pure magenta removed everywhere (3.4 rules 1 and 1b; P-3).
- **Q2** Accents: real and placeholder class per kind (comms cyan / amber, archive violet / cyan, green room none); violet class added (3.6, P-7).
- **Q3** `zoom_max` 6.0 accepted.
- **Q4** Regolith load shows the ice block: accepted as a known limitation.
- **Q5** `interior_scale` 1.9 is the starting value, to be judged on shots s23 to s25.
- **Q6** Door rects: the pipeline measures each, falling back to the `art.json` rect with a warning (3.6, P-6).
- **Q7** Interior slots by eye for habitat and comms, plus the `art.interiors.<kind>` override path (7.2).
- **Q8** Owner decision (Herby), final schedule: screen ramps to dark 19:00 to 21:30, lamps low at 19:00 and full at 21:30 (section 2, 4.4, 5.1, T-L1, T-LAMP). **Still to confirm with the owner: the mirrored dawn** (full dark to 05:30, ramp to full day by 07:00, lamps falling from 05:30 to off at 07:00), which is the coordinator's assumption.

## Implementation notes (step 10, view model)
- T-A1: the night accent maximum from the 5.3 formula is 1.05 (not 0.83); the tests assert 1.05.
- T-C2: `dt` is clamped to 0.1 s per update, so a 10 s burst needs frames of at most 0.1 s; one 5 s frame emits the 0.1 s worth (3 hand sparks).
- 7.3: no two beings share a slot while slots remain; beyond the slot count (15 habitat, 6 default) beings share the floor, up to the 25 cap.
- 5.5 draw-list `clip_top` values are unpadded; the 2 px pad is applied at draw time.
- T-DATA literal scan covers `view/model/**`. Allowed literals: 0, 1, 2, array indices, 0.5 and 60.0. Noon is `calendar.hours_per_sol_clock x 0.5`; the face-sign epsilon is 1e-6.
- 4.3 interpolation: render lags one sample. `alpha = clamp((rt - t_newest) / clamp(t_newest - t_prev, 0.016, 0.5), 0, 1)` between the previous and newest samples.
- Particles emitted in an update are not aged in that update; `emitted` counts accepted plus dropped.
- Tolerances: float32 Rect2/Vector2, so 1e-5 on scale, `fit.epsilon_px` on positions, 1e-4 on leaf offsets, 1e-3 on interior walk speed.

## Changelog
- 2026-10-03 draft by game-designer. Pending: code-reviewer sign-off against HANDOFF sections 2 and 6 and the cited prototype lines.
- 2026-10-03 revision 2 (code-reviewer findings B1-B7 and 10 non-blocking, owner decisions Q1-Q8). B1 `pipeline.raw_dirs` and `raw_ignore`; B2 `art.optional` (decals, sleeping poses), presence rule, `raw_sha256`, P-13, P-14, P-15; B3 violet class and real/placeholder accent per kind, P-7 for every kind with an accent; B4 shadow dx at h=4 is -12.0, clamp case at h=3 is -12.6; B5 walk phase clamp without pose jump (deviation from proto L1446 noted); B6 `interior_width_px` 512, budget 48 MB with a 44.2 MB hand estimate; B7 keying rule 1 plus 1b (near-pure magenta everywhere, P-3). Non-blocking: field names (`door(tile_px)`, `w.clock.mars_hour(w.t)`, owning building's `built`), door rule on `suit_kind()` and `building_id` not `mine`, A-label sources, prototype citation fixes (door fill, sleeper offset, lamp threshold, dropped glints, sparkle squash and hash constants into art.json), fit side effects, deterministic accumulator emission and T-C2, interior outline radius scaling, unbuilt dash colour, `art.schema`, interiors override path, magenta-corner fallback, `pillow_version` in the manifest. (The interim lamp rule of this revision, on from 19:00 to 05:00, is superseded by revision 3.)
- 2026-10-03 revision 3 (owner's final light and lamp schedule). Light curve rewritten (5.1): full day through 19:00, linear ramp to full dark at 21:30 (sim night start), full dark until 05:30 (sim night end), ramp to full day at 07:00 (the dawn mirror is the coordinator's assumption, flagged for the owner). Night factor N drives tints, windows, accents; dusk tint is 4 N (1 - N). New `art.light` keys `dusk_start_h`, `dark_start_h`, `dark_end_h`, `day_start_h`, `dusk_bump_gain` replace the old dawn, dusk and centre keys. Lamps (4.4): 1.0 when `lamp_on`, else `lamp.low` 0.3 + 0.7 x N across 19:00 to 21:30, falling N across 05:30 to 07:00, 0 by day and inside; `lamp.visual_night_min` removed, `lamp.low` added. T-L1 and T-LAMP rewritten (18.99, 19.0, 20.25, 21.5, 2.0, 5.5, 6.25, 7.0, inside), shot S-11 added. Shot section reconciled with the existing harness (`--seed --steps --hour --zoom --center --out --size --setup`, no `--hours`): `shots.list` entries now use setup, steps, hour and numeric centres, `shots.max_run_hours` became `shots.max_steps`, 29 shots renumbered s01 to s29, four harness extensions and the named setups listed for the godot-engineer.
