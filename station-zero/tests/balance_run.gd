extends SceneTree
## Balance run. godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols N [--param path=value ...]
## [--player attentive [--cadence <sols>]] runs tools/attentive_player.gd as a scripted player (influence-powers.md
## section 5); --cadence is how often it glances at the colony, in sols (default 1).
## Exits 0 when every target passes, 1 otherwise (spec section 15); the verdicts are in the output. See tests/balance_lib.gd.


func _init() -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var args := OS.get_cmdline_user_args()
	var seed_in := int(SimData.sim().default_seed)
	var sols := 300
	var every := 30
	var params := {}
	var tier := ""
	var player: RefCounted = null
	var cadence := -1.0
	var bad_args := false
	var out_dir := ""
	var i := 0
	while i < args.size():
		match args[i]:
			"--seed":
				i += 1
				seed_in = int(args[i])
			"--sols":
				i += 1
				sols = int(args[i])
			"--every":
				i += 1
				every = int(args[i])
			"--player":
				i += 1
				player = load("res://tools/%s_player.gd" % args[i]).new()
			"--cadence":
				i += 1
				cadence = float(args[i])
			"--tier":
				i += 1
				tier = args[i]
			"--out":
				i += 1
				out_dir = args[i]
			"--param":
				i += 1
				var kv: PackedStringArray = args[i].split("=", true, 1)
				if kv.size() == 2:
					params[kv[0]] = lib.parse_value(kv[1])
				else:
					print("PARAM ERROR: expected path=value, got %s" % args[i])
					bad_args = true
		i += 1
	if bad_args:
		print("ABORTED: nothing simulated because an argument was rejected")
		quit(2)
		return
	if player != null and cadence > 0.0:
		player.set("cadence", cadence)
	if player != null:
		player.set("sample_every", every)
	var res: Dictionary = lib.run(seed_in, sols, params, every, tier, player)
	var all_pass := true
	for line in res.lines:
		print(line)
	if res.get("error", false):
		quit(2)
		return
	if player != null:
		for line: String in player.call("report", res.world):
			print(line)
	if tier == "std":
		# Spec section 8: exit 1 on any L1 or L4 failure; every other verdict is read from the output.
		for v: Dictionary in res.std.verdicts:
			if v.id in ["L1", "L4"] and v.verdict == "FAIL":
				all_pass = false
		if out_dir != "":
			DirAccess.make_dir_recursive_absolute(out_dir)
			var f := FileAccess.open("%s/std_seed_%d.json" % [out_dir, seed_in], FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(res.std.data))
				f.close()
		quit(0 if all_pass else 1)
		return
	for v: Dictionary in res.verdicts:
		if v.verdict == "FAIL":
			all_pass = false
	quit(0 if all_pass else 1)
