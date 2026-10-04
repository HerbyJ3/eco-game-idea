# Art Still Needed for Station Zero (Task 2)

## 1. Already generated (8 images, pending download)

These were generated 2026-10-03 with Higgsfield Nano Banana 2 at 1.5 credits each:
- comms_exterior.png, archive_exterior.png (exteriors, cyan and violet accents)
- archive_interior.png, workshop_interior.png, greenroom_interior.png, reactor_interior.png (4 interiors)
- terrain_decals.png (2x2 grid: ice, pit, rocks, crater)
- sheet_colonist_sleeping.png (sleeping pose)

**Download steps:**
1. Allow d8j0ntlcm91z4.cloudfront.net in environment network settings
2. Run the curl commands from `docs/art/generated-2026-10-03.md` into `station-zero-handoff/assets/raw/`
3. Run `python3 tools/build_all.py` (15-20 s)
4. Run test suite: `python3 -m unittest discover station-zero/tools/tests`
5. Re-run `tools/shots.sh` to refresh the 12+ task-2 screenshots
6. Review overlay: check `assets/processed/_review/buildings.png` (comms/archive door rects measured, accent masks cyan/violet)

## 2. Still to generate (Nano Banana 2 prompts)

**Batch order:** 2 character sheets (then 4 jumpsuit atlas variants per sheet).

**Sheet 1 & 2: Extra colonist faces and hair** (two sheets, 4x4 layout, same poses)
- Generate with style reference: existing jumpsuit sheet (`sheet_colonist_jumpsuit.png`)
- Magenta background, 1024x1024
- Same layout: walk toward/away/side (12 frames), then idle, talking, carry crate (4 frames)
- Different faces and hair styles per sheet (variety for the 70-160 colonist population)
- Cost: ~3 credits per sheet (1.5 x 2 per sheet to recolor 4 roles)

**Prompt template:** Smooth 2D game art, 4x4 character sheet, Mars colonist in neutral gray jumpsuit with [new face/hair], same poses and scale as existing sheet, top-down/3/4 view, light from upper left, magenta background 1024x1024.

Dome-stage placeholder: NOT needed yet; landing/settlement phases use current buildings.

## 3. Known placeholder quirks

These will be fixed by real art:
- **Comms/archive exteriors:** currently tinted habitat sprites (cyan and violet hue shifts). Real versions add satellite dishes and storage panel patterns.
- **Reactor interior:** shows green bar (placeholder indicator). Real interior has amber-orange core glow and thermal systems.
- **Comms/archive window glow:** placeholder windows don't detect as blue, so they don't glow at night. Real interiors have cyan accents.
- **Interior furnishings:** procedural panel floors now. Real art adds shelving, hydroponic beds, workbenches, reactor core.
- **Terrain decals:** placeholder blobs. Real art adds detail to ice patches, pit excavation, rock outcrops, crater features.
- **All colonists:** one face/hair shared. Real sheets add visual variety.
