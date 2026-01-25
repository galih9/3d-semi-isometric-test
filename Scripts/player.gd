extends CharacterBody3D

signal health_changed(current_hp, max_hp)
signal player_died

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
@export var camera_angle: float = -45.0
@export var camera_smoothness: float = 5.0
@export var mouse_sensitivity: float = 0.3
@export var vertical_limit: float = 15.0

# --- Nodes ---
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var skeleton: Skeleton3D = $Skeleton3D

# Camera pivot nodes (will be set from player scene)
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot")
@onready var camera: Camera3D = get_node_or_null("CameraPivot/Camera3D")

# Gun system
var gun: Node3D = null
var is_gun_equipped: bool = false

# --- Camera State ---
var _camera_yaw: float = 0.0
var _camera_pitch: float = 0.0

# --- State ---
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _anim_playback: AnimationNodeStateMachinePlayback

# --- Health State ---
@export var max_hp: float = 100.0
var current_hp: float = max_hp

func _ready() -> void:
	_setup_inputs()
	
	if not camera or not camera_pivot:
		push_warning("Camera setup not found! Make sure CameraPivot/Camera3D exists")
	
	# Setup gun
	gun = get_node_or_null("Skeleton3D/arm-right/GunAttachPoint/Gun")
	if gun:
		gun.visible = is_gun_equipped
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Setup AnimationTree programmatically
	_setup_animation_tree()
	
	# Emit initial health
	call_deferred("emit_signal", "health_changed", current_hp, max_hp)

func take_damage(amount: float) -> void:
	current_hp -= amount
	current_hp = clamp(current_hp, 0, max_hp)
	emit_signal("health_changed", current_hp, max_hp)
	
	if current_hp <= 0:
		die()

func die() -> void:
	emit_signal("player_died")
	# Optional: Disable input or play animation logic here
	# For now, UI Manager will handle the game over screen

func _setup_animation_tree() -> void:
	if not anim_tree:
		return
		
	var root = AnimationNodeBlendTree.new()
	
	# 1. Movement State Machine (Legs+Body Base)
	var sm = AnimationNodeStateMachine.new()
	var anim_idle = AnimationNodeAnimation.new(); anim_idle.animation = "idle"
	var anim_walk = AnimationNodeAnimation.new(); anim_walk.animation = "walk"
	var anim_sprint = AnimationNodeAnimation.new(); anim_sprint.animation = "sprint"
	
	sm.add_node("idle", anim_idle)
	sm.add_node("walk", anim_walk)
	sm.add_node("sprint", anim_sprint)
	sm.set_node_position("idle", Vector2(0, 0))
	sm.set_node_position("walk", Vector2(200, 0))
	sm.set_node_position("sprint", Vector2(400, 0))
	
	# Simple transitions
	var trans = AnimationNodeStateMachineTransition.new()
	trans.xfade_time = 0.2
	# trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO # REMOVED: Caused auto-play loops
	
	sm.add_transition("idle", "walk", trans)
	sm.add_transition("walk", "idle", trans)
	sm.add_transition("walk", "sprint", trans)
	sm.add_transition("sprint", "walk", trans)
	sm.add_transition("idle", "sprint", trans)
	sm.add_transition("sprint", "idle", trans)
	
	root.add_node("movement", sm)
	root.set_node_position("movement", Vector2(-400, 0))
	
	# 2. Gun Blend (Upper Body Override)
	var blend_gun = AnimationNodeBlend2.new()
	blend_gun.filter_enabled = true
	# Filter for upper body parts
	for bone in ["torso", "arm-left", "arm-right", "head"]:
		blend_gun.set_filter_path("Skeleton3D:" + bone, true)
		
	var anim_hold = AnimationNodeAnimation.new()
	anim_hold.animation = "holding-right"
	
	root.add_node("gun_pose", anim_hold)
	root.set_node_position("gun_pose", Vector2(-400, 200))
	
	root.add_node("gun_blend", blend_gun)
	root.set_node_position("gun_blend", Vector2(-200, 0))
	
	# 3. Shoot Anim (OneShot)
	var oneshot_shoot = AnimationNodeOneShot.new()
	oneshot_shoot.filter_enabled = true
	for bone in ["torso", "arm-left", "arm-right", "head"]:
		oneshot_shoot.set_filter_path("Skeleton3D:" + bone, true)
		
	var anim_shoot = AnimationNodeAnimation.new()
	anim_shoot.animation = "holding-right-shoot"
	
	root.add_node("shoot_anim", anim_shoot)
	root.set_node_position("shoot_anim", Vector2(-200, 200))
	
	root.add_node("shoot_oneshot", oneshot_shoot)
	root.set_node_position("shoot_oneshot", Vector2(0, 0))
	
	# Connections
	# Movement -> GunBlend[0]
	root.connect_node("gun_blend", 0, "movement")
	# GunPose -> GunBlend[1]
	root.connect_node("gun_blend", 1, "gun_pose")
	# GunBlend -> ShootOneShot[0]
	root.connect_node("shoot_oneshot", 0, "gun_blend")
	# ShootAnim -> ShootOneShot[1]
	root.connect_node("shoot_oneshot", 1, "shoot_anim")
	# Output
	root.connect_node("output", 0, "shoot_oneshot")
	
	# Apply logic
	anim_tree.tree_root = root
	anim_tree.active = true
	
	# Get playback object for state machine
	# Note: Path is parameters/movement/playback because we named the node 'movement'
	_anim_playback = anim_tree.get("parameters/movement/playback")

