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

# --- Nodes ---
@onready var character_body: CharacterBody3D = $CharacterBody3D
@onready var anim_player: AnimationPlayer = $CharacterBody3D/AnimationPlayer

# --- State ---
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	_setup_inputs()
	# Optional: Capture mouse if you still want to hide the cursor, 
	# otherwise you can remove this or set to VISIBLE.
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
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		
		var cam_basis = cam.global_transform.basis
		var forward = cam_basis.z
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
		# Get target rotation angle
		var target_angle = atan2(direction.x, direction.z)
		# Smoothly interpolate current rotation to target rotation
		var current_angle = rotation.y
		rotation.y = lerp_angle(current_angle, target_angle, rotation_speed * delta)
		
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
			
func _unhandled_input(event: InputEvent) -> void:
	# Keep escape to uncapture mouse just in case
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
