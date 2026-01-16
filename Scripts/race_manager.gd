extends Node

@export var total_laps: int = 3

var checkpoints: Array[Node] = []
var car_progress := {}
var race_started := false

var race_time: float = 0.0

func _process(delta: float) -> void:
	if race_started:
		race_time += delta

func _ready():
	if not is_in_group("race_manager"):
		add_to_group("race_manager")
		print("[RACE] RaceManager added to group 'race_manager'")
	else:
		print("[RACE] RaceManager already in group 'race_manager'")
	
	checkpoints = []
	for node in get_tree().get_nodes_in_group("checkpoint"):
		checkpoints.append(node)
	print("[RACE] Found checkpoints: ", checkpoints.size())
	checkpoints.sort_custom(self._sort_checkpoints)
	for cp in checkpoints:
		print("[RACE] checkpoint index=", cp.checkpoint_index)
	
	race_started = true
	race_time = 0.0
	print("[RACE] Race started")

func _sort_checkpoints(a, b):
	return a.checkpoint_index < b.checkpoint_index

func register_car(car: Node):
	print("[RACE] register_car called for ", car.name)
	car_progress[car] = {
		"next_index": 0,
		"lap": 0,
		"last_checkpoint": null,
		"lap_start_time": race_time,
		"last_lap_time": 0.0,
		"best_lap_time": -1.0,
	}

func unregister_car(car: Node):
	car_progress.erase(car)

func on_car_checkpoint(car: Node, checkpoint: Node):
	if not race_started:
		print("[RACE] Ignoring checkpoint, race not started")
		return
	if not car_progress.has(car):
		print("[RACE] Car not registered: ", car.name)
		return

	var state = car_progress[car]
	var expected_index = state["next_index"]
	var lap = state["lap"]
	var idx = checkpoint.checkpoint_index
	print("[RACE] Car ", car.name, " hit checkpoint ", idx, " expected ", expected_index)

	if idx == expected_index:
		state["last_checkpoint"] = checkpoint
		print("[RACE] Stored last checkpoint for ", car.name, " index=", idx)
		expected_index += 1
		if expected_index >= checkpoints.size():
			expected_index = 0
			var lap_time: float = race_time - float(state.get("lap_start_time", race_time))
			state["last_lap_time"] = lap_time
			var best: float = float(state.get("best_lap_time", -1.0))
			if best < 0.0 or lap_time < best:
				state["best_lap_time"] = lap_time
			state["lap_start_time"] = race_time
			lap += 1
		state["next_index"] = expected_index
		state["lap"] = lap
		car_progress[car] = state
		_on_car_progress_updated(car, lap, expected_index)

func _on_car_progress_updated(car: Node, lap: int, _next_index: int):
	print("[RACE] Progress car=", car.name, " lap=", lap, " next_index=", _next_index)
	if lap >= total_laps:
		race_started = false
		_on_race_finished(car)

func _on_race_finished(winner: Node):
	print("[RACE] Race finished! Winner: ", winner.name)

func get_last_checkpoint_for_car(car: Node) -> Node:
	if not car_progress.has(car):
		print("[RACE] get_last_checkpoint_for_car: car not registered: ", car.name)
		return null
	var cp = car_progress[car]["last_checkpoint"]
	if cp == null:
		print("[RACE] get_last_checkpoint_for_car: no checkpoint stored yet for ", car.name)
	else:
		print("[RACE] get_last_checkpoint_for_car: returning checkpoint index=", cp.checkpoint_index, " for ", car.name)
	return cp

func get_next_checkpoint_index_for_car(car: Node) -> int:
	if not car_progress.has(car):
		return 0
	return int(car_progress[car]["next_index"])

func get_current_lap(car: Node) -> int:
	if not car_progress.has(car):
		return 1
	return int(car_progress[car]["lap"]) + 1

func get_lap_time(car: Node) -> float:
	if not car_progress.has(car):
		return 0.0
	var state = car_progress[car]
	return race_time - float(state.get("lap_start_time", race_time))

func get_best_lap_time(car: Node) -> float:
	if not car_progress.has(car):
		return -1.0
	return float(car_progress[car].get("best_lap_time", -1.0))

func get_position(car: Node) -> int:
	if not car_progress.has(car):
		return 1
	var cars: Array = car_progress.keys()
	cars.sort_custom(func(a: Node, b: Node) -> bool:
		var sa = car_progress[a]
		var sb = car_progress[b]
		var la: int = int(sa.get("lap", 0))
		var lb: int = int(sb.get("lap", 0))
		if la != lb:
			return la > lb
		var na: int = int(sa.get("next_index", 0))
		var nb: int = int(sb.get("next_index", 0))
		if na != nb:
			return na > nb
		return _distance_to_next_checkpoint(a) < _distance_to_next_checkpoint(b)
	)
	var idx: int = cars.find(car)
	return (idx + 1) if idx >= 0 else 1

func get_gap_to_ahead_meters(car: Node) -> float:
	if not car_progress.has(car):
		return 0.0
	var cars: Array = car_progress.keys()
	cars.sort_custom(func(a: Node, b: Node) -> bool:
		var sa = car_progress[a]
		var sb = car_progress[b]
		var la: int = int(sa.get("lap", 0))
		var lb: int = int(sb.get("lap", 0))
		if la != lb:
			return la > lb
		var na: int = int(sa.get("next_index", 0))
		var nb: int = int(sb.get("next_index", 0))
		if na != nb:
			return na > nb
		return _distance_to_next_checkpoint(a) < _distance_to_next_checkpoint(b)
	)
	var pos: int = cars.find(car)
	if pos <= 0:
		return 0.0
	var ahead: Node = cars[pos - 1]
	return _approx_gap_meters(car, ahead)

func _distance_to_next_checkpoint(car: Node) -> float:
	if checkpoints.is_empty() or not car_progress.has(car):
		return INF
	var next_idx: int = int(car_progress[car].get("next_index", 0))
	if next_idx < 0 or next_idx >= checkpoints.size():
		next_idx = 0
	var cp: Node3D = checkpoints[next_idx] as Node3D
	var c3d: Node3D = car as Node3D
	if cp == null or c3d == null:
		return INF
	return c3d.global_position.distance_to(cp.global_position)

func _approx_gap_meters(behind: Node, ahead: Node) -> float:
	if not car_progress.has(behind) or not car_progress.has(ahead):
		return 0.0
	var nb: int = int(car_progress[behind].get("next_index", 0))
	var na: int = int(car_progress[ahead].get("next_index", 0))
	var behind3d: Node3D = behind as Node3D
	var ahead3d: Node3D = ahead as Node3D
	if behind3d != null and ahead3d != null and nb == na:
		return behind3d.global_position.distance_to(ahead3d.global_position)
	var db: float = _distance_to_next_checkpoint(behind)
	var da: float = _distance_to_next_checkpoint(ahead)
	return max(0.0, db - da)
