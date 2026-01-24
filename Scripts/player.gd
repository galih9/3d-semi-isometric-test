extends Node3D

# --- Configuration ---
@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var jump_velocity: float = 4.5
@export var acceleration: float = 10.0
@export var friction: float = 10.0
@export var air_control: float = 0.3
@export var rotation_speed: float = 10.0

@export_group("Camera")
@export var camera_distance: float = 8.0
@export var camera_height: float = 6.0
@export var camera_angle: float = -45.0 # Base isometric angle in degrees
@export var camera_smoothness: float = 5.0
@export var mouse_sensitivity: float = 0.3 # Mouse rotation sensitivity
@export var vertical_limit: float = 15.0 # Max degrees up/down from base angle

# --- Nodes ---
@onready var character_body: CharacterBody3D = $CharacterBody3D
@onready var anim_player: AnimationPlayer = $CharacterBody3D/AnimationPlayer
@onready var skeleton: Skeleton3D = $CharacterBody3D/Skeleton3D

# Camera pivot nodes (will be set from player scene)
var camera_pivot: Node3D = null
var camera: Camera3D = null

# --- Camera State ---
var _camera_yaw: float = 0.0 # Horizontal rotation
var _camera_pitch: float = 0.0 # Vertical rotation (limited)

# --- State ---
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	_setup_inputs()
	
	# Find camera nodes within the player scene
	camera_pivot = character_body.get_node_or_null("CameraPivot")
	if camera_pivot:
		camera = camera_pivot.get_node_or_null("Camera3D")
	
	if not camera or not camera_pivot:
		push_warning("Camera setup not found! Make sure CharacterBody3D/CameraPivot/Camera3D exists")
	
	# Capture mouse for Tacticool-style aiming
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not character_body:
		return

	# Apply Gravity
	if not character_body.is_on_floor():
		character_body.velocity.y -= _gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and character_body.is_on_floor():
		character_body.velocity.y = jump_velocity

	# Get Reference Camera (Active Viewport Camera)
	var cam = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO
	
	if cam:
		# Calculate direction relative to Camera
		# IMPORTANT: get_vector returns (param1-param2, param3-param4)
		# So for forward/back to work correctly with camera basis, we need move_back first, then move_forward
		var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		
		var cam_basis = cam.global_transform.basis
		# In Godot, basis.z points BACKWARD, so we negate it to get forward
		var forward = - cam_basis.z
		var right = cam_basis.x
		
		# Flatten vectors
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		direction = (forward * input_dir.y + right * input_dir.x).normalized()
	
	# Determine Speed
	var current_speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	
	# Apply Movement
	var target_vel_x = direction.x * current_speed
	var target_vel_z = direction.z * current_speed
	
	var accel = acceleration if character_body.is_on_floor() else acceleration * air_control
	var fric = friction if character_body.is_on_floor() else friction * air_control
	
	if direction:
		character_body.velocity.x = move_toward(character_body.velocity.x, target_vel_x, accel * delta)
		character_body.velocity.z = move_toward(character_body.velocity.z, target_vel_z, accel * delta)
		
		# --- Rotation (Face Movement Direction) ---
		# Only rotate when moving forward or sideways, not when backpedaling
		# Check if we're moving more forward than backward
		var camera_ref = get_viewport().get_camera_3d()
		if camera_ref:
			var cam_forward = - camera_ref.global_transform.basis.z
			cam_forward.y = 0
			cam_forward = cam_forward.normalized()
			var move_dot = direction.dot(cam_forward)
			
			# Only rotate if moving forward or sideways (not backward)
			if move_dot > -0.3: # Allow slight backward movement before stopping rotation
				var target_angle = atan2(direction.x, direction.z)
				var current_angle = skeleton.rotation.y
				skeleton.rotation.y = lerp_angle(current_angle, target_angle, rotation_speed * delta)
		
	else:
		character_body.velocity.x = move_toward(character_body.velocity.x, 0, fric * delta)
		character_body.velocity.z = move_toward(character_body.velocity.z, 0, fric * delta)

	# --- Execute Move ---
	character_body.move_and_slide()
	
	# --- Sync Root ---
	# --- Sync Root ---
	# Sync logic must handle rotation. We snap the parent to the child's new global location,
	# then reset the child to local zero.
	if character_body.position != Vector3.ZERO:
		var target_global_pos = character_body.global_position
		global_position = target_global_pos
		character_body.position = Vector3.ZERO

	# --- Camera Follow ---
	_update_camera(direction, delta)
	
	# --- Animations ---
	_update_animations(direction)

func _update_animations(direction: Vector3) -> void:
	if not character_body.is_on_floor():
		pass
	elif direction.length_squared() > 0.01:
		if Input.is_action_pressed("sprint"):
			if anim_player.current_animation != "sprint":
				anim_player.play("sprint", 0.2)
		else:
			if anim_player.current_animation != "walk":
				anim_player.play("walk", 0.2)
	else:
		if anim_player.current_animation != "idle":
			anim_player.play("idle", 0.2)

func _update_camera(_direction: Vector3, _delta: float) -> void:
	if not camera_pivot or not camera:
		return
	
	# Apply horizontal rotation to camera pivot (yaw)
	camera_pivot.rotation.y = _camera_yaw
	
	# Apply vertical rotation to camera (pitch) - limited range
	var base_pitch = deg_to_rad(camera_angle)
	var pitch_offset = deg_to_rad(_camera_pitch)
	camera.rotation.x = base_pitch + pitch_offset

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse motion for camera rotation (Tacticool-style aiming)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Accumulate rotation based on mouse movement
		_camera_yaw -= event.relative.x * mouse_sensitivity * 0.01 # Horizontal rotation (left/right)
		_camera_pitch -= event.relative.y * mouse_sensitivity * 0.01 # Vertical rotation (up/down)
		
		# Clamp vertical rotation to limited range
		_camera_pitch = clamp(_camera_pitch, -vertical_limit, vertical_limit)
	
	# Toggle mouse mode with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _setup_inputs() -> void:
	if not InputMap.has_action("move_forward"): _add_key_action("move_forward", KEY_W)
	if not InputMap.has_action("move_back"): _add_key_action("move_back", KEY_S)
	if not InputMap.has_action("move_left"): _add_key_action("move_left", KEY_A)
	if not InputMap.has_action("move_right"): _add_key_action("move_right", KEY_D)
	if not InputMap.has_action("jump"): _add_key_action("jump", KEY_SPACE)
	if not InputMap.has_action("sprint"): _add_key_action("sprint", KEY_SHIFT)

func _add_key_action(action_name: String, key_code: int) -> void:
	InputMap.add_action(action_name)
	var ev = InputEventKey.new()
	ev.physical_keycode = key_code
	InputMap.action_add_event(action_name, ev)
