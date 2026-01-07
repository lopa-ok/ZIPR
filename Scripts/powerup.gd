extends Area3D
class_name Powerup

@export var icon_texture: Texture2D
@export var powerup_name: String = "Base"

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node):
	if body.has_method("pickup_powerup"):
		body.pickup_powerup(self)
		queue_free()
