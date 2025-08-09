extends CharacterBody3D

const BASE_SPEED = 5.0
const SPRINT_SPEED = 9.0
const CROUCH_SPEED = 2.5
const SLIDE_SPEED = 12.0
const ACCELERATION = 6.0
const GRAVITY = 9.8
const JUMP_VELOCITY = 4.5
const WALL_RUN_SPEED = 6.0
const WALL_RUN_GRAVITY = 3.0
const WALL_JUMP_PUSH = 4.0
const WALL_JUMP_TIME = 0.2
const MOUSE_SENSITIVITY = 0.003
const CROUCH_HEIGHT = 1.0
const STAND_HEIGHT = 2.0
const SLIDE_TIME = 0.6
const MAX_TILT_ANGLE = deg_to_rad(15)  # max tilt in radians (~15 degrees)
const TILT_SPEED = 6.0               # how fast the tilt interpolates

@onready var head = $Camera3D
@onready var collider = $CollisionShape3D  # For crouching height change

var camera_rot = Vector2.ZERO
var mouse_captured := true
var horizontal_velocity: Vector3 = Vector3.ZERO

var is_crouching = false
var is_sprinting = false
var is_sliding = false
var slide_timer = 0.0

# Wallrun variables
var wall_normal = Vector3.ZERO
var wall_jump_timer = 0.0
var is_wall_running = false
var target_tilt = 0.0
var current_tilt = 0.0

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

	# Choose speed based on state
	var target_speed = BASE_SPEED
	if is_sliding:
		target_speed = SLIDE_SPEED
	elif is_sprinting:
		target_speed = SPRINT_SPEED
	elif is_crouching:
		target_speed = CROUCH_SPEED
	elif is_wall_running:
		target_speed = WALL_RUN_SPEED

	# Calculate horizontal velocity with acceleration smoothing
	var target_velocity = input_dir * target_speed
	horizontal_velocity = horizontal_velocity.lerp(target_velocity, clamp(ACCELERATION * delta, 0, 1))

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	# Apply gravity
	if not is_on_floor():
		if is_wall_running:
			velocity.y -= WALL_RUN_GRAVITY * delta
		else:
			velocity.y -= GRAVITY * delta
	else:
		# Reset wallrun when grounded
		is_wall_running = false
		wall_jump_timer = 0.0
		# Jump from ground
		if Input.is_action_just_pressed("jump") and not is_crouching:
			velocity.y = JUMP_VELOCITY
	# Slide down slope when crouching
	slide_down_slope(delta)
	# Move character
	move_and_slide()

	# Detect wall for wallrun
	if not is_on_floor():
		var found_wall = false
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var normal = collision.get_normal()
			# Check if mostly vertical wall
			if abs(normal.y) < 0.1:
				wall_normal = normal
				wall_jump_timer = WALL_JUMP_TIME
				# Wallrun conditions: moving forward and near wall
				if input_dir != Vector3.ZERO and Input.is_action_pressed("move_forward"):
					is_wall_running = true
				found_wall = true
				break
		if not found_wall:
			is_wall_running = false
	else:
		is_wall_running = false

	# Reduce wall jump timer over time
	wall_jump_timer = max(wall_jump_timer - delta, 0)

	# Handle wall jump input
	if Input.is_action_just_pressed("jump"):
		if wall_jump_timer > 0 and not is_on_floor():
			wall_jump()

	# --- Camera tilt for wallrunning ---
	# Make sure these variables exist in your script:
	# var target_tilt = 0.0
	# var current_tilt = 0.0
	# const MAX_TILT_ANGLE = deg2rad(15)
	# const TILT_SPEED = 6.0

	if is_wall_running:
		var right_dir = transform.basis.x.normalized()
		if wall_normal.dot(right_dir) > 0:
			target_tilt = -MAX_TILT_ANGLE
		else:
			target_tilt = MAX_TILT_ANGLE
	else:
		target_tilt = 0.0

	current_tilt = lerp(current_tilt, target_tilt, TILT_SPEED * delta)
	head.rotation.z = current_tilt

func wall_jump():
	velocity = wall_normal * WALL_JUMP_PUSH
	velocity.y = JUMP_VELOCITY
	is_wall_running = false
	wall_jump_timer = 0

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

func slide_down_slope(delta):
	if not is_crouching or is_sliding:
		return
	
	if is_on_floor():
		var floor_normal = get_floor_normal()
		# Calculate slope angle from the floor normal and up vector
		var slope_angle = rad_to_deg(acos(floor_normal.dot(Vector3.UP)))
		# Define a slide threshold angle (e.g., anything steeper than 20 degrees)
		const SLIDE_ANGLE_THRESHOLD = 20.0
		
		if slope_angle > SLIDE_ANGLE_THRESHOLD:
			# Project gravity along the slope to slide down
			var slide_dir = Vector3(floor_normal.x, 0, floor_normal.z).normalized()
			velocity += slide_dir * GRAVITY * delta * 10  # Slide speed multiplier (tweak as needed)
		else:
			# If slope is gentle enough, stop sliding down
			velocity.x = 0
			velocity.z = 0
