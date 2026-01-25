extends CharacterBody3D

# --- Configuration ---
@export var speed: float = 3.0
@export var attack_range: float = 1.5
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.5
@export var max_health: float = 100.0

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
	# Find player (assuming name is "Player" or in a 'player' group)
	# Better approach: Main scene should assign it or we find it
	target = get_tree().get_first_node_in_group("player")
	
	if not target:
		# Fallback search
		target = get_tree().root.find_child("Player", true, false)

	# Setup Navigation
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	
	# Disable AnimationTree if it exists, as we use AnimationPlayer directly
	# The AnimationTree might be left over from previous attempts and overriding playback
	var anim_tree = get_node_or_null("AnimationTree")
	if anim_tree:
		anim_tree.active = false
	
	# Setup HP Bar if needed (User asked for it in previous convo, but now "basic hud" for player. 
	# User request #2: "enemy will try to chase the player")

func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		return
		
	# State Machine Logic
	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
	
	# Apply movement if valid velocity
	if current_state != State.DEAD:
		# Apply Gravity
		if not is_on_floor():
			velocity.y -= _gravity * delta
			
		move_and_slide()
		pass

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
	
	var next_path_pos = nav_agent.get_next_path_position()
	var current_agent_pos = global_position
	
	# Calculate velocity (Horizontal only)
	var new_velocity = (next_path_pos - current_agent_pos).normalized() * speed
	new_velocity.y = velocity.y # Preserve gravity
	
	# Rotate to face movement (Horizontal look)
	if Vector2(new_velocity.x, new_velocity.z).length_squared() > 0.1:
		var look_target = Vector3(next_path_pos.x, global_position.y, next_path_pos.z)
		look_at(look_target)
	
	# Avoidance (optional, can enable if RVO is set)
	# nav_agent.set_velocity(new_velocity) 
	velocity = new_velocity
	
	if new_velocity.length_squared() > 0.1:
		_play_anim("walk")
	else:
		_play_anim("idle")
	
	# Check attack range
	var dist = global_position.distance_to(target.global_position)
	if dist <= attack_range:
		current_state = State.ATTACK

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
	# Optional: Hit animation or flash
	
	if health <= 0:
		die()

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
