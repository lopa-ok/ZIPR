extends Node

@export var cars: Array[VehicleBody3D] = []

@export var waypoints: Array[NodePath] = []

@export var use_waypoints: bool = false

@export var waypoint_reach_radius: float = 4.0

@export var lookahead_min: float = 4.0
@export var lookahead_max: float = 16.0
@export var lookahead_speed_ref: float = 40.0

@export var target_speed: float = 45.0
@export var min_target_speed: float = 18.0
@export var corner_slowdown: float = 28.0

@export var steer_gain: float = 1.25
@export var steer_smooth: float = 8.0
@export var steer_rate_limit: float = 3.5

@export var throttle_deadzone: float = 0.05

@export var handbrake_for_hairpins: bool = true
@export var handbrake_angle_deg: float = 55.0
@export var handbrake_min_speed: float = 18.0

@export var steer_deadzone_deg: float = 2.0
@export var max_steer_at_speed: float = 0.85
@export var wall_avoid_slowdown: float = 12.0

@export var avoidance_radius: float = 5.0
@export var avoidance_strength: float = 12.0
@export var avoidance_check_interval: float = 0.1

@export var straight_lateral_deadzone: float = 0.6
@export var straight_angle_deg: float = 6.0
@export var straight_steer_gain: float = 0.55
@export var straight_hold_time: float = 0.25

@export var wobble_reduction_deadzone: float = 0.05
@export var wobble_reduction_strength: float = 0.5

@export var yaw_rate_damp: float = 0.22

@export var stuck_check_interval: float = 0.35
@export var stuck_speed_threshold: float = 0.8
@export var stuck_time_to_respawn: float = 2.0

@export_group("Wall Collision Recovery")
@export var wall_detection_enabled: bool = true
@export var wall_stuck_speed_threshold: float = 2.0
@export var wall_stuck_time_threshold: float = 0.8
@export var wall_backup_duration: float = 1.2
@export var wall_backup_steer_amount: float = 0.6

@export var turn_preview_distance: float = 10.0
@export var turn_preview_weight: float = 0.65
@export var brake_for_turns: bool = true
@export var brake_turn_angle_deg: float = 22.0

@export_group("Rubber Banding")
@export var enable_rubber_banding: bool = true
@export var rubber_band_catchup_speed: float = 12.0
@export var rubber_band_slowdown_speed: float = 8.0
@export var rubber_band_max_distance: float = 150.0

class CarAIState:
	var body: VehicleBody3D
	var controller: Node = null
	var steer_smoothed: float = 0.0
	var steer_out: float = 0.0
	var straight_hold: float = 0.0
	var stuck_timer: float = 0.0
	var stuck_check_timer: float = 0.0
	var waypoint_index: int = 0
	var base_ai_max_speed: float = -1.0
	
	# Wall collision recovery
	var wall_stuck_timer: float = 0.0
	var is_backing_up: bool = false
	var backup_timer: float = 0.0
	var backup_steer_direction: float = 0.0
	var last_position: Vector3 = Vector3.ZERO
	var position_check_timer: float = 0.0
	
	func _init(p_body: VehicleBody3D):
		body = p_body
		if body and "ai_max_speed" in body:
			base_ai_max_speed = float(body.get("ai_max_speed"))
		if body:
			last_position = body.global_position

var _race_manager: Node = null
var _checkpoints: Array[Node] = []
var _car_states: Array[CarAIState] = []

func _ready() -> void:
	if not is_in_group("ai_manager"):
		add_to_group("ai_manager")
		
	_race_manager = get_tree().get_first_node_in_group("race_manager")
	
	if cars.is_empty():
		var p = get_parent()
		if p is VehicleBody3D:
			cars.append(p)
	
	for car_body in cars:
		if car_body:
			var state = CarAIState.new(car_body)
			_resolve_car_controller(state)
			_car_states.append(state)
			
			var target_car = state.controller if state.controller else state.body
			if target_car and "is_ai_controlled" in target_car:
				target_car.is_ai_controlled = true
	
	_refresh_checkpoints()

