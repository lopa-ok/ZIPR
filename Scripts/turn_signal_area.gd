extends Area3D

@export var turn_direction: String = "left"
@export var signal_type: String = "turn"
@export var is_left: bool = false
@export var turn_signal_sheet: Texture
@export var signal_duration: float = 1.5

func _ready():
	print("[TurnSignalArea] Ready, connecting body_entered")
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	print("[TurnSignalArea] body entered:", body)
	if body is VehicleBody3D and not body.is_ai_controlled:
		var ui_node = body.get_node_or_null("UI")
		print("[TurnSignalArea] UI node:", ui_node)
		if ui_node:
			print("[TurnSignalArea] Showing signal:", signal_type, is_left)
			ui_node.show_turn_signal(signal_type, is_left)
			call_deferred("_hide_signal", ui_node)
		else:
			print("[TurnSignalArea] UI node not found on car")

func _hide_signal(ui_node):
	print("[TurnSignalArea] Waiting to hide signal")
	await get_tree().create_timer(signal_duration).timeout
	if ui_node:
		print("[TurnSignalArea] Hiding signal")
		ui_node.hide_turn_signal()

func _on_body_exited(body):
	if body.has_method("is_ai_controlled") and not body.is_ai_controlled:
		var ui = get_tree().get_first_node_in_group("ui")
		if ui:
			ui.call("hide_turn_signal")
