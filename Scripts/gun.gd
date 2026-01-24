extends Node3D

# --- Configuration ---
@export var fire_rate: float = 0.2 # Time between shots in seconds
@export var bullet_scene: PackedScene

# --- Nodes ---
@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: Sprite3D = $Muzzle/MuzzleFlash

# --- State ---
var can_shoot: bool = true
var shoot_timer: float = 0.0

func _ready() -> void:
	# Hide muzzle flash initially
	if muzzle_flash:
		muzzle_flash.visible = false
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Scenes/bullet.tscn")

func _process(delta: float) -> void:
	# Handle shoot cooldown
	if not can_shoot:
		shoot_timer -= delta
		if shoot_timer <= 0:
			can_shoot = true

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
	
	# Start cooldown
	can_shoot = false
	shoot_timer = fire_rate

func _show_muzzle_flash() -> void:
	if not muzzle_flash:
		return
	
	muzzle_flash.visible = true
	
	# Hide after a short delay
	await get_tree().create_timer(0.05).timeout
	if muzzle_flash:
		muzzle_flash.visible = false