func register_ai_car(car_body: VehicleBody3D) -> void:
	if not car_body:
		return
		
	for state in _car_states:
		if state.body == car_body:
			return
	
	print("[AI] Registering new AI car: ", car_body.name)
	cars.append(car_body)
	
	var state = CarAIState.new(car_body)
	_resolve_car_controller(state)
	_car_states.append(state)
	
	var target_car = state.controller if state.controller else state.body
	if target_car and "is_ai_controlled" in target_car:
		target_car.is_ai_controlled = true

func _resolve_car_controller(state: CarAIState) -> void:
	state.controller = null
	
	if state.body == null:
		return
	if state.body.has_method("set_ai_inputs"):
		state.controller = state.body
		return
	for child in state.body.get_children():
		if child is Node and (child as Node).has_method("set_ai_inputs"):
			state.controller = child as Node
			return
	var p: Node = state.body.get_parent()
	while p != null:
		if p.has_method("set_ai_inputs"):
			state.controller = p
			return
		p = p.get_parent()

func _refresh_checkpoints() -> void:
	_checkpoints.clear()
	if _race_manager == null:
		_race_manager = get_tree().get_first_node_in_group("race_manager")
	if _race_manager == null:
		return
	if "checkpoints" in _race_manager:
		_checkpoints = _race_manager.checkpoints

func _physics_process(delta: float) -> void:
	if _car_states.is_empty() and cars.is_empty():
		var p = get_parent()
		if p is VehicleBody3D:
			cars.append(p)
			var state = CarAIState.new(p)
			_resolve_car_controller(state)
			_car_states.append(state)
			var target_car = state.controller if state.controller else state.body
			if target_car and "is_ai_controlled" in target_car:
				target_car.is_ai_controlled = true
		else:
			return

	for state in _car_states:
		_process_car(state, delta)

func _process_car(state: CarAIState, delta: float) -> void:
	if _race_manager and "race_started" in _race_manager and not _race_manager.race_started:
		if state.controller == null:
			_resolve_car_controller(state)
		if state.controller:
			state.controller.call("set_ai_inputs", false, true, 0.0, true)
		return

	if state.controller == null:
		_resolve_car_controller(state)
		if state.base_ai_max_speed < 0.0 and state.body and "ai_max_speed" in state.body:
			state.base_ai_max_speed = float(state.body.get("ai_max_speed"))

	var car_body: VehicleBody3D = state.body
	if car_body == null:
		return

	if car_body.sleeping:
		car_body.sleeping = false

	var car_node: Node = state.controller if state.controller != null else state.body
	if ("is_ai_controlled" in car_node):
		car_node.is_ai_controlled = true

	var forward_dir: Vector3 = -car_body.global_transform.basis.z
	var speed: float = float(car_body.linear_velocity.dot(forward_dir))
	var speed_abs: float = abs(speed)

	if state.is_backing_up:
		state.backup_timer -= delta
		if state.backup_timer <= 0.0:
			state.is_backing_up = false
			state.wall_stuck_timer = 0.0
		else:
			_send_ai_inputs(state, false, true, state.backup_steer_direction, false)
			return

	if wall_detection_enabled:
		state.position_check_timer += delta
		if state.position_check_timer >= 0.2:
			state.position_check_timer = 0.0
			var dist_moved = car_body.global_position.distance_to(state.last_position)
			state.last_position = car_body.global_position
			
			if dist_moved < 0.5 and speed_abs < wall_stuck_speed_threshold:
				state.wall_stuck_timer += 0.2
			else:
				state.wall_stuck_timer = max(0.0, state.wall_stuck_timer - 0.2)
			
			if state.wall_stuck_timer > wall_stuck_time_threshold:
				state.is_backing_up = true
				state.backup_timer = wall_backup_duration
				state.wall_stuck_timer = 0.0
				
				if abs(state.steer_out) > 0.1:
					state.backup_steer_direction = -sign(state.steer_out) * wall_backup_steer_amount
				else:
					state.backup_steer_direction = (1.0 if randf() > 0.5 else -1.0) * wall_backup_steer_amount
				
				_send_ai_inputs(state, false, true, state.backup_steer_direction, false)
				return

	var target_point: Vector3 = Vector3.INF

	if use_waypoints and not waypoints.is_empty():
		target_point = _get_current_waypoint_target(state)
			
	if target_point == Vector3.INF:
		if _checkpoints.is_empty():
			_refresh_checkpoints()
		
		if not _checkpoints.is_empty():
			var next_idx: int = 0
			if _race_manager != null and _race_manager.has_method("get_next_checkpoint_index_for_car"):
				var raw_idx = _race_manager.get_next_checkpoint_index_for_car(car_node)
				if raw_idx != null:
					next_idx = int(raw_idx)
			elif _race_manager != null and ("car_progress" in _race_manager) and _race_manager.car_progress.has(car_node):
				var dic = _race_manager.car_progress[car_node]
				if dic and dic.has("next_index"):
					next_idx = int(dic["next_index"])
			
			var lookahead = lerp(lookahead_min, lookahead_max, clamp(speed_abs / lookahead_speed_ref, 0.0, 1.0))
			target_point = _compute_lookahead_target(state, next_idx, lookahead)
		else:
			if state.stuck_check_timer == 0.0:
				print("[AI] No checkpoints or waypoints found for ", car_body.name, "! Driving blindly.")
			var fallback_steer: float = float(sin(float(Time.get_ticks_msec()) * 0.001 + float(car_body.get_instance_id()))) * 0.2
			_send_ai_inputs(state, true, false, fallback_steer, false)
			return

	if target_point != Vector3.INF:
		_drive_towards_target(state, delta, target_point)

