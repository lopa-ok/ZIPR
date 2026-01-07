extends Powerup


var powerup_pool := ["speed_boost", "oil", "water_balloon"]



func _ready():
	powerup_name = powerup_pool[randi() % powerup_pool.size()]
	super._ready()
