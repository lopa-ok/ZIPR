extends Node

enum AIState { IDLE, ATTACK, DEFEND }

@export_group("Arena Awareness")
@export var sumo_manager_path: NodePath = NodePath()
@export var edge_danger_threshold: float = 0.75
@export var edge_critical_threshold: float = 0.90

@export_group("Target Selection")
@export var detection_range: float = 30.0
@export var edge_target_bonus: float = 3.0
@export var rear_hit_bonus: float = 2.0
@export var facing_outward_bonus: float = 1.5
@export var retarget_interval: float = 0.5

@export_group("Attack Driving")
@export var attack_speed: float = 55.0
@export var ram_boost_speed: float = 70.0
@export var ram_boost_distance: float = 8.0
@export var steer_gain: float = 2.0
@export var steer_smooth: float = 10.0
@export var side_hit_offset: float = 1.5

@export_group("Defend / Recovery")
@export var defend_speed: float = 40.0
@export var defend_linger_time: float = 0.8

@export_group("Stuck Recovery")
@export var stuck_speed_threshold: float = 1.5
@export var stuck_time_to_recover: float = 1.5
@export var reverse_duration: float = 1.0
@export var reverse_steer_amount: float = 0.6

@export_group("Personality Variation")
@export var aggression_range: Vector2 = Vector2(0.6, 1.0)
@export var reaction_delay_range: Vector2 = Vector2(0.0, 0.15)

class SumoCarState:
	var body: VehicleBody3D
	var controller: Node = null
	var state: int = AIState.IDLE
	var target: VehicleBody3D = null
	var retarget_timer: float = 0.0
	var defend_timer: float = 0.0
	var steer_smoothed: float = 0.0
	var aggression: float = 0.8
	var reaction_delay: float = 0.0
	var reaction_timer: float = 0.0
	var stuck_timer: float = 0.0
	var last_position: Vector3 = Vector3.ZERO
	var position_check_timer: float = 0.0
	var is_reversing: bool = false
	var reverse_timer: float = 0.0
	var reverse_steer: float = 0.0

	func _init(p_body: VehicleBody3D) -> void:
		body = p_body
		if body:
			last_position = body.global_position

var _sumo_manager: Node = null
var _car_states: Array[SumoCarState] = []
var _all_cars: Array[Node] = []

func _ready() -> void:
	if not is_in_group("sumo_ai_manager"):
		add_to_group("sumo_ai_manager")

	if sumo_manager_path != NodePath():
		_sumo_manager = get_node_or_null(sumo_manager_path)
	if _sumo_manager == null:
		_sumo_manager = get_tree().get_first_node_in_group("sumo_manager")

func register_ai_car(car_body: VehicleBody3D) -> void:
	if not car_body:
		return
	for s in _car_states:
		if s.body == car_body:
			return

	var state := SumoCarState.new(car_body)
	state.aggression = randf_range(aggression_range.x, aggression_range.y)
	state.reaction_delay = randf_range(reaction_delay_range.x, reaction_delay_range.y)
	_resolve_controller(state)
	_car_states.append(state)

	var target_node: Node = state.controller if state.controller else state.body
	if target_node and "is_ai_controlled" in target_node:
		target_node.is_ai_controlled = true

	print("[SUMO_AI] Registered: ", car_body.name, " aggression=%.2f" % state.aggression)

func _resolve_controller(state: SumoCarState) -> void:
	state.controller = null
	if state.body == null:
		return
	if state.body.has_method("set_ai_inputs"):
		state.controller = state.body
		return
	for child in state.body.get_children():
		if child.has_method("set_ai_inputs"):
			state.controller = child
			return

func _physics_process(delta: float) -> void:
	if _sumo_manager and not _sumo_manager.game_started:
		for s in _car_states:
			_send_inputs(s, false, true, 0.0, true)
		return

	_all_cars.clear()
	if _sumo_manager and _sumo_manager.has_method("is_car_alive"):
		for s in _car_states:
			if _sumo_manager.is_car_alive(s.body):
				_all_cars.append(s.body)
		for car in _sumo_manager.alive_cars:
			if car not in _all_cars:
				_all_cars.append(car)
	else:
		for s in _car_states:
			if is_instance_valid(s.body):
				_all_cars.append(s.body)

	for s in _car_states:
		if not is_instance_valid(s.body):
			continue
		if _sumo_manager and not _sumo_manager.is_car_alive(s.body):
			_send_inputs(s, false, true, 0.0, false)
			continue
		_process_car(s, delta)

