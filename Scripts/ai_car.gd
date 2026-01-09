extends "res://Scripts/car.gd"

var ai_max_speed: float = 50.0
var ai_accel_force: float = 120.0
var ai_brake_force: float = 180.0
var ai_steer_speed: float = 1.2
var ai_max_steering: float = 0.7

func _ready() -> void:
	is_ai_controlled = true
	super._ready()

func set_ai_inputs(accel: bool, brake: bool, steer: float, handbrake: bool) -> void:
	ai_accel = accel
	ai_brake = brake
	ai_steer = clamp(steer, -1.0, 1.0)
	ai_handbrake = handbrake

func _physics_process(delta: float) -> void:

	if not is_ai_controlled:
		super._physics_process(delta)
		return

	var forward_dir := -global_transform.basis.z
	var speed := linear_velocity.dot(forward_dir)
	if ai_accel and speed > ai_max_speed:
		ai_accel = false
	
	ai_steer = clamp(ai_steer, -1.0, 1.0) * ai_max_steering

	super._physics_process(delta)
