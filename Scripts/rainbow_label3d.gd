extends Label3D

@export var rainbow_speed: float = 1.0
@export var rainbow_saturation: float = 0.8
@export var rainbow_value: float = 1.0

var _rainbow_time: float = 0.0

func _process(delta: float) -> void:
	_rainbow_time += delta * rainbow_speed
	var hue = fmod(_rainbow_time, 1.0)
	modulate = Color.from_hsv(hue, rainbow_saturation, rainbow_value, modulate.a)
