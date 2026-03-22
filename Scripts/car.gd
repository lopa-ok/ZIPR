extends VehicleBody3D

@export_group("Car Specs")
@export var car_name: String = "Car"
@export var car_id: int = -1
@export var max_speed: float = 65.0
@export var max_reverse_speed: float = 20.0
@export var max_engine_force: float = 220.0
@export var max_steering: float = 0.9
@export var steering_speed: float = 2.5
@export var body_tilt: float = 25.0

@export_group("Drifting & Physics")
@export var drift_factor: float = 0.95
@export var drift_factor_handbrake: float = 0.5
@export var speed_steering_factor: float = 0.4
@export var reset_height_threshold: float = -20.0 

@export_group("Camera Settings")
@export var camera_distance: float = 4.0
@export var camera_height: float = 1.8
@export var camera_smoothness: float = 20.0
@export var camera_rotation_smoothness: float = 5.0

@export_group("AI Settings")
@export var is_ai_controlled: bool = false

var current_powerup: String = ""
var has_powerup: bool = false
var is_reversing_action: bool = false

var boost_timer: float = 0.0
var boost_duration: float = 2.0
var boost_multiplier: float = 2.5

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

var drift_friction := 1.9
var drift_front_friction := 2.5
var normal_friction := 4.5
var normal_front_friction := 4.5
var rear_friction := normal_friction
var front_friction := normal_front_friction
var friction_lerp_speed := 6.0
var drift_torque_assist := 100.0

var ai_accel: bool = false
var ai_brake: bool = false
var ai_steer: float = 0.0
var ai_handbrake: bool = false

var race_manager: Node = null
@onready var body_mesh = $Model/body
@onready var wheel_fl = $WheelFrontLeft
@onready var wheel_fr = $WheelFrontRight
@onready var wheel_rl = $WheelRearLeft
@onready var wheel_rr = $WheelRearRight
@onready var camera = $Camera3D
@onready var model_container = $Model

var engine_sound_player: AudioStreamPlayer3D
var engine_stream: AudioStream = preload("res://resources/models/Music/EngineSound.wav")

var oil_slip_timer: float = 0.0
var oil_slip_duration: float = 2.5
var oil_slip_friction: float = 0.6

func _ready() -> void:
	print("Car ready:", name, "is_ai_controlled:", is_ai_controlled)
	sleeping = false
	can_sleep = false
	randomize()
	_setup_audio()
	call_deferred("_initialize_car")

func _setup_audio() -> void:
	engine_sound_player = AudioStreamPlayer3D.new()
	add_child(engine_sound_player)
	if engine_stream:
		engine_sound_player.stream = engine_stream
		engine_sound_player.unit_size = 10.0
		engine_sound_player.max_db = 0.0
		engine_sound_player.autoplay = true
		engine_sound_player.play()

func _initialize_car() -> void:
	if not is_ai_controlled and (name.to_lower().contains("ai")):
		is_ai_controlled = true
	
	if is_ai_controlled:
		if camera: 
			camera.queue_free()
			camera = null
	elif camera:
		camera.top_level = true
		camera.make_current()

	race_manager = get_tree().get_first_node_in_group("race_manager")
	if race_manager and race_manager.has_method("register_car"):
		race_manager.register_car(self)

	if not is_ai_controlled:
		if Global.current_game_mode == Global.GameMode.SUMO:
			var sumo_ui = load("res://Scripts/sumo_ui.gd")
			if sumo_ui:
				var ui_layer := CanvasLayer.new()
				ui_layer.set_script(sumo_ui)
				ui_layer.name = "SumoUI"
				add_child(ui_layer)
		
	_apply_car_stats()

func _apply_car_stats() -> void:
	var active_car_id = car_id 
	if active_car_id == -1:
		if is_ai_controlled:
			active_car_id = Global.get_unique_ai_car_id()
			car_id = active_car_id
		else:
			active_car_id = Global.selected_car_id
			car_id = active_car_id
	
	if not is_ai_controlled and active_car_id != -1:
		Global.selected_car_id = active_car_id

	if Global.car_stats.has(active_car_id):
		var stats = Global.car_stats[active_car_id]
		max_engine_force = stats.get("max_engine_force", 220.0)
		max_steering = stats.get("max_steering", 0.9)
		steering_speed = stats.get("steering_speed", 2.5)
		max_speed = stats.get("max_speed", 65.0)
		max_reverse_speed = stats.get("max_reverse_speed", 20.0)
		drift_factor = stats.get("drift_factor", 0.95)
		body_tilt = stats.get("body_tilt", 25.0)

		if stats.has("mesh_scene") and stats["mesh_scene"] != "":
			if scene_file_path != stats["mesh_scene"]:
				_update_car_mesh(stats["mesh_scene"])

