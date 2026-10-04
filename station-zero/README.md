# Station Zero (Godot 4.5)

Design source: `../station-zero-handoff/HANDOFF.md`. Task plans: `docs/tasks/`. Specs: `docs/specs/`.

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