func _drive_towards_target(state: CarAIState, delta: float, target_point: Vector3) -> void:
	var car_body: VehicleBody3D = state.body
	var forward_dir: Vector3 = -car_body.global_transform.basis.z
	var speed: float = float(car_body.linear_velocity.dot(forward_dir))
	var speed_abs: float = abs(speed)

	var to_target_world: Vector3 = target_point - car_body.global_position
	
	var avoid_vec: Vector3 = Vector3.ZERO
	var cars_to_check: Array = []
	
	if _race_manager != null and "car_progress" in _race_manager:
		cars_to_check = _race_manager.car_progress.keys()
	else:
		for s in _car_states:
			if s.body:
				cars_to_check.append(s.body)
	
	for other in cars_to_check:
		if other == car_body or not is_instance_valid(other):
			continue
		
		var other_body = other as Node3D
		if other_body == null: continue

		var diff: Vector3 = car_body.global_position - other_body.global_position
		var dist: float = diff.length()
		
		if dist < avoidance_radius and dist > 0.01:
			var repulsion: float = (1.0 - (dist / avoidance_radius))
			avoid_vec += diff.normalized() * repulsion
	
	if avoid_vec != Vector3.ZERO:
		to_target_world += avoid_vec * avoidance_strength

	var local_target: Vector3 = car_body.global_transform.basis.inverse() * to_target_world
	local_target.y = 0.0

	var target_in_front: bool = (local_target.z < -0.5)

	var desired_yaw: float = atan2(float(local_target.x), float(-local_target.z))
	var desired_yaw_deg: float = abs(rad_to_deg(desired_yaw))

	var lateral_error: float = abs(float(local_target.x))
	var is_straight: bool = (desired_yaw_deg < straight_angle_deg and lateral_error < straight_lateral_deadzone)
	if is_straight:
		state.straight_hold = min(state.straight_hold + delta, straight_hold_time)
		desired_yaw *= straight_steer_gain
	else:
		state.straight_hold = max(state.straight_hold - delta * 2.0, 0.0)

	if desired_yaw_deg < steer_deadzone_deg:
		desired_yaw = 0.0

	var steer_cmd: float = clamp(desired_yaw * steer_gain, -1.0, 1.0)
	if not target_in_front:
		steer_cmd *= 0.35

	var speed_steer_limit: float = lerp(1.0, max_steer_at_speed, clamp(speed_abs / max(target_speed, 0.01), 0.0, 1.0))
	steer_cmd = clamp(steer_cmd, -speed_steer_limit, speed_steer_limit)

	var yaw_rate: float = float(car_body.angular_velocity.y)
	steer_cmd = clamp(steer_cmd - yaw_rate * yaw_rate_damp, -1.0, 1.0)

	if state.straight_hold >= straight_hold_time:
		steer_cmd = 0.0

	if abs(desired_yaw) < wobble_reduction_deadzone:
		state.steer_smoothed = move_toward(state.steer_smoothed, 0.0, delta * wobble_reduction_strength)
		steer_cmd *= 0.5

	var steer_alpha: float = clamp(steer_smooth * delta, 0.0, 1.0)
	state.steer_smoothed = lerp(state.steer_smoothed, steer_cmd, steer_alpha)

	var max_step: float = steer_rate_limit * delta
	state.steer_out = move_toward(state.steer_out, state.steer_smoothed, max_step)

	var target_dir_world: Vector3 = to_target_world
	target_dir_world.y = 0.0
	var fwd: Vector3 = forward_dir
	fwd.y = 0.0
	var angle_to_target: float = 0.0
	if target_dir_world.length() > 0.01 and fwd.length() > 0.01:
		angle_to_target = abs(rad_to_deg(fwd.normalized().angle_to(target_dir_world.normalized())))
	
	var turn_severity: float = angle_to_target 

	var desired_speed: float = target_speed - (turn_severity / 90.0) * corner_slowdown
	
	if turn_severity > 45.0:
		desired_speed -= wall_avoid_slowdown
	
	if enable_rubber_banding and _race_manager != null and _race_manager.has_method("get_race_progress_distance"):
		var player_car: Node = _get_player_car()
		if player_car and player_car != car_body:
			var my_prog: float = _race_manager.get_race_progress_distance(car_body)
			var pl_prog: float = _race_manager.get_race_progress_distance(player_car)
			var diff: float = pl_prog - my_prog 
			
			if diff > 0.0:
				var factor: float = clamp(diff / rubber_band_max_distance, 0.0, 1.0)
				var boost: float = rubber_band_catchup_speed * factor
				desired_speed += boost
				
				if state.base_ai_max_speed > 0.0 and "ai_max_speed" in car_body:
					car_body.set("ai_max_speed", max(state.base_ai_max_speed, desired_speed + 5.0))
			else:
				var factor: float = clamp(abs(diff) / rubber_band_max_distance, 0.0, 1.0)
				desired_speed -= rubber_band_slowdown_speed * factor
				
				if state.base_ai_max_speed > 0.0 and "ai_max_speed" in car_body:
					car_body.set("ai_max_speed", state.base_ai_max_speed)
		elif state.base_ai_max_speed > 0.0 and "ai_max_speed" in car_body:
			car_body.set("ai_max_speed", state.base_ai_max_speed)

	desired_speed = clamp(desired_speed, min_target_speed, max(target_speed + rubber_band_catchup_speed, 100.0))

	var accel: bool = false
	var brake: bool = false
	var handbrake: bool = false

	var speed_error: float = desired_speed - speed_abs
	if speed_error > max(throttle_deadzone * desired_speed, 0.5):
		accel = true
	elif speed_error < -1.0:
		brake = true

	if brake_for_turns and turn_severity > brake_turn_angle_deg and speed_abs > min_target_speed + 2.0:
		brake = true
		accel = false

	if handbrake_for_hairpins and speed_abs > handbrake_min_speed and turn_severity > handbrake_angle_deg:
		handbrake = true

	if speed < -1.5:
		accel = true
		brake = false

	_send_ai_inputs(state, accel, brake, state.steer_out, handbrake)
	_update_unstuck(state, delta, speed_abs)