func _physics_process(delta: float) -> void:
	if global_position.y < reset_height_threshold:
		_teleport_to_last_checkpoint()

	var accel_input: bool
	var brake_input: bool
	var steer_input: float
	var handbrake_input: bool

	if is_ai_controlled:
		accel_input = ai_accel
		brake_input = ai_brake
		steer_input = ai_steer
		handbrake_input = ai_handbrake
	else:
		accel_input = Input.is_action_pressed("Accelerate")
		brake_input = Input.is_action_pressed("Brake")
		steer_input = Input.get_axis("SteerRight", "SteerLeft")
		handbrake_input = Input.is_action_pressed("Handbrake")

	if not is_ai_controlled:
		var ui_node = get_node_or_null("UI")
		if ui_node:
			if Input.is_action_pressed("SteerLeft"):
				ui_node.show_turn_signal("turn", true)
			elif Input.is_action_pressed("SteerRight"):
				ui_node.show_turn_signal("turn", false)
			else:
				ui_node.hide_turn_signal()

	var race_stopped = false
	if race_manager and "race_started" in race_manager and not race_manager.race_started:
		race_stopped = true
		accel_input = false
		brake_input = true 
		handbrake_input = true
		steer_input = 0.0

	var forward_dir := -global_transform.basis.z
	var right_dir := global_transform.basis.x
	var current_speed_dot := linear_velocity.dot(forward_dir)
	
	var engine := 0.0
	var brake_force := 0.0

	if race_stopped:
		engine = 0.0
		brake_force = max_engine_force
		is_reversing_action = false

	elif accel_input:
		is_reversing_action = false
		if current_speed_dot < max_speed:
			engine = max_engine_force
		else:
			engine = 0.0
	
	elif brake_input:
		if is_reversing_action:
			brake_force = 0.0
			if current_speed_dot > -max_reverse_speed:
				engine = -max_engine_force
			else:
				engine = 0.0 
		else:
			if current_speed_dot > 2.0:
				brake_force = max_engine_force
				engine = 0.0
			else:
				is_reversing_action = true
				brake_force = 0.0
				engine = -max_engine_force
	else:
		is_reversing_action = false 
		engine = 0.0
		brake_force = 0.0

	if boost_timer > 0.0:
		boost_timer -= delta
		engine *= boost_multiplier

	if oil_slip_timer > 0.0:
		oil_slip_timer -= delta
		if oil_slip_timer < 0.0:
			oil_slip_timer = 0.0

	wheel_rl.engine_force = engine
	wheel_rr.engine_force = engine
	wheel_fl.engine_force = 0.0
	wheel_fr.engine_force = 0.0

	wheel_rl.brake = brake_force
	wheel_rr.brake = brake_force
	wheel_fl.brake = brake_force * 0.7
	wheel_fr.brake = brake_force * 0.7

	var steer_val := steer_input * max_steering
	if abs(current_speed_dot) > 1.0:
		steer_val *= clamp(1.0 - abs(current_speed_dot) / 1000.0, speed_steering_factor, 1.0)
	
	if handbrake_input:
		steer_val *= 1.3
		
	wheel_fl.steering = steer_val
	wheel_fr.steering = steer_val

	_handle_drift(delta, steer_input, handbrake_input, current_speed_dot, right_dir)
	_update_engine_sound(current_speed_dot)
	_handle_visuals(delta, steer_input, current_speed_dot)
	_handle_action_inputs(delta, current_speed_dot)

func _handle_drift(delta: float, steer_input: float, handbrake_input: bool, speed: float, right_dir: Vector3) -> void:
	var lateral_velocity: float = linear_velocity.dot(right_dir)
	var is_sliding: bool = abs(lateral_velocity) > 2.0

	var target_rear_friction: float = normal_friction
	var target_front_friction: float = normal_front_friction

	if oil_slip_timer > 0.0:
		target_rear_friction = oil_slip_friction
		target_front_friction = oil_slip_friction
	elif handbrake_input:
		target_rear_friction = drift_friction
		target_front_friction = drift_front_friction
		if abs(steer_input) > 0.1 and speed > 5.0:
			apply_torque(Vector3.UP * -steer_input * drift_torque_assist)
	elif is_sliding:
		target_rear_friction = drift_friction
		target_front_friction = normal_front_friction
	
	rear_friction = lerp(rear_friction, target_rear_friction, friction_lerp_speed * delta)
	front_friction = lerp(front_friction, target_front_friction, friction_lerp_speed * delta)

	wheel_rl.wheel_friction_slip = rear_friction
	wheel_rr.wheel_friction_slip = rear_friction
	wheel_fl.wheel_friction_slip = front_friction
	wheel_fr.wheel_friction_slip = front_friction

func _handle_visuals(delta: float, steer_input: float, speed: float) -> void:
	if body_mesh:
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

