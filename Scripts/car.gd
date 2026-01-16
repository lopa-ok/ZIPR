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

@export_group("Camera Settings")
@export var camera_distance: float = 4.0
@export var camera_height: float = 1.8
@export var camera_smoothness: float = 20.0
@export var camera_rotation_smoothness: float = 5.0

var unflip_cooldown: float = 1.0
var unflip_timer: float = 0.0
var unflip_min_speed: float = 1.0
var unflip_tilt_threshold: float = 0.6

@export var is_ai_controlled: bool = false
@export var car_name: String = "Car"
@export var car_id: int = -1

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

# Removed duplicate is_ai_controlled declaration
var ai_accel: bool = false
var ai_brake: bool = false
var ai_steer: float = 0.0
var ai_handbrake: bool = false

var reset_height_threshold: float = -20.0 

@onready var body_mesh = $Model/body
@onready var wheel_fl = $WheelFrontLeft
@onready var wheel_fr = $WheelFrontRight
@onready var wheel_rl = $WheelRearLeft
@onready var wheel_rr = $WheelRearRight
@onready var camera = $Camera3D
@onready var model_container = $Model

var engine_sound_player: AudioStreamPlayer3D

func _ready() -> void:
	sleeping = false
	can_sleep = false
	randomize()
	call_deferred("_initialize_car")

func _initialize_car() -> void:
	if not is_ai_controlled and (name.to_lower().contains("ai")):
		is_ai_controlled = true
	
	if is_ai_controlled and camera:
		camera.queue_free()
		camera = null
	elif camera:
		camera.top_level = true
		camera.make_current()

	race_manager = get_tree().get_first_node_in_group("race_manager")
	if race_manager and race_manager.has_method("register_car"):
		race_manager.register_car(self)
	_apply_car_stats()

func _apply_car_stats() -> void:
	var active_car_id = car_id 
	if active_car_id == -1:
		if is_ai_controlled:
			active_car_id = Global.get_unique_ai_car_id()
			car_id = active_car_id
			print("[DEBUG] AI Car ", name, " assigned random car ID: ", active_car_id)
		else:
			active_car_id = Global.selected_car_id
			car_id = active_car_id
	
	if not is_ai_controlled and active_car_id != -1:
		Global.selected_car_id = active_car_id

	print("[DEBUG] applying car stats for car: ", name, " using ID: ", active_car_id)
	var stats = Global.car_stats[active_car_id]
	max_engine_force = stats["max_engine_force"]
	max_steering = stats["max_steering"]
	steering_speed = stats["steering_speed"]
	max_speed = stats["max_speed"]
	drift_factor = stats["drift_factor"]
	body_tilt = stats["body_tilt"]

	if stats.has("mesh_scene") and stats["mesh_scene"] != "":
		if scene_file_path != stats["mesh_scene"]:
			_update_car_mesh(stats["mesh_scene"])

