extends VehicleBody3D

var drift_factor: float = 0.95
var drift_factor_handbrake: float = 0.5

var current_powerup: String = ""
var has_powerup: bool = false

var boost_timer: float = 0.0
var boost_duration: float = 2.0
var boost_multiplier: float = 2.5

var max_engine_force: float = 220.0
var max_steering: float = 0.9
var steering_speed: float = 2.5
var body_tilt: float = 25.0

var max_speed: float = 65.0
var speed_cap_epsilon: float = 0.5
var max_reverse_speed: float = 10.0
var speed_steering_factor: float = 0.4

var camera_distance: float = 4.0
var camera_height: float = 1.8
var camera_smoothness: float = 20.0
var camera_rotation_smoothness: float = 5.0

var unflip_cooldown: float = 1.0
var unflip_timer: float = 0.0
var unflip_min_speed: float = 1.0
var unflip_tilt_threshold: float = 0.6

var unflip_hop_strength: float = 260.0
var unflip_roll_speed: float = 7.0
var unflip_roll_delay: float = 0.18

var unflip_roll_delay_timer: float = 0.0
var unflip_active: bool = false
var unflip_time: float = 0.0
var unflip_max_duration: float = 1.5

var race_manager: Node = null

var drift_friction := 0.5
var drift_front_friction := 1.5
var normal_friction := 4.0
var normal_front_friction := 4.0
var rear_friction := normal_friction
var front_friction := normal_front_friction
var friction_lerp_speed := 8.0
var drift_kick_strength := 8.0
var drift_kick_cooldown := 0.2
var drift_kick_timer := 0.0

@onready var body_mesh = $Model/body
@onready var wheel_fl = $WheelFrontLeft
@onready var wheel_fr = $WheelFrontRight
@onready var wheel_rl = $WheelRearLeft
@onready var wheel_rr = $WheelRearRight
@onready var camera = $Camera3D

func _ready() -> void:
	if camera:
		camera.top_level = true
	race_manager = get_tree().get_first_node_in_group("race_manager")
	if race_manager and race_manager.has_method("register_car"):
		race_manager.register_car(self)

