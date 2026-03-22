extends Area3D

@export var checkpoint_index: int = 0
@export var is_braking_zone: bool = false
@export var braking_strength: float = 0.5
@export var speed_limit: float = 35.0

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	if body.has_method("on_checkpoint_passed"):
		body.on_checkpoint_passed(self)
	
	if is_braking_zone:
		if body.has_method("set_ai_inputs"):
			pass
		elif body is VehicleBody3D:
			pass
