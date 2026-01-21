extends Node3D

# --- Configuration ---
@export_category("Powerup Settings")
@export var powerup_types: Array[String] = ["speed_boost", "oil", "water_balloon"]
@export var respawn_time: float = 5.0

@export_category("Visuals")
@export var rotate_speed: float = 90.0
@export var float_height: float = 0.5
@export var float_speed: float = 2.0

# --- Internal State ---
var _base_y: float = 0.0
var _float_phase: float = 0.0
var _current_powerup: String = ""

# --- Node References ---
@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var area: Area3D = $Area3D
@onready var collision_shape: CollisionShape3D = $Area3D/CollisionShape3D
# Using get_node_or_null allows the script to work even if you haven't added particles yet
@onready var particles: GPUParticles3D = get_node_or_null("Particles")

func _ready():
	# Capture starting height
	_base_y = position.y
	_randomize_powerup()
	
	# Connect signals safely
	# We connect to the Area3D specifically, not "self"
	if area:
		if not area.body_entered.is_connected(_on_body_entered):
			area.body_entered.connect(_on_body_entered)
	else:
		printerr("CRITICAL: Powerup missing Area3D child node!")

func _process(delta):
	# Rotate the root
	rotation.y += deg_to_rad(rotate_speed) * delta
	
	# Float the mesh specifically (keeps the collider stable)
	_float_phase += delta * float_speed
	if mesh:
		mesh.position.y = sin(_float_phase) * float_height

func _on_body_entered(body):
	# Double check: if mesh is hidden, we shouldn't be pickable
	# (Prevents race conditions where 2 bodies enter same frame)
	if mesh and not mesh.visible:
		return

	if body.has_method("pickup_powerup"):
		body.pickup_powerup(self)
		_on_collected()

func _on_collected():
	# 1. Play Particle Effect (if exists)
	if particles:
		particles.restart()
		particles.emitting = true
	
	# 2. Hide the MESH only (Keep root visible so particles can play)
	if mesh:
		mesh.visible = false
		
	# 3. CRITICAL FIX: Use set_deferred to safely disable physics
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if area:
		area.set_deferred("monitoring", false)

	# 4. Stop floating animation to save resources
	set_process(false)
	
	# 5. Start Respawn Timer
	await get_tree().create_timer(respawn_time).timeout
	_respawn()

func _respawn():
	_randomize_powerup()
	
	# Re-enable visuals
	if mesh:
		mesh.visible = true
		
	# Re-enable physics safely
	if collision_shape:
		collision_shape.set_deferred("disabled", false)
	if area:
		area.set_deferred("monitoring", true)
		
	set_process(true)

func _randomize_powerup():
	if powerup_types.size() > 0:
		_current_powerup = powerup_types.pick_random()

func get_powerup_type() -> String:
	return _current_powerup
