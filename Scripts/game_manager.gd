extends Node3D

# Store enemy spawn data: { "scene_path": String, "transform": Transform3D }
var initial_enemies_data: Array = []
@onready var build_camera = %BuildCamera

func _ready() -> void:
	# Wait one frame to ensure all enemies are initialized and in the group
	await get_tree().process_frame
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	print("GameManager: Found %d enemies." % enemies.size())
	
	for enemy in enemies:
		if enemy is Node3D:
			var data = {
				"scene_path": enemy.scene_file_path,
				"transform": enemy.global_transform
			}
			initial_enemies_data.append(data)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("slot1"): # Key 1
		print("GameManager: Respawning enemies...")
		respawn_enemies()
	if event.is_action_pressed("build_mode"):
		build_camera.current = !build_camera.current

func respawn_enemies() -> void:
	# 1. Remove existing enemies
	var current_enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in current_enemies:
		enemy.queue_free()
	
	# 2. Spawn initial enemies
	for data in initial_enemies_data:
		var scene_path = data["scene_path"]
		var spawn_transform = data["transform"]
		
		var scene = load(scene_path)
		if scene:
			var new_enemy = scene.instantiate()
			# Add to scene
			add_child(new_enemy)
			new_enemy.global_transform = spawn_transform
			print("GameManager: Respawned enemy from %s" % scene_path)
		else:
			print("GameManager: Failed to load scene %s" % scene_path)
