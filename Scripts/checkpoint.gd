extends Area3D

@export var checkpoint_index: int = 0



func _ready():
	body_entered.connect(_on_body_entered)



func _on_body_entered(body: Node):
	if body.has_method("on_checkpoint_passed"):
		body.on_checkpoint_passed(self)