func _send_ai_inputs(state: CarAIState, accel: bool, brake: bool, steer: float, handbrake: bool) -> void:
	if state.controller == null:
		_resolve_car_controller(state)
	if state.controller == null:
		if Engine.get_process_frames() % 60 == 0:
			var n = "unknown"
			if state.body:
				n = state.body.name
			print("[AI-Error] No controller found for ", n)
		return
		
	state.controller.call("set_ai_inputs", accel, brake, steer, handbrake)

func _compute_lookahead_target(state: CarAIState, next_idx: int, lookahead: float) -> Vector3:
	if state.body == null:
		return Vector3.ZERO
		
	var idx: int = clamp(next_idx, 0, _checkpoints.size() - 1)
	var pos: Vector3 = state.body.global_position
	var remaining: float = lookahead

	for _i in range(min(_checkpoints.size(), 12)):
		var cp: Node = _checkpoints[idx]
		if cp == null or not (cp is Node3D):
			break
		var cp_pos: Vector3 = (cp as Node3D).global_position
		var d: float = pos.distance_to(cp_pos)
		if d >= remaining:
			var t: float = float(remaining) / max(d, 0.001)
			return pos.lerp(cp_pos, t)
		remaining -= d
		pos = cp_pos
		idx = (idx + 1) % _checkpoints.size()

	var cp0: Node = _checkpoints[clamp(next_idx, 0, _checkpoints.size() - 1)]
	return (cp0 as Node3D).global_position if (cp0 is Node3D) else state.body.global_position

