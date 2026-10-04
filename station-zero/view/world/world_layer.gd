extends Node2D
## One draw layer of the world view. It owns no logic: _draw hands the canvas to the view, which asks the drawer of
## this layer to paint from the model. Layers are siblings, back to front, in the order of spec 6.

var view: Node
var layer_id := ""


func _draw() -> void:
	if view != null:
		view.draw_layer(self, layer_id)
