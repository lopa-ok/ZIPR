extends Area3D
class_name OilSlick

@export var lifetime := 8.0
@export var slip_force := 12.0

func _ready():
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node):
	if body is VehicleBody3D and body.has_method("apply_oil_slip"):
		body.apply_oil_slip(self)
