# Station Zero (Godot 4.5)

Design source: `../station-zero-handoff/HANDOFF.md`. Task plans: `docs/tasks/`. Specs: `docs/specs/`.

All six building types and a format for interior descriptions: [building catalog](docs/art/building-catalog.md). Starting-building purposes and art requirements: [building design brief](docs/art/starting-buildings.md). Indoor behavior, animation gaps, and the animator/graphic-designer handoff: [indoor animation handoff](docs/art/interior-animation.md).

New owner inputs for player influence, organic pacing, bed capacity, and city art direction: [design notes](docs/design/owner-direction-notes.md).

Calendar pregnancy and human life stages: [lifecycle rules](docs/specs/lifecycle.md). Strictly 2D graphics direction based on the owner's concept: [art-director review](docs/art/mars-colony-redesign.md).

Two interior concepts per building are rendered in Higgsfield Seedream 5.0 Pro: [rendered concepts and references](docs/art/concepts/seedream-5-pro/README.md), [contact sheet](docs/art/concepts/seedream-5-pro/contact_sheet.jpg), and [12 reusable prompts](docs/art/interior-concepts-seedream-5-pro.md). The concepts await design review. Current decisions and remaining tasks: [continuation handoff](docs/design/continuation-handoff.md). Latest simulation measurements: [1,500-sol lifecycle baseline](docs/balance/lifecycle-standard-baseline.md).

The [ice-supply investigation](docs/balance/ice-supply-investigation.md) traces the founder-era delivery bottleneck without tuning gameplay. Replay it with `tools/ice_supply_probe.gd`; use `--control` to verify end-state and RNG equality.

- `sim/`: headless simulation (RefCounted classes, no drawing). Tunables are in `data/*.json`.
- `view/`: scenes that only read sim state. The `Sim` autoload (`view/sim_host.gd`) owns the `SimWorld` and steps it.
- `tests/`: headless tests.

A fresh clone has no `.godot/` (it is gitignored, as are `*.import`). Run the import once first, otherwise the `class_name` cache is empty and every script that uses `SimWorld`, `ArtLibrary` etc. fails to parse:

```
godot --headless --path station-zero --import                                         # once per clone, and after adding or renaming a class_name
godot --headless --path station-zero --script res://tests/run_tests.gd               # all tests (exit 1 on failure)
godot --headless --path station-zero --script res://tests/run_tests.gd -- --only test_clock
godot --headless --path station-zero --quit-after 30                                 # view smoke run
```
After adding or renaming a `class_name`, run `godot --headless --path station-zero --import` once so the class cache updates.

Art: `view/art_library.gd` (`ArtLibrary`) reads `assets/processed/manifest.json` and builds textures from the PNG bytes with mipmaps, so it does not depend on the import cache. Draw nodes must set `texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS`. An exported build must include `assets/processed/*` (non-resource files filter `*.json, *.png`).

Sprite world view (default scene): `view/world/` draws terrain, tunnels, buildings (doors, lights, offline dimming, construction) and the day/night tint from the view model (`view/model/`). Keys: WASD or arrows pan, wheel or +/- zoom, Home reset, F follow the selection, Esc deselect, M toggles the debug dot map. Screenshots: `tools/shots.sh [name ...]` (list from `data/art.json` via `python3 tools/shots_from_art.py`), output in `docs/shots/task-2/`.