func _process_car(s: SumoCarState, delta: float) -> void:
	if s.controller == null:
		_resolve_controller(s)
	if s.controller == null:
		return

	if s.body.sleeping:
		s.body.sleeping = false

	s.reaction_timer += delta
	if s.reaction_timer < s.reaction_delay:
		return
	s.reaction_timer = 0.0
	s.reaction_delay = randf_range(reaction_delay_range.x, reaction_delay_range.y)

	if _check_stuck(s, delta):
		return

	var my_edge_factor: float = _get_edge_factor(s.body)

	if my_edge_factor >= edge_danger_threshold:
		if s.state != AIState.DEFEND:
			s.state = AIState.DEFEND
			s.defend_timer = 0.0

	if s.state == AIState.DEFEND:
		if my_edge_factor < edge_danger_threshold * 0.6:
			s.defend_timer += delta
			if s.defend_timer >= defend_linger_time:
				s.state = AIState.IDLE

	if s.state == AIState.IDLE:
		s.retarget_timer += delta
		if s.retarget_timer >= retarget_interval * (2.0 - s.aggression):
			s.target = _select_target(s)
			s.retarget_timer = 0.0
			if s.target:
				s.state = AIState.ATTACK

	if s.state == AIState.ATTACK:
		s.retarget_timer += delta
		if s.retarget_timer >= retarget_interval:
			s.retarget_timer = 0.0
			if s.target == null or not is_instance_valid(s.target):
				s.target = _select_target(s)
			elif _sumo_manager and not _sumo_manager.is_car_alive(s.target):
				s.target = _select_target(s)
			else:
				var better := _select_target(s)
				if better and better != s.target:
					var old_score := _score_target(s, s.target)
					var new_score := _score_target(s, better)
					if new_score > old_score * 1.3:
						s.target = better
		if s.target == null:
			s.state = AIState.IDLE

	match s.state:
		AIState.IDLE:
			_drive_idle(s, delta)
		AIState.ATTACK:
			_drive_attack(s, delta)
		AIState.DEFEND:
			_drive_defend(s, delta, my_edge_factor)

func _drive_idle(s: SumoCarState, delta: float) -> void:
	var to_center: Vector3 = _sumo_manager.arena_center - s.body.global_position if _sumo_manager else -s.body.global_position
	to_center.y = 0.0
	var steer := _compute_steer(s, to_center, delta)
	_send_inputs(s, true, false, steer, false)

func _drive_attack(s: SumoCarState, delta: float) -> void:
	if s.target == null or not is_instance_valid(s.target):
		s.state = AIState.IDLE
		_send_inputs(s, true, false, 0.0, false)
		return

	var my_pos: Vector3 = s.body.global_position
	var target_pos: Vector3 = s.target.global_position
	var to_target: Vector3 = target_pos - my_pos
	var distance: float = to_target.length()
	to_target.y = 0.0

	var target_right: Vector3 = s.target.global_transform.basis.x
	var target_forward: Vector3 = -s.target.global_transform.basis.z
	var approach_dir: Vector3 = to_target.normalized()

	var from_behind: float = approach_dir.dot(target_forward)

	var aim_offset := Vector3.ZERO
	if abs(approach_dir.dot(target_right)) > 0.3:
		aim_offset = Vector3.ZERO
	elif from_behind > 0.2:
		var side_sign: float = sign(approach_dir.dot(target_right))
		if abs(side_sign) < 0.1:
			side_sign = 1.0 if randf() > 0.5 else -1.0
		aim_offset = target_right * side_sign * side_hit_offset
	else:
		var dodge_sign: float = 1.0 if randf() > 0.5 else -1.0
		aim_offset = target_right * dodge_sign * side_hit_offset * 2.0

	var aim_point: Vector3 = target_pos + aim_offset
	if distance > 5.0:
		var time_to_reach: float = distance / max(s.body.linear_velocity.length(), 10.0)
		aim_point += s.target.linear_velocity * time_to_reach * 0.5 * s.aggression

	var to_aim: Vector3 = aim_point - my_pos
	to_aim.y = 0.0

	var steer := _compute_steer(s, to_aim, delta)

	var accel := true
	var brake := false
	var handbrake := false

	var speed: float = s.body.linear_velocity.dot(-s.body.global_transform.basis.z)

	if distance < ram_boost_distance:
		accel = true
		if abs(steer) > 0.7 and speed > 15.0:
			handbrake = true
	else:
		if speed > attack_speed * s.aggression:
			accel = false

	_send_inputs(s, accel, brake, steer, handbrake)

func _drive_defend(s: SumoCarState, delta: float, edge_factor: float) -> void:
	var center: Vector3 = _sumo_manager.arena_center if _sumo_manager else Vector3.ZERO
	var to_center: Vector3 = center - s.body.global_position
	to_center.y = 0.0

	var steer := _compute_steer(s, to_center, delta)

	if edge_factor >= edge_critical_threshold:
		var velocity_toward_center: float = s.body.linear_velocity.normalized().dot(to_center.normalized())
		if velocity_toward_center < 0.2:
			_send_inputs(s, false, true, steer, false)
			return

	var speed: float = s.body.linear_velocity.dot(-s.body.global_transform.basis.z)
	var accel := speed < defend_speed
	_send_inputs(s, accel, false, steer, false)

