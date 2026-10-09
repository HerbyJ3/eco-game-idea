extends RefCounted
## Balance target 9 (spec sections 13, 15): the same seed and sols give an identical table hash.
## Also covers stats.window / SimWorld.reset_window (spec section 16, added in step 10).

const SOLS := 10
const EVERY := 5


func test_same_seed_same_hash(t) -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var a: Dictionary = lib.run(42, SOLS, {}, EVERY)
	var b: Dictionary = lib.run(42, SOLS, {}, EVERY)
	t.eq(a.table_hash, b.table_hash, "table hash, seed 42")
	t.eq("\n".join(a.lines), "\n".join(b.lines), "full output, seed 42")
	t.check(a.lines.size() > 8, "table has rows")
	var c: Dictionary = lib.run(7, SOLS, {}, EVERY)
	t.check(a.table_hash != c.table_hash, "seed 7 differs from seed 42")


func test_param_override_applies_and_restores(t) -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var before = SimData.colony().birth.cooldown_sols
	var r: Dictionary = lib.run(42, 2, {"colony.birth.cooldown_sols": 3}, 1)
	t.check("cooldown_sols=3" in r.lines[0], "header lists the override")
	t.eq(SimData.colony().birth.cooldown_sols, before, "override restored")
	var bad: Dictionary = lib.run(42, 1, {"colony.nope.x": 1}, 1)
	t.check(bad.lines[0].begins_with("PARAM ERROR"), "unknown key reported")


func test_stats_window_reset(t) -> void:
	var w := SimWorld.new(42)
	for i in 100:
		w.step()
	var win: Dictionary = w.stats.window
	t.eq(int(win.step_count), 100, "window counts steps")
	t.eq(int(w.stats.step_count), 100, "run-wide counts steps")
	t.check(win.min_pop != null and int(win.min_pop) == 7, "min_pop tracked")
	t.eq(w.stats.pop_by_sol[0], 7, "pop_by_sol[0] is the founders")
	w.reset_window()
	t.eq(int(w.stats.window.step_count), 0, "window reset")
	t.eq(w.stats.window.min_pop, null, "window minima reset to null")
	t.eq(int(w.stats.step_count), 100, "run-wide kept")
	w.step()
	t.eq(int(w.stats.window.step_count), 1, "window counts again")
	t.eq(int(w.stats.step_count), 101, "run-wide continues")
