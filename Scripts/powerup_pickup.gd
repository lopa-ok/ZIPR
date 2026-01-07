extends Area3D

@export var available_powerups := ["speed_boost", "oil", "water_balloon"]
@export var respawn_time := 3.0

var is_active := true

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body):
	if body.has_method("has_powerup_func") and body.has_powerup_func():
		return
	if body.has_method("pickup_powerup"):
		var powerup_name = available_powerups[randi() % available_powerups.size()]
		var powerup = Powerup.new()
		powerup.powerup_name = powerup_name
		body.pickup_powerup(powerup)
		_hide_and_respawn()

func _hide_and_respawn():
	is_active = false
	visible = false
	$CollisionShape3D.call_deferred("set_disabled", true)
	await get_tree().create_timer(respawn_time).timeout
	is_active = true
	visible = true
	$CollisionShape3D.call_deferred("set_disabled", false)