func _select_target(s: SumoCarState) -> VehicleBody3D:
	var best_target: VehicleBody3D = null
	var best_score: float = -INF

	for car in _all_cars:
		if car == s.body:
			continue
		if not is_instance_valid(car):
			continue
		if car is not VehicleBody3D:
			continue

		var score := _score_target(s, car as VehicleBody3D)
		if score > best_score:
			best_score = score
			best_target = car as VehicleBody3D

	return best_target

func _score_target(s: SumoCarState, target: VehicleBody3D) -> float:
	if not is_instance_valid(target):
		return -INF

	var my_pos: Vector3 = s.body.global_position
	var target_pos: Vector3 = target.global_position
	var distance: float = my_pos.distance_to(target_pos)

	if distance > detection_range:
		return -INF

	var score: float = 1.0 - (distance / detection_range)

	var target_edge: float = _get_edge_factor(target)
	score += target_edge * edge_target_bonus

	var center: Vector3 = _sumo_manager.arena_center if _sumo_manager else Vector3.ZERO
	var target_forward: Vector3 = -target.global_transform.basis.z
	var target_to_center: Vector3 = (center - target_pos).normalized()
	var facing_out: float = -target_forward.dot(target_to_center)
	if facing_out > 0.0:
		score += facing_out * facing_outward_bonus

	var to_target: Vector3 = (target_pos - my_pos).normalized()
	var behind_factor: float = to_target.dot(target_forward)
	if behind_factor > 0.0:
		score += behind_factor * rear_hit_bonus

	score *= s.aggression

	return score

func _compute_steer(s: SumoCarState, world_dir: Vector3, delta: float) -> float:
	if world_dir.length_squared() < 0.001:
		return 0.0

	var local: Vector3 = s.body.global_transform.basis.inverse() * world_dir
	local.y = 0.0
	var desired_yaw: float = atan2(local.x, -local.z)
	var steer_cmd: float = clamp(desired_yaw * steer_gain, -1.0, 1.0)

	var yaw_rate: float = s.body.angular_velocity.y
	steer_cmd = clamp(steer_cmd - yaw_rate * 0.2, -1.0, 1.0)

	var alpha: float = clamp(steer_smooth * delta, 0.0, 1.0)
	s.steer_smoothed = lerp(s.steer_smoothed, steer_cmd, alpha)
	return s.steer_smoothed

func _check_stuck(s: SumoCarState, delta: float) -> bool:
	if s.is_reversing:
		s.reverse_timer -= delta
		if s.reverse_timer <= 0.0:
			s.is_reversing = false
			s.stuck_timer = 0.0
		else:
			_send_inputs(s, false, true, s.reverse_steer, false)
			return true

	s.position_check_timer += delta
	if s.position_check_timer >= 0.3:
		s.position_check_timer = 0.0
		var dist_moved: float = s.body.global_position.distance_to(s.last_position)
		s.last_position = s.body.global_position
		var speed: float = s.body.linear_velocity.length()

		if dist_moved < 0.3 and speed < stuck_speed_threshold:
			s.stuck_timer += 0.3
		else:
			s.stuck_timer = maxf(s.stuck_timer - 0.3, 0.0)

		if s.stuck_timer >= stuck_time_to_recover:
			s.is_reversing = true
			s.reverse_timer = reverse_duration
			s.stuck_timer = 0.0
			s.reverse_steer = (1.0 if randf() > 0.5 else -1.0) * reverse_steer_amount
			_send_inputs(s, false, true, s.reverse_steer, false)
			return true

	return false

func _get_edge_factor(car: Node) -> float:
	if _sumo_manager and _sumo_manager.has_method("get_edge_factor"):
		return _sumo_manager.get_edge_factor(car)
	var center: Vector3 = _sumo_manager.arena_center if _sumo_manager else Vector3.ZERO
	var radius: float = _sumo_manager.arena_radius if _sumo_manager else 40.0
	var pos: Vector3 = (car as Node3D).global_position
	var flat_pos := Vector2(pos.x, pos.z)
	var flat_center := Vector2(center.x, center.z)
	return flat_pos.distance_to(flat_center) / max(radius, 0.01)

func _send_inputs(s: SumoCarState, accel: bool, brake: bool, steer: float, handbrake: bool) -> void:
	if s.controller == null:
		_resolve_controller(s)
	if s.controller == null:
		return
	s.controller.call("set_ai_inputs", accel, brake, steer, handbrake)
