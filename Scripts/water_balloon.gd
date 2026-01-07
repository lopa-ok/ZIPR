extends RigidBody3D
class_name WaterBalloon

@export var lifetime := 4.0
@export var splash_force := 14.0

func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _integrate_forces(state):
	for i in range(state.get_contact_count()):
		var collider = state.get_contact_collider_object(i)
		if collider and collider.has_method("apply_water_hit"):
			collider.apply_water_hit(self)
			queue_free()
			return
