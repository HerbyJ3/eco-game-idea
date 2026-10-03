extends RefCounted
## Instantiates the HUD scene and checks its sections. The scene is bound by hand (setup) because
## nodes cannot become ready inside the runner's _init.


func test_hud_sections(t) -> void:
	var sim: Node = load("res://view/sim_host.gd").new()
	sim.world = SimWorld.new()
	var main: Control = (load("res://view/main.tscn") as PackedScene).instantiate()
	main.setup(sim)
	var before: float = sim.world.t
	for i in 3:
		main._process(0.2)
	var txt := ""
	for n in ["Clock", "Colony", "Power", "Site", "Beings", "Log", "Controls"]:
		txt += (main.get_node("Margin/HBox/VBox/" + n) as Label).text + "\n"
	for want in ["Year", "Sol", "Population", "births", "deaths", "Oxygen", "Food", "Ice",
			"Regolith", "/h", "Power:", "supply", "draw", "Buildings:", "Construction:",
			"Beings:", "idle", "sleep", "mining", "eva", "transit", "Log", "Speed"]:
		t.check(txt.contains(want), "HUD shows '%s'" % want)
	main.set_speed(100.0)
	t.eq(sim.speed, 100.0, "set_speed writes sim speed")
	main.toggle_pause()
	t.eq(sim.speed, 0.0, "pause")
	main.toggle_pause()
	t.eq(sim.speed, 100.0, "resume")
	t.eq(sim.world.t, before, "HUD does not advance the sim")
	main.free()
	sim.free()