func _handle_action_inputs(delta: float, speed: float) -> void:
	if not is_ai_controlled and Input.is_action_just_pressed("Usepowerup") and has_powerup:
		_use_current_powerup()

	unflip_timer = max(unflip_timer - delta, 0.0)
	if not is_ai_controlled and not unflip_active and Input.is_action_just_pressed("Unflip") and unflip_timer == 0.0:
		if speed < unflip_min_speed:
			var up: Vector3 = global_transform.basis.y.normalized()
			if up.dot(Vector3.UP) < unflip_tilt_threshold:
				_start_unflip()
	
	if unflip_active:
		_process_unflip(delta)

func _start_unflip() -> void:
	unflip_active = true
	unflip_time = 0.0
	unflip_timer = unflip_cooldown
	angular_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	apply_central_impulse(Vector3.UP * unflip_hop_strength)
	unflip_roll_delay_timer = unflip_roll_delay

func _process_unflip(delta: float) -> void:
	unflip_time += delta
	if unflip_time > unflip_max_duration:
		_snap_upright()
		unflip_active = false
		angular_velocity = Vector3.ZERO
		return

	if unflip_roll_delay_timer > 0.0:
		unflip_roll_delay_timer = max(unflip_roll_delay_timer - delta, 0.0)
	else:
		if linear_velocity.y < 0.0:
			linear_velocity.y = 0.0
			
		var cur_basis: Basis = global_transform.basis
		var up_vec: Vector3 = cur_basis.y.normalized()
		var target_up: Vector3 = Vector3.UP
		var rot_axis: Vector3 = up_vec.cross(target_up)
		var axis_len: float = rot_axis.length()
		
		if axis_len > 0.0001:
			rot_axis /= axis_len
			var angle: float = acos(clamp(up_vec.dot(target_up), -1.0, 1.0))
			var step: float = min(unflip_roll_speed * delta, angle)
			var rot: Basis = Basis(rot_axis, step)
			global_transform.basis = rot * cur_basis
			
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

func _update_engine_sound(speed: float) -> void:
	if not engine_sound_player: return
	var pitch = clamp(0.5 + (speed / max_speed) * 1.5, 0.5, 2.5)
	engine_sound_player.pitch_scale = lerp(engine_sound_player.pitch_scale, pitch, 0.1)

func set_ai_inputs(accel: bool, is_braking: bool, steer: float, handbrake: bool) -> void:
	ai_accel = accel
	ai_brake = is_braking
	ai_steer = clamp(steer, -1.0, 1.0)
	ai_handbrake = handbrake

func _teleport_to_last_checkpoint() -> void:
	if race_manager and race_manager.has_method("get_last_checkpoint_for_car"):
		var cp: Node3D = race_manager.get_last_checkpoint_for_car(self)
		if cp:
			var t: Transform3D = cp.global_transform
			var rotated_basis = t.basis.rotated(Vector3.UP, PI)
			global_transform = Transform3D(rotated_basis, t.origin)
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO

func on_checkpoint_passed(checkpoint: Node) -> void:
	if race_manager and race_manager.has_method("on_car_checkpoint"):
		race_manager.on_car_checkpoint(self, checkpoint)

func get_speed() -> float:
	return linear_velocity.length()

func pickup_powerup(powerup: Node) -> void:
	if powerup.has_method("get_powerup_type"):
		current_powerup = powerup.get_powerup_type()
		has_powerup = true

func has_powerup_func() -> bool:
	return has_powerup

func _use_current_powerup() -> void:
	match current_powerup:
		"speed_boost": _apply_speed_boost()
		"oil": _drop_oil()
		"water_balloon": _shoot_water_balloon()
	has_powerup = false
	current_powerup = ""

func _apply_speed_boost() -> void:
	boost_timer = boost_duration

func _drop_oil() -> void:
	var oil_scene = load("res://Scenes/OilSlick.tscn")
	if oil_scene:
		var oil = oil_scene.instantiate()
		get_tree().current_scene.add_child(oil)
		oil.global_position = global_transform.origin + (-global_transform.basis.z * 1.5)
		oil.global_rotation = global_transform.basis.get_euler()

func apply_oil_slip(oil: Node) -> void:
	oil_slip_timer = oil_slip_duration
	rear_friction = normal_friction
	front_friction = normal_front_friction

func _shoot_water_balloon() -> void:
	var scene = load("res://Scenes/WaterBalloon.tscn")
	if scene:
		var balloon = scene.instantiate()
		get_tree().current_scene.add_child(balloon)
		balloon.global_position = global_transform.origin + (global_transform.basis.z * 1.5) + Vector3.UP * 0.5
		balloon.global_rotation = global_transform.basis.get_euler()
		var forward_dir: Vector3 = global_transform.basis.z
		balloon.linear_velocity = linear_velocity + forward_dir * 20.0

func apply_water_hit(balloon: Node) -> void:
	var force = balloon.splash_force if "splash_force" in balloon else 5.0
	angular_velocity += Vector3.UP * force
	linear_velocity *= 0.6

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

		var potential_body = new_body.find_child("body")
		if potential_body:
			body_mesh = potential_body
		else:
			body_mesh = new_body
		sleeping = false
