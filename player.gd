extends CharacterBody3D

const BASE_SPEED = 5.0
const SPRINT_SPEED = 9.0
const CROUCH_SPEED = 2.5
const SLIDE_SPEED = 12.0
const ACCELERATION = 6.0
const GRAVITY = 9.8
const JUMP_VELOCITY = 4.5
const WALL_JUMP_VELOCITY = 50
const MOUSE_SENSITIVITY = 0.003

const CROUCH_HEIGHT = 1.0
const STAND_HEIGHT = 2.0
const SLIDE_TIME = 0.6

@onready var head = $Camera3D
@onready var collider = $CollisionShape3D  # For crouching height change

var camera_rot = Vector2.ZERO
var mouse_captured := true
var horizontal_velocity: Vector3 = Vector3.ZERO

var is_crouching = false
var is_sprinting = false
var is_sliding = false
var slide_timer = 0.0

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	if event is InputEventMouseMotion and mouse_captured:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_rot.x = clamp(camera_rot.x - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-89), deg_to_rad(89))
		head.rotation.x = camera_rot.x

	elif event is InputEventKey and event.pressed:
		if event.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			mouse_captured = false

	elif event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		mouse_captured = true

func _physics_process(delta):
	if not mouse_captured:
		return

	handle_states(delta)

	var input_dir = Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		input_dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += transform.basis.x

	input_dir = input_dir.normalized()

	var target_speed = BASE_SPEED
	if is_sliding:
		target_speed = SLIDE_SPEED
	elif is_sprinting:
		target_speed = SPRINT_SPEED
	elif is_crouching:
		target_speed = CROUCH_SPEED

	var target_velocity = input_dir * target_speed
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, clamp(ACCELERATION * delta, 0, 1))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not is_crouching:
		velocity.y = JUMP_VELOCITY

	move_and_slide()

func handle_states(delta):
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching and !is_sliding

	if Input.is_action_just_pressed("slide") and is_on_floor() and velocity.length() > 0.1:
		start_slide()
	elif Input.is_action_just_pressed("crouch") and !is_sliding:
		toggle_crouch(true)

	if Input.is_action_just_released("crouch") and !is_sliding:
		toggle_crouch(false)

	if is_sliding:
		slide_timer -= delta
		if slide_timer <= 0.0:
			is_sliding = false
			toggle_crouch(false)  # End slide into crouch

func toggle_crouch(enable: bool):
	is_crouching = enable
	var shape = collider.shape
	if shape is CapsuleShape3D:
		shape.height = CROUCH_HEIGHT if enable else STAND_HEIGHT
		collider.shape = shape

func start_slide():
	is_sliding = true
	slide_timer = SLIDE_TIME
	toggle_crouch(true)  # Temporarily lower collider
