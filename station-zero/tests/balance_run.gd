extends SceneTree
## Balance run. godot --headless --path station-zero --script res://tests/balance_run.gd -- --seed N --sols N [--param path=value ...]
## Exits 0 when every target passes, 1 otherwise (spec section 15); the verdicts are in the output. See tests/balance_lib.gd.


func _init() -> void:
	var lib: GDScript = load("res://tests/balance_lib.gd")
	var args := OS.get_cmdline_user_args()
	var seed_in := int(SimData.sim().default_seed)
	var sols := 300
	var every := 30
	var params := {}
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
			"--param":
				i += 1
				var kv: PackedStringArray = args[i].split("=", true, 1)
				if kv.size() == 2:
					params[kv[0]] = lib.parse_value(kv[1])
				else:
					print("PARAM ERROR: expected path=value, got %s" % args[i])
		i += 1
	var res: Dictionary = lib.run(seed_in, sols, params, every)
	var all_pass := true
	for line in res.lines:
		print(line)
	for v: Dictionary in res.verdicts:
		if v.verdict == "FAIL":
			all_pass = false
	quit(0 if all_pass else 1)
