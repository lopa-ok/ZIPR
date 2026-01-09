extends Node

@export var car: VehicleBody3D

@export var waypoints: Array[NodePath] = []

@export var use_waypoints: bool = false

@export var waypoint_reach_radius: float = 4.0
var _waypoint_index: int = 0

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

@export var straight_lateral_deadzone: float = 0.6
@export var straight_angle_deg: float = 6.0
@export var straight_steer_gain: float = 0.55
@export var straight_hold_time: float = 0.25

@export var yaw_rate_damp: float = 0.22

@export var stuck_check_interval: float = 0.35
@export var stuck_speed_threshold: float = 0.8
@export var stuck_time_to_respawn: float = 2.0

@export var turn_preview_distance: float = 10.0
@export var turn_preview_weight: float = 0.65
@export var brake_for_turns: bool = true
@export var brake_turn_angle_deg: float = 22.0

var _race_manager: Node = null
var _checkpoints: Array[Node] = []

var _car_controller: Node = null

var _steer_smoothed: float = 0.0
var _steer_out: float = 0.0
var _straight_hold: float = 0.0

var _stuck_timer: float = 0.0
var _stuck_check_timer: float = 0.0

func _ready() -> void:
	_race_manager = get_tree().get_first_node_in_group("race_manager")
	_resolve_car_controller()
	_refresh_checkpoints()

func _resolve_car_controller() -> void:
	_car_controller = null
	if car == null:
		return
	if car.has_method("set_ai_inputs"):
		_car_controller = car
		return
	for child in car.get_children():
		if child is Node and (child as Node).has_method("set_ai_inputs"):
			_car_controller = child as Node
			return
	var p: Node = car.get_parent()
	while p != null:
		if p.has_method("set_ai_inputs"):
			_car_controller = p
			return
		p = p.get_parent()

func _refresh_checkpoints() -> void:
	_checkpoints.clear()
	if _race_manager == null:
		return
	if "checkpoints" in _race_manager:
		_checkpoints = _race_manager.checkpoints

func _physics_process(delta: float) -> void:
	if car == null:
		return
	if _car_controller == null:
		_resolve_car_controller()

	var car_node: Node = _car_controller if _car_controller != null else car
	var car_body: VehicleBody3D = car_node as VehicleBody3D
	if car_body == null:
		return

	if ("is_ai_controlled" in car_node):
		car_node.is_ai_controlled = true

	if use_waypoints and not waypoints.is_empty():
		var wp_target: Vector3 = _get_current_waypoint_target()
		if wp_target != Vector3.INF:
			_drive_towards_target(delta, wp_target)
			return

	if _checkpoints.is_empty():
		_refresh_checkpoints()
		if _checkpoints.is_empty():
			if not waypoints.is_empty():
				var wp_target: Vector3 = _get_current_waypoint_target()
				if wp_target != Vector3.INF:
					_drive_towards_target(delta, wp_target)
					return

			var fallback_steer: float = float(sin(float(Time.get_ticks_msec()) * 0.001)) * 0.2
			_send_ai_inputs(true, false, fallback_steer, false)
			return

	var next_idx: int = 0
	if _race_manager != null and _race_manager.has_method("get_next_checkpoint_index_for_car"):
		next_idx = int(_race_manager.get_next_checkpoint_index_for_car(car_node))
	elif _race_manager != null and ("car_progress" in _race_manager) and _race_manager.car_progress.has(car_node):
		next_idx = int(_race_manager.car_progress[car_node]["next_index"])

	var forward_dir: Vector3 = -car_body.global_transform.basis.z
	var speed: float = float(car_body.linear_velocity.dot(forward_dir))
	var speed_abs: float = abs(speed)
	var lookahead_lerp_t: float = clamp(speed_abs / lookahead_speed_ref, 0.0, 1.0)
	var lookahead: float = lerp(lookahead_min, lookahead_max, lookahead_lerp_t)
	var target_point: Vector3 = _compute_lookahead_target(next_idx, lookahead)

	_drive_towards_target(delta, target_point)