func _update_unstuck(state: CarAIState, delta: float, speed_abs: float) -> void:
	state.stuck_check_timer += delta
	if state.stuck_check_timer < stuck_check_interval:
		return
	state.stuck_check_timer = 0.0

	if speed_abs < stuck_speed_threshold:
		state.stuck_timer += stuck_check_interval
	else:
		state.stuck_timer = max(state.stuck_timer - stuck_check_interval * 2.0, 0.0)

	if state.stuck_timer >= stuck_time_to_respawn:
		state.stuck_timer = 0.0
		if _race_manager != null and _race_manager.has_method("get_last_checkpoint_for_car"):
			if state.body:
				var cp: Node = _race_manager.get_last_checkpoint_for_car(state.body)
				if cp != null and cp is Node3D:
					state.body.global_transform.origin = (cp as Node3D).global_transform.origin
					state.body.linear_velocity = Vector3.ZERO
					state.body.angular_velocity = Vector3.ZERO

func _get_current_waypoint_target(state: CarAIState) -> Vector3:
	if waypoints.is_empty():
		return Vector3.INF

	var safety: int = 0
	while safety < waypoints.size():
		safety += 1
		state.waypoint_index = posmod(state.waypoint_index, waypoints.size())
		var np: NodePath = waypoints[state.waypoint_index]
		if np == NodePath():
			state.waypoint_index += 1
			continue
		var n: Node = get_node_or_null(np)
		if n == null or not (n is Node3D):
			state.waypoint_index += 1
			continue

		var p: Vector3 = (n as Node3D).global_position
		var reach: float = waypoint_reach_radius
		if state.body != null and state.body.global_position.distance_to(p) <= reach:
			state.waypoint_index += 1
			continue
		return p

	return Vector3.INF

func _get_waypoint_point(index: int) -> Vector3:
	if waypoints.is_empty():
		return Vector3.INF
	var i: int = posmod(index, waypoints.size())
	var np: NodePath = waypoints[i]
	if np == NodePath():
		return Vector3.INF
	var n: Node = get_node_or_null(np)
	if n == null or not (n is Node3D):
		return Vector3.INF
	return (n as Node3D).global_position

func _get_player_car() -> Node:
	if _race_manager == null:
		return null
	if "car_progress" in _race_manager:
		for car in _race_manager.car_progress.keys():
			if car and car.get("is_ai_controlled") == false:
				return car
	return null
