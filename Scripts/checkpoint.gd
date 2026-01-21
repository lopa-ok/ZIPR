extends Area3D

@export var checkpoint_index: int = 0
@export var is_braking_zone: bool = false
@export var braking_strength: float = 0.5 # 0.0 to 1.0, where 1.0 is full brakes
@export var speed_limit: float = 35.0 # Speed limit in km/h for this zone

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	if body.has_method("on_checkpoint_passed"):
		body.on_checkpoint_passed(self)
	
	if is_braking_zone:
		if body.has_method("set_ai_inputs"):
			# For AI cars
			# We can't easily force braking on the AI driver from here without
			# modifying the AI driver or adding a temporary override.
			# However, if we're marking waypoints/checkpoints as braking zones,
			# the AI driver should probably read this property.
			pass
		elif body is VehicleBody3D:
			# For player cars or simple physics manipulation
			# Apply a braking impulse or modify velocity?
			# Modifying velocity directly is jerky.
			# Let's see if the user wants this for AI or Player.
			pass
