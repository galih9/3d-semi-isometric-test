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
	
	# Connect signals
	area_entered.connect(_on_area_entered)

func init(start_pos: Vector3, direction: Vector3) -> void:
	global_position = start_pos
	# Look at direction
	if direction.length_squared() > 0.001:
		look_at(start_pos + direction, Vector3.UP)
		velocity = direction.normalized() * speed

func _process(delta: float) -> void:
	# Move bullet
	global_position += velocity * delta
	
	# Track lifetime
	time_alive += delta
	if time_alive >= lifetime:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	# Hit something solid
	# TODO: Apply damage if it's an enemy
	if body.has_method("take_damage"):
		body.take_damage(damage)
	
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	# Hit another area (could be enemy hitbox)
	# TODO: Apply damage if it's an enemy
	if area.has_method("take_damage"):
		area.take_damage(damage)
	elif area.get_parent() and area.get_parent().has_method("take_damage"):
		area.get_parent().take_damage(damage)
	
	queue_free()