func _physics_process(delta: float) -> void:
	var accel_input := Input.is_action_pressed("Accelerate")
	var brake_input := Input.is_action_pressed("Brake")
	var steer_input := Input.get_axis("SteerRight", "SteerLeft")
	var handbrake_input := Input.is_action_pressed("Handbrake")

	var engine := 0.0
	var brake_force := 0.0
	var max_fwd := max_engine_force
	var max_rev := max_engine_force * 0.5

	var forward_dir := -global_transform.basis.z
	var speed := linear_velocity.dot(forward_dir)

	if accel_input and speed < max_speed:
		engine = max_fwd
	elif brake_input:
		if speed > 1.0:
			brake_force = max_engine_force
		else:
			engine = -max_rev
	else:
		engine = 0.0
		brake_force = 0.0

	if boost_timer > 0.0:
		boost_timer -= delta
		if boost_timer > 0.0:
			engine *= boost_multiplier

	wheel_rl.engine_force = engine
	wheel_rr.engine_force = engine
	wheel_fl.engine_force = 0.0
	wheel_fr.engine_force = 0.0

	wheel_rl.brake = brake_force
	wheel_rr.brake = brake_force
	wheel_fl.brake = brake_force
	wheel_fr.brake = brake_force

	var steer_val := steer_input * max_steering
	if abs(speed) > 1.0:
		steer_val *= clamp(1.0 - abs(speed) / max_speed, speed_steering_factor, 1.0)
	if handbrake_input:
		steer_val *= 1.5
	wheel_fl.steering = steer_val
	wheel_fr.steering = steer_val

	var drifting := handbrake_input
	var steer_abs: float = abs(steer_input)
	var velocity_dir: float = sign(linear_velocity.dot(forward_dir))
	var steer_dir: float = sign(steer_input)
	var is_counter_steering: bool = (steer_dir != 0.0 and steer_dir != velocity_dir)

	var min_drift_friction: float = 1.2
	var steer_friction: float = lerp(drift_friction, normal_friction, 1.0 - steer_abs)
	if drifting and is_counter_steering:
		steer_friction = lerp(steer_friction, normal_friction, 0.7)
	steer_friction = max(steer_friction, min_drift_friction)

	var steer_front_friction: float = lerp(drift_front_friction, normal_front_friction, 1.0 - steer_abs)
	var target_rear_friction: float = steer_friction if drifting else normal_friction
	var target_front_friction: float = steer_front_friction if drifting else normal_front_friction

	rear_friction = lerp(rear_friction, target_rear_friction, clamp(friction_lerp_speed * delta, 0, 1))
	front_friction = lerp(front_friction, target_front_friction, clamp(friction_lerp_speed * delta, 0, 1))
	wheel_rl.wheel_friction_slip = rear_friction
	wheel_rr.wheel_friction_slip = rear_friction
	wheel_fl.wheel_friction_slip = front_friction
	wheel_fr.wheel_friction_slip = front_friction

	if drifting and drift_kick_timer <= 0.0 and abs(speed) > 2.0:
		var right: Vector3 = global_transform.basis.x
		var steer_sign: float = sign(steer_input) if steer_input != 0.0 else 1.0
		var drift_dir: Vector3 = right * steer_sign
		var drift_kick: float = drift_kick_strength * steer_abs
		if is_counter_steering:
			drift_kick *= 0.3
		apply_impulse(Vector3.ZERO, drift_dir * drift_kick)
		drift_kick_timer = drift_kick_cooldown
	elif not drifting:
		drift_kick_timer = 0.0
	if drift_kick_timer > 0.0:
		drift_kick_timer -= delta

	var t: float = -steer_input * speed / body_tilt
	body_mesh.rotation.z = lerp(body_mesh.rotation.z, t, 5.0 * delta)
	if camera:
		var target_pos: Vector3 = global_position - global_transform.basis.z * camera_distance + Vector3.UP * camera_height
		camera.global_position = camera.global_position.lerp(target_pos, camera_smoothness * delta)
		var look_target: Vector3 = global_position + Vector3.UP * 0.5
		var current_look: Vector3 = -camera.global_transform.basis.z
		var target_direction: Vector3 = (look_target - camera.global_position).normalized()
		var new_look: Vector3 = current_look.lerp(target_direction, camera_rotation_smoothness * delta).normalized()
		if new_look.length() > 0.1:
			camera.look_at(camera.global_position + new_look * 10.0, Vector3.UP)

	if Input.is_action_just_pressed("Usepowerup") and has_powerup:
		_use_current_powerup()

	unflip_timer = max(unflip_timer - delta, 0.0)
	if not unflip_active and Input.is_action_just_pressed("Unflip") and unflip_timer == 0.0:
		if speed < unflip_min_speed:
			var up: Vector3 = global_transform.basis.y.normalized()
			var tilt: float = up.dot(Vector3.UP)
			if tilt < unflip_tilt_threshold:
				unflip_active = true
				unflip_time = 0.0
				unflip_timer = unflip_cooldown
				angular_velocity = Vector3.ZERO
				linear_velocity = Vector3.ZERO
				apply_central_impulse(Vector3.UP * unflip_hop_strength)
				unflip_roll_delay_timer = unflip_roll_delay
	if unflip_active:
		unflip_time += delta
		if unflip_time > unflip_max_duration:
			_snap_upright()
			unflip_active = false
			angular_velocity = Vector3.ZERO
		else:
			if unflip_roll_delay_timer > 0.0:
				unflip_roll_delay_timer = max(unflip_roll_delay_timer - delta, 0.0)
			else:
				if linear_velocity.y < 0.0:
					linear_velocity.y = 0.0
				var cur_basis: Basis = global_transform.basis
				var right: Vector3 = cur_basis.x.normalized()
				var forward: Vector3 = -cur_basis.z.normalized()
				var up_vec: Vector3 = cur_basis.y.normalized()
				var target_up: Vector3 = Vector3.UP
				var rot_axis: Vector3 = up_vec.cross(target_up)
				var axis_len: float = rot_axis.length()
				if axis_len > 0.0001:
					rot_axis /= axis_len
					var dot_val: float = clamp(up_vec.dot(target_up), -1.0, 1.0)
					var angle: float = acos(dot_val)
					var max_step: float = unflip_roll_speed * delta
					var step: float = min(max_step, angle)
					var rot: Basis = Basis(rot_axis, step)
					up_vec = (rot * up_vec).normalized()
					right = (rot * right).normalized()
					forward = (rot * forward).normalized()
					global_transform.basis = Basis(right, up_vec, -forward)
					if up_vec.dot(Vector3.UP) > 0.995 or angle < 0.02:
						_snap_upright()
						unflip_active = false
						angular_velocity = Vector3.ZERO
				else:
					_snap_upright()
					unflip_active = false
					angular_velocity = Vector3.ZERO