func _update_car_mesh(scene_path: String) -> void:
	var scene = load(scene_path)
	if scene:
		for child in model_container.get_children():
			child.queue_free()
		
		var new_body = scene.instantiate()
		new_body.set_script(null)
		new_body.set_process(false)
		new_body.set_physics_process(false)

		if new_body is CollisionObject3D:
			new_body.collision_layer = 0
			new_body.collision_mask = 0
		
		var nested_bodies = new_body.find_children("*", "CollisionObject3D", true, false)
		for nb in nested_bodies:
			nb.collision_layer = 0
			nb.collision_mask = 0

		if new_body is RigidBody3D:
			new_body.freeze = true
			new_body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			new_body.collision_layer = 0
			new_body.collision_mask = 0

		model_container.add_child(new_body)
		
		var embedded_cameras = new_body.find_children("*", "Camera3D", true, false)
		for cam in embedded_cameras:
			cam.queue_free()
		
		for child in get_children():
			if child.is_in_group("imported_collision"):
				child.queue_free()
		
		var default_col = get_node_or_null("CollisionShape3D")
		if default_col:
			default_col.disabled = true

		var new_shapes = new_body.find_children("*", "CollisionShape3D", true, false)
		new_shapes.append_array(new_body.find_children("*", "CollisionPolygon3D", true, false))
		
		if new_shapes.is_empty():
			print("[DEBUG] WARNING: No collision shapes found in imported scene!")
			
		for child in new_shapes:
			child.reparent(self, true)
			if "disabled" in child:
				child.disabled = false
			child.add_to_group("imported_collision")

		var wheel_map = {
			"WheelFrontLeft": wheel_fl,
			"WheelFrontRight": wheel_fr,
			"WheelRearLeft": wheel_rl,
			"WheelRearRight": wheel_rr
		}
		
		var new_wheels = new_body.find_children("*", "VehicleWheel3D", true, false)
		
		if new_wheels.is_empty():
			print("[DEBUG] WARNING: No VehicleWheel3D nodes found in imported scene. Wheels might be misaligned!")

		for child in new_wheels:
			var matched_key = ""
			if wheel_map.has(child.name):
				matched_key = child.name
			else:
				var cname = child.name.to_lower()
				if ("front" in cname or "f_" in cname) and ("left" in cname or "_l" in cname):
					matched_key = "WheelFrontLeft"
				elif ("front" in cname or "f_" in cname) and ("right" in cname or "_r" in cname):
					matched_key = "WheelFrontRight"
				elif ("rear" in cname or "back" in cname or "r_" in cname) and ("left" in cname or "_l" in cname):
					matched_key = "WheelRearLeft"
				elif ("rear" in cname or "back" in cname or "r_" in cname) and ("right" in cname or "_r" in cname):
					matched_key = "WheelRearRight"

			if matched_key != "" and wheel_map.has(matched_key):
				var real_wheel = wheel_map[matched_key]
				if real_wheel:
					var target_transform = model_container.transform * new_body.transform * child.transform
					
					if child.get_parent() != new_body:
						var path_transform = new_body.global_transform.affine_inverse() * child.global_transform
						target_transform = model_container.transform * path_transform
					
					real_wheel.position = target_transform.origin
					real_wheel.rotation = Vector3.ZERO
					
					real_wheel.wheel_radius = child.wheel_radius if child.wheel_radius > 0.05 else 0.3
					real_wheel.suspension_travel = child.suspension_travel if child.suspension_travel > 0.01 else 0.2
					real_wheel.suspension_stiffness = child.suspension_stiffness
					real_wheel.damping_compression = child.damping_compression
					real_wheel.damping_relaxation = child.damping_relaxation
					
					real_wheel.wheel_friction_slip = child.wheel_friction_slip
					real_wheel.wheel_roll_influence = child.wheel_roll_influence
					
					if "rear" in matched_key.to_lower():
						real_wheel.use_as_traction = true
						real_wheel.use_as_steering = false
					elif "front" in matched_key.to_lower():
						real_wheel.use_as_traction = false
						real_wheel.use_as_steering = true
					else:
						real_wheel.use_as_traction = child.use_as_traction
						real_wheel.use_as_steering = child.use_as_steering
					
					var w_name_lower = child.name.to_lower()
					if "rear" in w_name_lower or "back" in w_name_lower:
						normal_friction = child.wheel_friction_slip
						rear_friction = normal_friction
					elif "front" in w_name_lower:
						normal_front_friction = child.wheel_friction_slip
						front_friction = normal_front_friction

					for old_visual in real_wheel.get_children():
						old_visual.queue_free()

					child.reparent(real_wheel, true)
			else:
				print("[DEBUG] -> WARNING: Wheel ", child.name, " could not be matched to any physical wheel!")

		var potential_body = new_body.find_child("body")
		if potential_body:
			body_mesh = potential_body
		else:
			body_mesh = new_body
			
		sleeping = false

func set_ai_inputs(accel: bool, is_braking: bool, steer: float, handbrake: bool) -> void:
	ai_accel = accel
	ai_brake = is_braking
	ai_steer = clamp(steer, -1.0, 1.0)
	ai_handbrake = handbrake

func _physics_process(delta: float) -> void:
	if is_ai_controlled and camera:
		camera.queue_free()
		camera = null
	
	if is_ai_controlled and ai_accel and linear_velocity.length() < 0.1:
		if Engine.get_process_frames() % 120 == 0:
			print("[AI STUCK] Car ", name, " is trying to accelerate but speed is 0. Check brake/handbrake or physics collision.")

	if global_position.y < reset_height_threshold:
		_teleport_to_last_checkpoint()

	var accel_input := ai_accel if is_ai_controlled else Input.is_action_pressed("Accelerate")
	var brake_input := ai_brake if is_ai_controlled else Input.is_action_pressed("Brake")
	var steer_input := ai_steer if is_ai_controlled else Input.get_axis("SteerRight", "SteerLeft")
	var handbrake_input := ai_handbrake if is_ai_controlled else Input.is_action_pressed("Handbrake")

	# Block input if race hasn't started
	if race_manager and "race_started" in race_manager and not race_manager.race_started:
		accel_input = false
		brake_input = true # Hold brake
		handbrake_input = true
		steer_input = 0.0

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
	wheel_fl.brake = 0.0
	wheel_fr.brake = 0.0

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
	
	# Engine Sound Logic
	_update_engine_sound()

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
		# Only play for player unless we want a cacophony
		if not is_ai_controlled:
			# We don't have a direct reference to SoundManager here without autoload
			# But we added it to AutoLoad so it should be available globally
			pass 

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

func _update_engine_sound() -> void:
	if not engine_sound_player:
		engine_sound_player = AudioStreamPlayer3D.new()
		add_child(engine_sound_player)
		# Load engine sound (adjust path as needed)
		var stream = load("res://resources/models/Music/EngineSound.wav")
		if stream:
			engine_sound_player.stream = stream
			engine_sound_player.unit_size = 10.0
			engine_sound_player.max_db = 0.0
			engine_sound_player.autoplay = true
			engine_sound_player.play()
		else:
			print("Failed to load engine sound")
			return

	if not engine_sound_player.playing:
		engine_sound_player.play()

	var speed = linear_velocity.length()
	var pitch = clamp(0.5 + (speed / max_speed) * 1.5, 0.5, 2.5)
	engine_sound_player.pitch_scale = lerp(engine_sound_player.pitch_scale, pitch, 0.1)
