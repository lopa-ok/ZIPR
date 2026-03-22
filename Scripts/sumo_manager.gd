extends Node

@export_group("Arena")
@export var arena_center: Vector3 = Vector3.ZERO
@export var arena_radius: float = 40.0
@export var fall_threshold: float = -10.0
@export var show_arena_gizmo: bool = true

@export_group("Game Rules")
@export var countdown_duration: float = 3.0
@export var round_time_limit: float = 120.0
@export var elimination_respawn: bool = false

@export_group("Spawning")
@export var ai_count: int = 5

signal car_eliminated(car: Node, reason: String)
signal round_started()
signal round_ended(winner: Node)

var registered_cars: Array[Node] = []
var alive_cars: Array[Node] = []
var eliminated_cars: Array[Node] = []
var elimination_log: Array[Dictionary] = []

var spawn_points: Array[Node] = []
var game_started: bool = false
var countdown_active: bool = false
var countdown_timer: float = 0.0
var go_display_timer: float = 0.0
var round_timer: float = 0.0

var race_started: bool = false

func _ready() -> void:
	Global.current_game_mode = Global.GameMode.SUMO

	if not is_in_group("sumo_manager"):
		add_to_group("sumo_manager")
	if not is_in_group("race_manager"):
		add_to_group("race_manager")

	var center_node: Node3D = get_tree().get_first_node_in_group("arena_center") as Node3D
	if center_node:
		arena_center = center_node.global_position

	spawn_points.clear()
	for node in get_tree().get_nodes_in_group("spawn_point"):
		spawn_points.append(node)
	spawn_points.sort_custom(func(a, b): return a.spawn_index < b.spawn_index)

	Global.reset_ai_assignments()
	call_deferred("_spawn_cars")

	if SoundManager:
		SoundManager.play_music("res://resources/models/Music/MainTrack.mp3", -10.0)

	_start_countdown()

func _process(delta: float) -> void:
	if countdown_active:
		var last_int = ceil(countdown_timer)
		countdown_timer -= delta
		var current_int = ceil(countdown_timer)
		if current_int < last_int and current_int > 0:
			_play_countdown_beep()
		if countdown_timer <= 0.0:
			countdown_active = false
			game_started = true
			race_started = true
			round_timer = 0.0
			go_display_timer = 2.0
			round_started.emit()
			if SoundManager:
				SoundManager.play_sfx("res://resources/models/Music/beep.mp3", 0.0, 1.5)
		return

	if not game_started:
		return

	round_timer += delta
	if go_display_timer > 0.0:
		go_display_timer -= delta

	_check_eliminations()

	var _player_alive := false
	var _ai_alive_count := 0
	for car in alive_cars:
		if not car.get("is_ai_controlled"):
			_player_alive = true
		else:
			_ai_alive_count += 1

	if alive_cars.size() <= 1:
		_end_round(alive_cars[0] if alive_cars.size() == 1 else null)
	elif round_time_limit > 0.0 and round_timer >= round_time_limit:
		var best_car: Node = null
		var best_dist: float = INF
		for car in alive_cars:
			var d: float = (car as Node3D).global_position.distance_to(arena_center)
			if d < best_dist:
				best_dist = d
				best_car = car
		_end_round(best_car)

func _check_eliminations() -> void:
	var to_eliminate: Array[Node] = []
	for car in alive_cars:
		var car3d := car as Node3D
		if not car3d or not is_instance_valid(car3d):
			to_eliminate.append(car)
			continue

		var pos: Vector3 = car3d.global_position
		if pos.y < fall_threshold:
			to_eliminate.append(car)
			continue

		var flat_pos := Vector2(pos.x, pos.z)
		var flat_center := Vector2(arena_center.x, arena_center.z)
		if flat_pos.distance_to(flat_center) > arena_radius:
			to_eliminate.append(car)

	for car in to_eliminate:
		_eliminate_car(car, "fell off the arena")

func _eliminate_car(car: Node, reason: String) -> void:
	if car in eliminated_cars:
		return
	alive_cars.erase(car)
	eliminated_cars.append(car)
	elimination_log.append({
		"car_name": str(car.name) if car else "Unknown",
		"time": round_timer,
		"reason": reason
	})
	car_eliminated.emit(car, reason)
	print("[SUMO] Eliminated: ", car.name, "  ", reason)

	if car is VehicleBody3D:
		(car as VehicleBody3D).engine_force = 0.0
		(car as VehicleBody3D).brake = 100.0
	car.set_physics_process(false)
	car.set_process(false)

	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func():
		if is_instance_valid(car):
			(car as Node3D).visible = false
	)

