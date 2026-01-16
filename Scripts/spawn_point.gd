extends Node3D

@export var is_player_start: bool = false
@export var spawn_index: int = 0

func _ready() -> void:
	visible = false
	add_to_group("spawn_point")