func _physics_process(delta: float) -> void:
	# Gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta
 
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
 
	# Movement input
	var cam = get_viewport().get_camera_3d()
	var direction = Vector3.ZERO
	var cam_forward_flat = Vector3.FORWARD
	
	if cam:
		var input_dir := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		
		var cam_basis = cam.global_transform.basis
		var forward = - cam_basis.z
		var right = cam_basis.x
		 
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		
		direction = (forward * input_dir.y + right * input_dir.x).normalized()
		cam_forward_flat = forward
	 
	var current_speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	 
	var target_vel_x = direction.x * current_speed
	var target_vel_z = direction.z * current_speed
	
	var accel = acceleration if is_on_floor() else acceleration * air_control
	var fric = friction if is_on_floor() else friction * air_control
	
	if direction:
		velocity.x = move_toward(velocity.x, target_vel_x, accel * delta)
		velocity.z = move_toward(velocity.z, target_vel_z, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, fric * delta)
		velocity.z = move_toward(velocity.z, 0, fric * delta)
	
	# Rotation Logic
	if is_gun_equipped and cam:
		# Face Camera Look Direction (Strafing Mode)
		var target_angle = atan2(cam_forward_flat.x, cam_forward_flat.z)
		var current_angle = skeleton.rotation.y
		skeleton.rotation.y = lerp_angle(current_angle, target_angle, rotation_speed * delta)
		
	elif direction:
		# Face Movement Direction (Adventure Mode)
		var camera_ref = get_viewport().get_camera_3d()
		if camera_ref:
			var cam_fwd = - camera_ref.global_transform.basis.z
			cam_fwd.y = 0
			cam_fwd = cam_fwd.normalized()
			var move_dot = direction.dot(cam_fwd)
			 
			if move_dot > -0.3:
				var target_angle = atan2(direction.x, direction.z)
				var current_angle = skeleton.rotation.y
				skeleton.rotation.y = lerp_angle(current_angle, target_angle, rotation_speed * delta)
 
	move_and_slide()

	# Camera Follow
	_update_camera(direction, delta)
	
	# Animations
	_update_animations(direction)
	
	# Gun shooting
	# Check if gun is present and not reloading (prevent animation if reloading)
	var can_fire_gun = gun and gun.has_method("shoot")
	if can_fire_gun and "is_reloading" in gun and gun.is_reloading:
		can_fire_gun = false
		
	if is_gun_equipped and Input.is_action_pressed("shoot") and can_fire_gun:
		# Calculate shooting direction (Camera Forward - Horizontal only)
		# Use the flattened forward vector we calculated earlier for movement
		gun.shoot(cam_forward_flat)
		
		# Trigger shoot animation
		if anim_tree and anim_tree.active:
			anim_tree.set("parameters/shoot_oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func _update_animations(direction: Vector3) -> void:
	if not anim_tree or not anim_tree.active:
		return

	# 1. Update Movement State (Legs)
	var is_moving = direction.length_squared() > 0.01
	var is_sprinting = Input.is_action_pressed("sprint")
	
	if _anim_playback:
		if is_moving:
			if is_sprinting:
				_anim_playback.travel("sprint")
			else:
				_anim_playback.travel("walk")
		else:
			_anim_playback.travel("idle")
	
	# 2. Update Gun Blend (Arms)
	# Check for reloading state from gun directly
	var is_reloading = false
	if gun and "is_reloading" in gun:
		is_reloading = gun.is_reloading

	if is_gun_equipped and not is_reloading:
		# Blend to 1.0 (Gun Pose)
		# Smooth transition can be done by lerping, but AnimationTree handles set() instantly usually.
		# For smooth blend, we rely on the node's internal filtering or manual tweening?
		# Blend2 doesn't auto-tween. We might want to lerp this value.
		var current_blend = anim_tree.get("parameters/gun_blend/blend_amount")
		var target_blend = 1.0
		var new_blend = move_toward(current_blend, target_blend, 5.0 * get_process_delta_time())
		anim_tree.set("parameters/gun_blend/blend_amount", new_blend)
	else:
		# Blend to 0.0 (Normal Arms)
		var current_blend = anim_tree.get("parameters/gun_blend/blend_amount")
		var target_blend = 0.0
		var new_blend = move_toward(current_blend, target_blend, 5.0 * get_process_delta_time())
		anim_tree.set("parameters/gun_blend/blend_amount", new_blend)

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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw -= event.relative.x * mouse_sensitivity * 0.01
		_camera_pitch -= event.relative.y * mouse_sensitivity * 0.01
		
		_camera_pitch = clamp(_camera_pitch, -vertical_limit, vertical_limit)
	
	# Toggle gun/melee with action key (E)
	if event.is_action_pressed("action"):
		_toggle_gun_mode()
	
	# Toggle mouse mode with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _toggle_gun_mode() -> void:
	is_gun_equipped = not is_gun_equipped
	if gun:
		gun.visible = is_gun_equipped

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