func _drive_towards_target(delta: float, target_point: Vector3) -> void:
	var car_node: Node = _car_controller if _car_controller != null else car
	var car_body: VehicleBody3D = car_node as VehicleBody3D
	if car_body == null:
		return

	var forward_dir: Vector3 = -car_body.global_transform.basis.z
	var speed: float = float(car_body.linear_velocity.dot(forward_dir))
	var speed_abs: float = abs(speed)

	var to_target_world: Vector3 = target_point - car_body.global_position
	var local_target: Vector3 = car_body.global_transform.basis.inverse() * to_target_world
	local_target.y = 0.0

	var target_in_front: bool = (local_target.z < -0.5)

	var desired_yaw: float = atan2(float(local_target.x), float(-local_target.z))
	var desired_yaw_deg: float = abs(rad_to_deg(desired_yaw))

	var lateral_error: float = abs(float(local_target.x))
	var is_straight: bool = (desired_yaw_deg < straight_angle_deg and lateral_error < straight_lateral_deadzone)
	if is_straight:
		_straight_hold = min(_straight_hold + delta, straight_hold_time)
		desired_yaw *= straight_steer_gain
	else:
		_straight_hold = max(_straight_hold - delta * 2.0, 0.0)

	desired_yaw_deg = abs(rad_to_deg(desired_yaw))
	if desired_yaw_deg < steer_deadzone_deg:
		desired_yaw = 0.0

	var steer_cmd: float = clamp(desired_yaw * steer_gain, -1.0, 1.0)
	if not target_in_front:
		steer_cmd *= 0.35

	var speed_steer_limit: float = lerp(1.0, max_steer_at_speed, clamp(speed_abs / max(target_speed, 0.01), 0.0, 1.0))
	steer_cmd = clamp(steer_cmd, -speed_steer_limit, speed_steer_limit)

	var yaw_rate: float = float(car_body.angular_velocity.y)
	steer_cmd = clamp(steer_cmd - yaw_rate * yaw_rate_damp, -1.0, 1.0)

	if _straight_hold >= straight_hold_time:
		steer_cmd = 0.0

	var steer_alpha: float = clamp(steer_smooth * delta, 0.0, 1.0)
	_steer_smoothed = lerp(_steer_smoothed, steer_cmd, steer_alpha)

	var max_step: float = steer_rate_limit * delta
	_steer_out = move_toward(_steer_out, _steer_smoothed, max_step)

	var target_dir_world: Vector3 = to_target_world
	target_dir_world.y = 0.0
	var fwd: Vector3 = forward_dir
	fwd.y = 0.0
	var angle_to_target: float = 0.0
	if target_dir_world.length() > 0.01 and fwd.length() > 0.01:
		angle_to_target = abs(rad_to_deg(fwd.normalized().angle_to(target_dir_world.normalized())))

	var preview_angle: float = angle_to_target
	if use_waypoints and not waypoints.is_empty():
		var p2: Vector3 = _get_waypoint_point(_waypoint_index + 1)
		if p2 != Vector3.INF:
			var dir2: Vector3 = (p2 - car_body.global_position)
			dir2.y = 0.0
			if dir2.length() > 0.01 and fwd.length() > 0.01:
				preview_angle = abs(rad_to_deg(fwd.normalized().angle_to(dir2.normalized())))
	elif not _checkpoints.is_empty():
		var idx2: int = 0
		if _race_manager != null and _race_manager.has_method("get_next_checkpoint_index_for_car"):
			idx2 = int(_race_manager.get_next_checkpoint_index_for_car(car_node))
		var next2: int = (idx2 + 1) % _checkpoints.size()
		var cp2: Node = _checkpoints[next2]
		if cp2 != null and (cp2 is Node3D):
			var dir2: Vector3 = ((cp2 as Node3D).global_position - car_body.global_position)
			dir2.y = 0.0
			if dir2.length() > 0.01 and fwd.length() > 0.01:
				preview_angle = abs(rad_to_deg(fwd.normalized().angle_to(dir2.normalized())))

	var turn_severity: float = lerp(angle_to_target, max(angle_to_target, preview_angle), turn_preview_weight)

	var desired_speed: float = target_speed - (turn_severity / 90.0) * corner_slowdown
	if turn_severity > 45.0:
		desired_speed -= wall_avoid_slowdown
	desired_speed = clamp(desired_speed, min_target_speed, target_speed)

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

	_send_ai_inputs(accel, brake, _steer_out, handbrake)
	_update_unstuck(delta, speed_abs)

func _send_ai_inputs(accel: bool, brake: bool, steer: float, handbrake: bool) -> void:
	if _car_controller == null:
		_resolve_car_controller()
	if _car_controller == null:
		return
	_car_controller.call("set_ai_inputs", accel, brake, steer, handbrake)

func _compute_lookahead_target(next_idx: int, lookahead: float) -> Vector3:
	var idx: int = clamp(next_idx, 0, _checkpoints.size() - 1)
	var pos: Vector3 = car.global_position
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
	return (cp0 as Node3D).global_position if (cp0 is Node3D) else car.global_position

func _update_unstuck(delta: float, speed_abs: float) -> void:
	_stuck_check_timer += delta
	if _stuck_check_timer < stuck_check_interval:
		return
	_stuck_check_timer = 0.0

	if speed_abs < stuck_speed_threshold:
		_stuck_timer += stuck_check_interval
	else:
		_stuck_timer = max(_stuck_timer - stuck_check_interval * 2.0, 0.0)

	if _stuck_timer >= stuck_time_to_respawn:
		_stuck_timer = 0.0
		if _race_manager != null and _race_manager.has_method("get_last_checkpoint_for_car"):
			var cp: Node = _race_manager.get_last_checkpoint_for_car(car)
			if cp != null and cp is Node3D:
				car.global_transform.origin = (cp as Node3D).global_transform.origin
				car.linear_velocity = Vector3.ZERO
				car.angular_velocity = Vector3.ZERO

func _get_current_waypoint_target() -> Vector3:
	if waypoints.is_empty():
		return Vector3.INF

	var safety: int = 0
	while safety < waypoints.size():
		safety += 1
		_waypoint_index = posmod(_waypoint_index, waypoints.size())
		var np: NodePath = waypoints[_waypoint_index]
		if np == NodePath():
			_waypoint_index += 1
			continue
		var n: Node = get_node_or_null(np)
		if n == null or not (n is Node3D):
			_waypoint_index += 1
			continue

		var p: Vector3 = (n as Node3D).global_position
		var reach: float = waypoint_reach_radius
		if car != null and car.global_position.distance_to(p) <= reach:
			_waypoint_index += 1
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