func _snap_upright() -> void:
	var flat_forward: Vector3 = -global_transform.basis.z
	flat_forward.y = 0.0
	if flat_forward.length() == 0.0:
		flat_forward = Vector3.FORWARD
	flat_forward = flat_forward.normalized()
	var flat_right: Vector3 = flat_forward.cross(Vector3.UP).normalized()
	global_transform.basis = Basis(flat_right, Vector3.UP, -flat_forward)

func _teleport_to_last_checkpoint() -> void:
	if not race_manager:
		return
	if not race_manager.has_method("get_last_checkpoint_for_car"):
		return
	var cp: Node3D = race_manager.get_last_checkpoint_for_car(self)
	if cp == null:
		return
	var t: Transform3D = cp.global_transform
	global_transform.origin = t.origin
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func on_checkpoint_passed(checkpoint: Node) -> void:
	if race_manager and race_manager.has_method("on_car_checkpoint"):
		race_manager.on_car_checkpoint(self, checkpoint)

func get_speed() -> float:
	return linear_velocity.length()

func pickup_powerup(powerup: Powerup) -> void:
	current_powerup = powerup.powerup_name
	has_powerup = true

func has_powerup_func() -> bool:
	return has_powerup

func _use_current_powerup() -> void:
	match current_powerup:
		"speed_boost":
			_apply_speed_boost()
		"oil":
			_drop_oil()
		"water_balloon":
			_shoot_water_balloon()
		_:
			pass
	has_powerup = false
	current_powerup = ""

func _apply_speed_boost() -> void:
	boost_timer = boost_duration

func _drop_oil() -> void:
	var oil_scene: PackedScene = load("res://Scenes/OilSlick.tscn")
	var oil = oil_scene.instantiate()
	get_tree().current_scene.add_child(oil)
	oil.global_position = global_transform.origin + (-global_transform.basis.z * 1.5)
	oil.global_rotation = global_transform.basis.get_euler()

func apply_oil_slip(oil: OilSlick) -> void:
	var right_dir: Vector3 = global_transform.basis.x
	var random_dir: Vector3 = right_dir.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	linear_velocity += random_dir * oil.slip_force

func _shoot_water_balloon() -> void:
	var scene: PackedScene = load("res://Scenes/WaterBalloon.tscn")
	var balloon = scene.instantiate()
	get_tree().current_scene.add_child(balloon)
	balloon.global_position = global_transform.origin + (global_transform.basis.z * 1.5) + Vector3.UP * 0.5
	balloon.global_rotation = global_transform.basis.get_euler()
	var forward_dir: Vector3 = global_transform.basis.z
	balloon.linear_velocity = linear_velocity + forward_dir * 20.0

func apply_water_hit(balloon: WaterBalloon) -> void:
	angular_velocity += Vector3.UP * balloon.splash_force
	linear_velocity *= 0.6
