# Station Zero (Godot 4.5)

Design source: `../station-zero-handoff/HANDOFF.md`. Task plans: `docs/tasks/`. Specs: `docs/specs/`.

- `sim/`: headless simulation (RefCounted classes, no drawing). Tunables are in `data/*.json`.
- `view/`: scenes that only read sim state. The `Sim` autoload (`view/sim_host.gd`) owns the `SimWorld` and steps it.
- `tests/`: headless tests.

```
godot --headless --path station-zero --script res://tests/run_tests.gd               # all tests (exit 1 on failure)
godot --headless --path station-zero --script res://tests/run_tests.gd -- --only test_clock
godot --headless --path station-zero --quit-after 30                                 # view smoke run
```
After adding or renaming a `class_name`, run `godot --headless --path station-zero --import` once so the class cache updates.
