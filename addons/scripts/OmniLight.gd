extends OmniLight3D

@export var target: NodePath
@export var min_intensity: float = 0.4
@export var max_intensity: float = 1.0
@export var max_distance: float = 15.0

var player: Node3D

func _ready():
	if target != NodePath():
		player = get_node(target)

func _process(delta):
	if player:
		var dist = global_position.distance_to(player.global_position)

		var intensity = lerp(max_intensity, min_intensity, clamp(dist / max_distance, 0.0, 1.0))

		light_energy = intensity
