extends Control
## Task 0 view: shows Mars time and the founders' visible personalities.
## Reads sim state only; never shows the hidden chart.

@onready var _clock_label: Label = $Margin/VBox/Clock
@onready var _founders_label: Label = $Margin/VBox/Founders

func _ready() -> void:
	var lines: PackedStringArray = []
	for f: Dictionary in Sim.world.founders:
		lines.append("%s  (%s)" % [f.persona.description, f.persona.role])
	_founders_label.text = "Founders\n" + "\n".join(lines)
	print(_founders_label.text)


func _process(_delta: float) -> void:
	var w: SimWorld = Sim.world
	var c := w.clock
	var hour := c.mars_hour(w.t)
	_clock_label.text = "%s  ·  Year %d, Sol %d  ·  %02d:%02d  ·  %s" % [
		c.site_name, c.year_index(w.t), c.sol_index(w.t),
		int(hour), int(fmod(hour, 1.0) * 60.0), c.season(w.t)]
