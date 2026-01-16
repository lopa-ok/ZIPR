extends Node

var selected_car_id: int = 0

var car_stats: Dictionary = {
	0: {
		"name": "Taxi",
		"max_engine_force": 230.0,
		"max_steering": 0.8,
		"steering_speed": 2.5,
		"max_speed": 70.0,
		"drift_factor": 0.96,
		"body_tilt": 22.0,
		"mesh_scene": "res://Scenes/Car_Taxi.tscn"
	},
	1: {
		"name": "Sedan Sports",
		"max_engine_force": 270.0,
		"max_steering": 0.9,
		"steering_speed": 2.8,
		"max_speed": 85.0,
		"drift_factor": 0.92,
		"body_tilt": 28.0,
		"mesh_scene": "res://Scenes/Car_SedanSports.tscn"
	},
	2: {
		"name": "Firetruck",
		"max_engine_force": 300.0,
		"max_steering": 0.6,
		"steering_speed": 1.5,
		"max_speed": 60.0,
		"drift_factor": 0.99,
		"body_tilt": 15.0,
		"mesh_scene": "res://Scenes/Car_Firetruck.tscn"
	},
	3: {
		"name": "Hatchback Sports",
		"max_engine_force": 250.0,
		"max_steering": 1.1,
		"steering_speed": 3.2,
		"max_speed": 78.0,
		"drift_factor": 0.88,
		"body_tilt": 30.0,
		"mesh_scene": "res://Scenes/Car_HatchbackSports.tscn"
	},
	4: {
		"name": "Police",
		"max_engine_force": 280.0,
		"max_steering": 0.85,
		"steering_speed": 2.6,
		"max_speed": 92.0,
		"drift_factor": 0.94,
		"body_tilt": 25.0,
		"mesh_scene": "res://Scenes/Car_Police.tscn"
	},
	5: {
		"name": "Ambulance", 
		"max_engine_force": 260.0,
		"max_steering": 0.7,
		"steering_speed": 2.0,
		"max_speed": 68.0,
		"drift_factor": 0.97,
		"body_tilt": 18.0,
		"mesh_scene": "res://Scenes/Car_Ambulance.tscn"
	}
}

var used_ai_ids: Array = []

func reset_ai_assignments() -> void:
	used_ai_ids.clear()

func get_unique_ai_car_id() -> int:
	var available: Array = car_stats.keys()
	available.erase(selected_car_id)
	
	var candidates: Array = []
	for id in available:
		if not id in used_ai_ids:
			candidates.append(id)
	
	if candidates.is_empty():
		candidates = available
		
	if candidates.is_empty():
		return selected_car_id
		
	var picked = candidates.pick_random()
	used_ai_ids.append(picked)
	return picked
