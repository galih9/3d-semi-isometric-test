extends CharacterBody3D

# --- Configuration ---
@export var speed: float = 3.0
@export var attack_range: float = 0.8
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.5
@export var max_health: float = 200.0

# --- Nodes ---
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
# @onready var anim_tree: AnimationTree = $AnimationTree # If we use tree later

# --- State ---
var health: float = max_health
var target: Node3D = null # The player
var can_attack: bool = true
var is_attacking: bool = false

enum State {IDLE, CHASE, ATTACK, DEAD}
var current_state: State = State.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready() -> void:
	add_to_group("enemies")
	# Disable AnimationTree if it exists
	var anim_tree = get_node_or_null("AnimationTree")
	if anim_tree:
		anim_tree.active = false
		
	# Find player
	_find_target()

	# Setup Navigation
	nav_agent.path_desired_distance = 1.0
	nav_agent.target_desired_distance = 1.0
	
	# Wait for first physics frame to ensure NavigationServer is synced
	await get_tree().physics_frame

func _find_target() -> void:
	# Try group finding
	target = get_tree().get_first_node_in_group("player")
	
	# Try name finding if group fails
	if not target:
		target = get_tree().root.find_child("Player", true, false)
		
	if name == "BigEnemy":
		print("BigEnemy target search result: ", target)


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
		
	# Robust target finding if lost
	if not is_instance_valid(target):
		_find_target()
		
	# Auto-transition from IDLE if target is found
	if current_state == State.IDLE and target:
		current_state = State.CHASE
	
	# State Machine Logic
	match current_state:
		State.IDLE:
			if name == "BigEnemy" and Engine.get_physics_frames() % 60 == 0:
				print("BigEnemy: IDLE. Target valid: ", is_instance_valid(target))
			_process_idle(delta)
		State.CHASE:
			if name == "BigEnemy" and Engine.get_physics_frames() % 60 == 0:
				var dist = global_position.distance_to(target.global_position)
				var reach = nav_agent.is_target_reachable()
				print("BigEnemy: CHASE. Dist: %.2f, Reachable: %s, Velocity: %s" % [dist, reach, velocity])
			_process_chase(delta)
		State.ATTACK:
			if name == "BigEnemy" and Engine.get_physics_frames() % 60 == 0:
				print("BigEnemy: ATTACKing")
			_process_attack(delta)
	
	# Apply movement if valid velocity
	if current_state != State.DEAD:
		# Apply Gravity
		if not is_on_floor():
			velocity.y -= _gravity * delta
			
		move_and_slide()
		
		if name == "BigEnemy" and Engine.get_physics_frames() % 60 == 0:
			if velocity.length() < 0.1 and current_state == State.CHASE:
				print("BigEnemy: STUCK? Velocity is near zero while in CHASE state.")


func _process_idle(_delta: float) -> void:
	if target:
		current_state = State.CHASE
	# Play idle anim
	_play_anim("idle")
	velocity = Vector3.ZERO

func _process_chase(_delta: float) -> void:
	if not target:
		current_state = State.IDLE
		return
		
	# Update Navigation Target
	nav_agent.target_position = target.global_position
	
	# Check attack range FIRST
	var dist = global_position.distance_to(target.global_position)
	if dist <= attack_range:
		current_state = State.ATTACK
		return

	if nav_agent.is_navigation_finished():
		if name == "BigEnemy": print("BigEnemy: Navigation thinks it is finished.")
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var current_agent_pos = global_position
	
	# Calculate velocity (Horizontal only)
	var dir = next_path_pos - current_agent_pos
	dir.y = 0
	var new_velocity = dir.normalized() * speed
	new_velocity.y = velocity.y # Preserve gravity
	
	# Rotate to face movement (Horizontal look)
	var move_dir_h = Vector2(new_velocity.x, new_velocity.z)
	if move_dir_h.length_squared() > 0.1:
		var look_target = Vector3(next_path_pos.x, global_position.y, next_path_pos.z)
		if global_position.distance_to(look_target) > 0.01:
			look_at(look_target)
	
	# Avoidance (optional, can enable if RVO is set)
	# nav_agent.set_velocity(new_velocity) 
	velocity = new_velocity

	
	if new_velocity.length_squared() > 0.1:
		_play_anim("walk")
	else:
		_play_anim("idle")
	

func _process_attack(_delta: float) -> void:
	velocity = Vector3.ZERO
	
	# Face target
	if target:
		var look_target = Vector3(target.global_position.x, global_position.y, target.global_position.z)
		look_at(look_target)
		
		# Distance check to go back to chase
		var dist = global_position.distance_to(target.global_position)
		if dist > attack_range + 0.5 and not is_attacking:
			current_state = State.CHASE
			return

	if can_attack and not is_attacking:
		_perform_attack()

func _perform_attack() -> void:
	is_attacking = true
	can_attack = false
	
	# Play attack animation
	_play_anim("attack-melee-right")
	
	# Deal damage at specific time or now? Let's delay slightly
	await get_tree().create_timer(0.3).timeout
	
	if target and current_state != State.DEAD:
		# Double check distance
		var dist = global_position.distance_to(target.global_position)
		if dist <= attack_range + 0.5:
			if target.has_method("take_damage"):
				target.take_damage(attack_damage)
	
	# Wait for animation finish approx
	await get_tree().create_timer(0.5).timeout
	is_attacking = false
	
	# Cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func take_damage(amount: float) -> void:
	if current_state == State.DEAD:
		return
		
	health -= amount
	
	# Visual feedback: Flash red
	_flash_damage()
	
	if health <= 0:
		die()

func _flash_damage() -> void:
	# Find all meshes and flash them red
	var mesh_instances = find_children("*", "MeshInstance3D", true, false)
	for mesh in mesh_instances:
		# Use material_override for temporary flash
		# Create a red material if not already cached? or just new one (cheap enough for occasional hits)
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0, 0) # Red
		mat.emission_enabled = true
		mat.emission = Color(1, 0, 0)
		mat.emission_energy_multiplier = 2.0
		
		mesh.material_override = mat
	
	# Wait and reset
	await get_tree().create_timer(0.1).timeout
	
	if is_instance_valid(self):
		for mesh in mesh_instances:
			if is_instance_valid(mesh):
				mesh.material_override = null

func die() -> void:
	current_state = State.DEAD
	# Stop horizontal movement, keep gravity? 
	# Ideally allow falling, but velocity = ZERO stops falling.
	# Let's keep Y velocity if falling, else zero.
	var y_vel = velocity.y
	velocity = Vector3(0, y_vel, 0)
	
	# Disable collision
	$CollisionShape3D.set_deferred("disabled", true)
	
	_play_anim("die")
	
	# Remove after delay
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _play_anim(anim_name: String) -> void:
	if anim_player and anim_player.has_animation(anim_name):
		if anim_player.current_animation != anim_name:
			anim_player.play(anim_name, 0.3) # 0.3 blend time
