extends Node3D

# --- Configuration ---
@export var fire_rate: float = 0.2 # Time between shots in seconds
@export var bullet_scene: PackedScene
@export var clip_size: int = 30
@export var reload_time: float = 3.0

signal ammo_changed(current_ammo)
signal reload_started
signal reload_finished

# --- Nodes ---
@onready var muzzle: Marker3D = $Muzzle
@onready var muzzle_flash: AnimatedSprite3D = $Muzzle/MuzzleFlash
@onready var ray_cast: RayCast3D = $Muzzle/RayCast3D
@onready var laser_mesh: MeshInstance3D = $Muzzle/Laser
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var cooldown_timer: Timer = $Timer
var reload_audio: AudioStreamPlayer

# --- State ---
var can_shoot: bool = true
var current_ammo: int = clip_size
var is_reloading: bool = false

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
		
	reload_audio = get_node_or_null("ReloadAudio")
		
	emit_signal("ammo_changed", current_ammo)

func _process(_delta: float) -> void:
	# Update Laser Sight
	_update_laser()
	
	# Auto-reload if empty
	if current_ammo <= 0 and not is_reloading:
		reload()

func shoot(aim_direction: Vector3 = Vector3.ZERO, _aim_origin: Vector3 = Vector3.ZERO) -> void:
	if not can_shoot or not bullet_scene or not muzzle or is_reloading:
		return
	
	if current_ammo <= 0:
		reload()
		return
		
	# Consume ammo
	current_ammo -= 1
	emit_signal("ammo_changed", current_ammo)
	
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

func reload() -> void:
	if is_reloading or current_ammo == clip_size:
		return
		
	is_reloading = true
	emit_signal("reload_started")
	
	if reload_audio:
		reload_audio.play()
	
	# Use a timer for reload
	await get_tree().create_timer(reload_time).timeout
	
	current_ammo = clip_size
	is_reloading = false
	emit_signal("ammo_changed", current_ammo)
	emit_signal("reload_finished")

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
