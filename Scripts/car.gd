extends VehicleBody3D

var max_engine_force = 300.0
var max_brake_force = 15.0
var max_steering = 0.9
var steering_speed = 2.5
var body_tilt = 25.0

var max_speed = 50.0
var speed_steering_factor = 0.4

var camera_distance = 4.0
var camera_height = 1.8
var camera_smoothness = 20.0
var camera_rotation_smoothness = 5.0

@onready var body_mesh = $Model/body
@onready var wheel_fl = $WheelFrontLeft
@onready var wheel_fr = $WheelFrontRight
@onready var wheel_rl = $WheelRearLeft
@onready var wheel_rr = $WheelRearRight
@onready var camera = $Camera3D


func _ready():
	if camera:
		camera.top_level = true

func _physics_process(delta):
	var speed_input = Input.get_axis("Brake", "Accelerate")
	var steering_input = Input.get_axis("SteerRight", "SteerLeft")
	
	var speed = linear_velocity.length()
	
	if speed < max_speed:
		engine_force = speed_input * max_engine_force
	else:
		var speed_factor = clamp(1.0 - (speed - max_speed) / 10.0, 0.0, 1.0)
		engine_force = speed_input * max_engine_force * speed_factor
	
	if speed_input < 0:
		brake = abs(speed_input) * max_brake_force
	else:
		brake = 0.0
	
	var speed_ratio = clamp(speed / max_speed, 0.0, 1.0)
	var steering_multiplier = lerp(1.0, speed_steering_factor, speed_ratio)
	var target_steering = steering_input * max_steering * steering_multiplier
	
	steering = move_toward(steering, target_steering, delta * steering_speed)
	
	var t = -steering_input * speed / body_tilt
	body_mesh.rotation.z = lerp(body_mesh.rotation.z, t, 5.0 * delta)
	
	if camera:
		var target_pos = global_position - global_transform.basis.z * camera_distance + Vector3.UP * camera_height
		camera.global_position = camera.global_position.lerp(target_pos, camera_smoothness * delta)
		
		var look_target = global_position + Vector3.UP * 0.5
		var current_look = -camera.global_transform.basis.z
		var target_direction = (look_target - camera.global_position).normalized()
		var new_look = current_look.lerp(target_direction, camera_rotation_smoothness * delta).normalized()
		
		if new_look.length() > 0.1:
			camera.look_at(camera.global_position + new_look * 10.0, Vector3.UP)
