extends Area3D

@export var turn_direction: String = "left" # "left" or "right"

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	if body.has_method("is_ai_controlled") and not body.is_ai_controlled:
		var ui = get_tree().get_first_node_in_group("ui")
		if ui:
			ui.call("show_turn_signal", turn_direction)

func _on_body_exited(body):
	if body.has_method("is_ai_controlled") and not body.is_ai_controlled:
		var ui = get_tree().get_first_node_in_group("ui")
		if ui:
			ui.call("hide_turn_signal")
