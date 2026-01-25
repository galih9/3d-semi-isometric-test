extends Area3D

# --- Configuration ---
@export var speed: float = 20.0
@export var lifetime: float = 5.0
@export var damage: float = 25.0

# --- State ---
var velocity: Vector3 = Vector3.ZERO
var time_alive: float = 0.0

func _ready() -> void:
	# Keep default behavior if not configured externally
	if velocity == Vector3.ZERO:
		velocity = - global_transform.basis.z * speed

func init(start_pos: Vector3, direction: Vector3) -> void:
	global_position = start_pos
	# Look at direction
	if direction.length_squared() > 0.001:
		look_at(start_pos + direction, Vector3.UP)
		velocity = direction.normalized() * speed
	
func _physics_process(delta: float) -> void:
	# Calculate frame movement
	var motion = velocity * delta
	var current_pos = global_position
	var target_pos = current_pos + motion
	
	# Raycast for collision
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(current_pos, target_pos)
	
	# Exclude self to be safe, though Area3D usually isn't picked up by default rays unless configured
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Set collision mask if needed, but default is usually fine for now
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Hit something!
		var collider = result.collider
		var hit_pos = result.position
		var normal = result.normal
		
		# Move to hit position
		global_position = hit_pos
		
		# Apply Damage
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		elif collider.get_parent() and collider.get_parent().has_method("take_damage"):
			collider.get_parent().take_damage(damage) # For Area3D child of enemy
			
		# Spawn Effect
		_spawn_hit_effect(hit_pos, normal)
		
		queue_free()
	else:
		# No hit, move normally
		global_position = target_pos
		
	# Track lifetime
	time_alive += delta
	if time_alive >= lifetime:
		queue_free()

func _spawn_hit_effect(pos: Vector3, normal: Vector3) -> void:
	var effect_scene = load("res://Scenes/Effects/HitEffect.tscn")
	if effect_scene:
		var effect = effect_scene.instantiate()
		get_tree().root.add_child(effect)
		
		# Position slightly off the surface to avoid z-fighting/clipping
		effect.global_position = pos + (normal * 0.1)
		
		# Optional: Orient effect to match surface normal if it was a flat decal
		# Since it's a billboard sprite, position is most important.