func _end_round(winner: Node) -> void:
	if not game_started:
		return
	game_started = false
	race_started = false
	round_ended.emit(winner)
	if winner:
		print("[SUMO] Round over! Winner: ", winner.name)
	else:
		print("[SUMO] Round over! No winner (draw).")

func register_car(car: Node) -> void:
	if car in registered_cars:
		return
	registered_cars.append(car)
	alive_cars.append(car)

func is_car_alive(car: Node) -> bool:
	return car in alive_cars

func get_alive_count() -> int:
	return alive_cars.size()

func get_round_time() -> float:
	return round_timer

func get_arena_center() -> Vector3:
	return arena_center

func get_arena_radius() -> float:
	return arena_radius

func get_elimination_log() -> Array[Dictionary]:
	return elimination_log

func get_edge_factor(car: Node) -> float:
	if not car or not is_instance_valid(car):
		return 1.0
	var pos: Vector3 = (car as Node3D).global_position
	var flat_pos := Vector2(pos.x, pos.z)
	var flat_center := Vector2(arena_center.x, arena_center.z)
	return flat_pos.distance_to(flat_center) / max(arena_radius, 0.01)

func get_countdown_text() -> String:
	if countdown_active:
		return str(ceil(countdown_timer))
	if game_started and go_display_timer > 0.0:
		return "GO!"
	return ""

func _spawn_cars() -> void:
	if spawn_points.is_empty():
		print("[SUMO] No spawn points found!")
		return

	var player_spawn: Node = null
	for sp in spawn_points:
		if sp.is_player_start:
			player_spawn = sp
			break
	if player_spawn == null and not spawn_points.is_empty():
		player_spawn = spawn_points[0]

	if player_spawn:
		_spawn_single_car(player_spawn, false)

	var ai_spawned := 0
	for sp in spawn_points:
		if sp == player_spawn:
			continue
		_spawn_single_car(sp, true)
		ai_spawned += 1
		if ai_spawned >= ai_count:
			break

func _spawn_single_car(spawn_point: Node, is_ai: bool) -> void:
	var car_scene = load("res://Scenes/Car.tscn")
	var car = car_scene.instantiate()
	car.global_transform = spawn_point.global_transform
	if is_ai:
		car.is_ai_controlled = true
		car.car_name = "AI Car " + str(spawn_point.spawn_index)
		car.name = "AI_Car_" + str(spawn_point.spawn_index)
	else:
		car.is_ai_controlled = false
	get_tree().current_scene.add_child(car)
	register_car(car)
	print("[SUMO] Spawned ", car.name, " at ", spawn_point.name)

	if is_ai:
		var ai_manager = get_tree().get_first_node_in_group("sumo_ai_manager")
		if ai_manager and ai_manager.has_method("register_ai_car"):
			ai_manager.register_ai_car(car)
		else:
			print("[SUMO] WARNING: No Sumo AI Manager found for ", car.name)

func _start_countdown() -> void:
	countdown_timer = countdown_duration
	countdown_active = true
	race_started = false
	game_started = false
	_play_countdown_beep()

func _play_countdown_beep() -> void:
	if SoundManager:
		SoundManager.play_sfx("res://resources/models/Music/beep.mp3", -5.0, 1.0)

func get_last_checkpoint_for_car(_car: Node) -> Node:
	return null

func get_next_checkpoint_index_for_car(_car: Node) -> int:
	return 0

func get_current_lap(_car: Node) -> int:
	return 1

func get_lap_time(_car: Node) -> float:
	return round_timer

func get_best_lap_time(_car: Node) -> float:
	return -1.0

func get_position(car: Node) -> int:
	if car in eliminated_cars:
		return eliminated_cars.size() + alive_cars.size() - eliminated_cars.find(car)
	if car in alive_cars:
		var sorted_cars := alive_cars.duplicate()
		sorted_cars.sort_custom(func(a, b):
			var da = (a as Node3D).global_position.distance_to(arena_center)
			var db = (b as Node3D).global_position.distance_to(arena_center)
			return da < db
		)
		return sorted_cars.find(car) + 1
	return registered_cars.size()

func get_gap_to_ahead_meters(_car: Node) -> float:
	return 0.0

func on_car_checkpoint(_car: Node, _checkpoint: Node) -> void:
	pass
