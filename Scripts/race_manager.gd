extends Node

@export var total_laps: int = 3

var checkpoints: Array[Node] = []
var car_progress := {}
var race_started := false

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
	print("[RACE] Race started")

func _sort_checkpoints(a, b):
	return a.checkpoint_index < b.checkpoint_index

func register_car(car: Node):
	print("[RACE] register_car called for ", car.name)
	car_progress[car] = {
		"next_index": 0,
		"lap": 0,
		"last_checkpoint": null
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
