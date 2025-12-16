extends Node3D

@onready var Ball = $Ball
@onready var Car = $Car
@onready var RightWheel = $"Car/Model/wheel-front-right"
@onready var LeftWheel = $"Car/Model/wheel-front-left"
@onready var CarBody = $Car/Model/body
@onready var Camera = $Camera3D


var acceleration = 80.0
var steering = 18.0
var turn_speed = 6.0
var body_tilt = 30
var camera_distance = 3.5
var camera_height = 2.0
var camera_smoothness = 5.0

var max_speed = 40.0
var grip = 0.88


var speed_input = 0 
var rotate_input = 0


func _physics_process(delta):
	var car_offset = Vector3(0, -0.5, 0)
	Car.transform.origin = Ball.transform.origin + car_offset
	
	var velocity = Ball.linear_velocity
	var speed = velocity.length()
	
	if speed > max_speed:
		Ball.linear_velocity = velocity.normalized() * max_speed
	
	var forward_velocity = -Car.global_transform.basis.z * velocity.dot(-Car.global_transform.basis.z)
	var lateral_velocity = Car.global_transform.basis.x * velocity.dot(Car.global_transform.basis.x)
	Ball.linear_velocity = Ball.linear_velocity.lerp(forward_velocity + lateral_velocity * grip, delta * 12)
	
	Ball.apply_central_force(Car.global_transform.basis.z * speed_input)
	
	var target_position = Car.global_transform.origin - Car.global_transform.basis.z * camera_distance + Vector3.UP * camera_height
	Camera.global_transform.origin = Camera.global_transform.origin.lerp(target_position, camera_smoothness * delta)
	Camera.look_at(Car.global_transform.origin + Vector3.UP * 0.5, Vector3.UP)

func _process(delta):
	speed_input = Input.get_action_strength("Accelerate") * acceleration
	
	if Input.is_action_pressed("Brake"):
		speed_input -= acceleration * 0.5
	
	rotate_input = deg_to_rad(steering) * (Input.get_action_strength("SteerLeft") - Input.get_action_strength("SteerRight"))
	
	RightWheel.rotation.y = rotate_input
	LeftWheel.rotation.y = rotate_input
	
	var speed = Ball.linear_velocity.length()
	if speed > 2.0:
		RotateCar(delta)

func RotateCar(delta):
	var new_basis = Car.global_transform.basis.rotated(Car.global_transform.basis.y, rotate_input)
	Car.global_transform.basis = Car.global_transform.basis.slerp(new_basis, turn_speed * delta)
	
	var tilt = -rotate_input * Ball.linear_velocity.length() / body_tilt
	CarBody.rotation.z = lerp(CarBody.rotation.z, tilt, 10 * delta)
