extends Node
## Autoload that owns the simulation and steps it from real time.
## The view reads `world`; it never writes sim state directly.

var world: SimWorld
var speed := 1.0
var _hours_per_second: float


func _ready() -> void:
	world = SimWorld.new()
	_hours_per_second = 1.0 / float(SimData.sim().real_seconds_per_hour_at_1x)


func _process(delta: float) -> void:
	world.advance(delta * speed * _hours_per_second)
