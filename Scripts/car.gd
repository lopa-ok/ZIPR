extends VehicleBody3D

var max_engine_force = 220.0
var max_steering = 0.9
var steering_speed = 2.5
var body_tilt = 25.0

var max_speed = 6.11
var speed_cap_epsilon = 0.5
var max_reverse_speed = 20000
var speed_steering_factor = 0.4

var camera_distance = 4.0
var camera_height = 1.8
var camera_smoothness = 20.0
var camera_rotation_smoothness = 5.0

var unflip_cooldown := 1.0
var unflip_timer := 0.0
var unflip_min_speed := 1.0
var unflip_tilt_threshold := 0.6

var unflip_hop_strength := 260.0
var unflip_roll_speed := 7.0
var unflip_roll_delay := 0.18

var unflip_roll_delay_timer := 0.0
var unflip_active := false
var unflip_time := 0.0
var unflip_max_duration := 1.5

var race_manager: Node = null

@onready var body_mesh = $Model/body
@onready var wheel_fl = $WheelFrontLeft
@onready var wheel_fr = $WheelFrontRight
@onready var wheel_rl = $WheelRearLeft
@onready var wheel_rr = $WheelRearRight
@onready var camera = $Camera3D

func _ready():
	if camera:
		camera.top_level = true
	race_manager = get_tree().get_first_node_in_group("race_manager")
	if race_manager and race_manager.has_method("register_car"):
		race_manager.register_car(self)
		print("[CAR] Registered with race manager")

func _physics_process(delta):
	var accel_input = Input.get_action_strength("Accelerate")
	var brake_input = Input.get_action_strength("Brake")
	var steering_input = Input.get_axis("SteerRight", "SteerLeft")
	
	# DEBUG: see if the input action ever fires
	if Input.is_action_just_pressed("teleport_to_checkpoint"):
		print("[CAR] teleport_to_checkpoint INPUT FIRED")
		_teleport_to_last_checkpoint()
		
	var forward_dir = -global_transform.basis.z
	var forward_speed = linear_velocity.dot(forward_dir)
	
	if forward_speed > max_speed:
		linear_velocity = forward_dir * max_speed
	elif forward_speed < -max_reverse_speed:
		linear_velocity = -forward_dir * max_reverse_speed
	
	var speed = linear_velocity.length()
	forward_speed = linear_velocity.dot(forward_dir)
	
	engine_force = 0.0
	brake = 0.0
	
	if accel_input > 0.0 and forward_speed < max_speed - speed_cap_epsilon:
		engine_force += accel_input * max_engine_force
	
	if brake_input > 0.0:
		var reverse_speed = -forward_speed
		if reverse_speed < max_reverse_speed - speed_cap_epsilon:
			engine_force -= brake_input * max_engine_force
	
	unflip_timer = max(unflip_timer - delta, 0.0)
	
	if not unflip_active and Input.is_action_just_pressed("Unflip") and unflip_timer == 0.0:
		if speed < unflip_min_speed:
			var up = global_transform.basis.y.normalized()
			var tilt = up.dot(Vector3.UP)
			if tilt < unflip_tilt_threshold:
				unflip_active = true
				unflip_time = 0.0
				unflip_timer = unflip_cooldown
				angular_velocity = Vector3.ZERO
				linear_velocity = Vector3.ZERO
				apply_central_impulse(Vector3.UP * unflip_hop_strength)
				unflip_roll_delay_timer = unflip_roll_delay
				print("[CAR] Unflip started, tilt=", tilt)
		else:
			print("[CAR] Unflip pressed but conditions not met, speed=", speed)
	
	if unflip_active:
		unflip_time += delta
		if unflip_time > unflip_max_duration:
			print("[CAR] Unflip timeout, snapping upright")
			_snap_upright()
			unflip_active = false
			angular_velocity = Vector3.ZERO
		else:
			if unflip_roll_delay_timer > 0.0:
				unflip_roll_delay_timer = max(unflip_roll_delay_timer - delta, 0.0)
			else:
				if linear_velocity.y < 0.0:
					linear_velocity.y = 0.0
				
				var cur_basis = global_transform.basis
				var right = cur_basis.x.normalized()
				var forward = -cur_basis.z.normalized()
				var up_vec = cur_basis.y.normalized()
				
				var target_up = Vector3.UP
				var rot_axis = up_vec.cross(target_up)
				var axis_len = rot_axis.length()
				if axis_len > 0.0001:
					rot_axis /= axis_len
					var dot_val = clamp(up_vec.dot(target_up), -1.0, 1.0)
					var angle = acos(dot_val)
					var max_step = unflip_roll_speed * delta
					var step = min(max_step, angle)
					var rot = Basis(rot_axis, step)
					up_vec = (rot * up_vec).normalized()
					right = (rot * right).normalized()
					forward = (rot * forward).normalized()
					global_transform.basis = Basis(right, up_vec, -forward)
					if up_vec.dot(Vector3.UP) > 0.995 or angle < 0.02:
						print("[CAR] Unflip finished, angle=", angle)
						_snap_upright()
						unflip_active = false
						angular_velocity = Vector3.ZERO
				else:
					print("[CAR] Unflip degenerate axis, snapping upright")
					_snap_upright()
					unflip_active = false
					angular_velocity = Vector3.ZERO
	
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

func _snap_upright():
	var flat_forward = -global_transform.basis.z
	flat_forward.y = 0.0
	if flat_forward.length() == 0.0:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var flat_right = flat_forward.cross(Vector3.UP).normalized()
	global_transform.basis = Basis(flat_right, Vector3.UP, -flat_forward)

func _teleport_to_last_checkpoint():
	if not race_manager:
		print("[CAR] Teleport failed: no race_manager")
		return
	if not race_manager.has_method("get_last_checkpoint_for_car"):
		print("[CAR] Teleport failed: race_manager has no get_last_checkpoint_for_car")
		return
	var cp = race_manager.get_last_checkpoint_for_car(self)
	if cp == null:
		print("[CAR] Teleport failed: no last checkpoint stored for this car")
		return
	var t = cp.global_transform
	global_transform.origin = t.origin
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	print("[CAR] Teleported to checkpoint", cp.checkpoint_index)

func on_checkpoint_passed(checkpoint: Node):
	print("[CAR] Checkpoint passed index=", checkpoint.checkpoint_index)
	if race_manager and race_manager.has_method("on_car_checkpoint"):
		race_manager.on_car_checkpoint(self, checkpoint)

func get_speed() -> float:
	return linear_velocity.length()
