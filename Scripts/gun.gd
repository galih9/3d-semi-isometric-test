extends Node3D

# --- Configuration ---
@export var gun_data: GunData
@export var bullet_scene: PackedScene

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
var current_ammo: int = 0
var is_reloading: bool = false
var _current_spread: float = 0.0
var movement_spread_modifier: float = 0.0

func _ready() -> void:
	if not gun_data:
		push_warning("Gun has no GunData assigned! Creating default.")
		gun_data = GunData.new()
		
	current_ammo = gun_data.clip_size

	# Hide muzzle flash initially
	if muzzle_flash:
		muzzle_flash.visible = false
	
	# Load bullet scene if not set
	if not bullet_scene:
		bullet_scene = load("res://Scenes/bullet.tscn")
		
	# Setup Timer
	if cooldown_timer:
		cooldown_timer.wait_time = gun_data.fire_rate
		cooldown_timer.one_shot = true
		cooldown_timer.timeout.connect(_on_timer_timeout)
		
	reload_audio = get_node_or_null("ReloadAudio")
		
	emit_signal("ammo_changed", current_ammo)

func _process(_delta: float) -> void:
	if not gun_data: return
	
	# Update Laser Sight
	_update_laser()
	
	# Spread Recovery
	if _current_spread > 0:
		_current_spread = max(0.0, _current_spread - gun_data.spread_recovery * _delta)
	
	# Auto-reload if empty
	if current_ammo <= 0 and not is_reloading:
		reload()

func shoot(aim_direction: Vector3 = Vector3.ZERO, _aim_origin: Vector3 = Vector3.ZERO, camera_pitch: float = 0.0) -> void:
	if not can_shoot or not bullet_scene or not muzzle or is_reloading or not gun_data:
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
	# Determine direction
	var dir = aim_direction
	if dir == Vector3.ZERO:
		# Fallback to muzzle forward
		dir = - muzzle.global_transform.basis.z
		
	# Apply Vertical Bias (Pitch down/up)
	# We construct a basis looking at 'dir' then rotate local X
	var right = dir.cross(Vector3.UP).normalized()
	if right == Vector3.ZERO: right = Vector3.RIGHT # Handle straight up/down
	
	var combined_pitch = gun_data.vertical_aim_bias + camera_pitch
	dir = dir.rotated(right, deg_to_rad(combined_pitch))
	
	# Apply Spread
	var total_spread = gun_data.base_spread + _current_spread + movement_spread_modifier
	if total_spread > 0:
		var spread_angle = deg_to_rad(randf_range(0, total_spread))
		var spread_rot = randf_range(0, TAU) # Random rotation around forward axis
		
		# Rotate random amount around a random axis perpendicular to direction
		# To do this robustly: Create a basis where Z is dir
		var up = Vector3.UP
		if abs(dir.dot(up)) > 0.99: up = Vector3.RIGHT
		
		var basis_aim = Basis.looking_at(dir, up)
		# Local rotation: Tilt "up" by spread amount, then spin around Z
		var spread_vector = Vector3.FORWARD.rotated(Vector3.RIGHT, spread_angle).rotated(Vector3.FORWARD, spread_rot)
		# Transform to world space
		dir = basis_aim * spread_vector
		
		# Increase spread
		var max_add_spread = max(0.0, gun_data.max_spread - gun_data.base_spread)
		_current_spread = min(max_add_spread, _current_spread + gun_data.spread_per_shot)
	
	# Initialize bullet
	if bullet.has_method("init"):
		bullet.init(start_pos, dir)
		if "damage" in bullet:
			bullet.damage = gun_data.damage
		if "speed" in bullet:
			bullet.speed = gun_data.bullet_speed
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
		cooldown_timer.wait_time = gun_data.fire_rate
		cooldown_timer.start()

func _on_timer_timeout() -> void:
	can_shoot = true

func reload() -> void:
	if is_reloading or not gun_data or current_ammo == gun_data.clip_size:
		return
		
	is_reloading = true
	emit_signal("reload_started")
	
	if reload_audio:
		reload_audio.play()
	
	# Use a timer for reload
	await get_tree().create_timer(gun_data.reload_time).timeout
	
	current_ammo = gun_data.clip_size
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
