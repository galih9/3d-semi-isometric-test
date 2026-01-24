extends Node3D

# --- Configuration ---
@export var fire_rate: float = 0.2 # Time between shots in seconds
@export var bullet_scene: PackedScene

# --- Nodes ---
@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: AnimatedSprite3D = $Muzzle/MuzzleFlash
@onready var ray_cast: RayCast3D = $Muzzle/RayCast3D
@onready var laser_mesh: MeshInstance3D = $Muzzle/Laser
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var cooldown_timer: Timer = $Timer

# --- State ---
var can_shoot: bool = true

func _ready() -> void:
	# Hide muzzle flash initially
	if muzzle_flash:
		muzzle_flash.visible = false
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Scenes/bullet.tscn")
		
	# Setup Timer
	if cooldown_timer:
		cooldown_timer.wait_time = fire_rate
		cooldown_timer.one_shot = true
		cooldown_timer.timeout.connect(_on_timer_timeout)

func _process(_delta: float) -> void:
	# Update Laser Sight
	_update_laser()

func shoot(aim_direction: Vector3 = Vector3.ZERO, _aim_origin: Vector3 = Vector3.ZERO) -> void:
	if not can_shoot or not bullet_scene or not muzzle:
		return
	
	# Spawn bullet
	var bullet = bullet_scene.instantiate()
	get_tree().root.add_child(bullet)
	
	# Calculate start position (muzzle)
	var start_pos = muzzle.global_position
	
	# Determine direction
	var dir = aim_direction
	if dir == Vector3.ZERO:
		# Fallback to muzzle forward
		dir = - muzzle.global_transform.basis.z
	
	# Initialize bullet
	if bullet.has_method("init"):
		bullet.init(start_pos, dir)
	else:
		# Fallback for old bullet scripts (compatibility)
		bullet.global_transform = muzzle.global_transform

	# Show muzzle flash
	_show_muzzle_flash()
	
	# Play Sound
	if audio_player:
		audio_player.play()
	
	# Start cooldown
	can_shoot = false
	if cooldown_timer:
		cooldown_timer.start()

func _on_timer_timeout() -> void:
	can_shoot = true

func _show_muzzle_flash() -> void:
	if muzzle_flash:
		muzzle_flash.visible = true
		muzzle_flash.frame = 0
		muzzle_flash.play("default")
		muzzle_flash.rotation_degrees.z = randf_range(-45, 45)
		muzzle_flash.scale = Vector3.ONE * randf_range(0.40, 0.75)
		
		# Hide after a short delay
		await get_tree().create_timer(0.05).timeout
		if muzzle_flash:
			muzzle_flash.visible = false

func _update_laser() -> void:
	if not ray_cast or not laser_mesh:
		return
		
	var distance: float = 50.0 # Max range default
	
	# Check collision
	if ray_cast.is_colliding():
		var collision_point = ray_cast.get_collision_point()
		distance = muzzle.global_position.distance_to(collision_point)
	
	# Note: Laser mesh is a cylinder with height 1.0 (centered)
	# rotated -90 on X, so Y-axis points forward (-Z relative to Muzzle)
	# We scale the Y axis to match distance
	laser_mesh.scale.y = distance
	# Move it forward by half the distance to start at muzzle
	laser_mesh.position.z = - distance / 2.0
