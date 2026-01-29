extends Node3D

const ConstructionItemScript = preload("res://Scripts/construction_item.gd")

@export var floor_scene: PackedScene = preload("res://Scenes/Construction/single_floor.tscn")
@export var wall_scene: PackedScene = preload("res://Scenes/Construction/single_wall.tscn")
@export var snap_threshold: float = 2.0

@onready var build_camera: Camera3D = %BuildCamera
@onready var player: CharacterBody3D = %Player

var current_ghost: Node3D = null
var current_scene_to_build: PackedScene = null
var active_build_mode: bool = false

# Raycasting
const RAY_LENGTH = 1000.0

func _ready() -> void:
	# Ensure primary_click action exists
	if not InputMap.has_action("primary_click"):
		InputMap.add_action("primary_click")
		var ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("primary_click", ev)
		
	# Connect to build mode signal or check state in process
	# Assuming GameManager or input handles build mode toggling. 
	# For this implementation, we check build_camera state.
	
	# Initial Setup
	current_scene_to_build = floor_scene

func _process(_delta: float) -> void:
	# Check if we should be active
	var is_cam_active = build_camera.current
	
	if is_cam_active and not active_build_mode:
		_enter_build_mode()
	elif not is_cam_active and active_build_mode:
		_exit_build_mode()
		
	if active_build_mode:
		_handle_building_logic()

func _enter_build_mode() -> void:
	active_build_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player.has_method("set_frozen"):
		player.set_frozen(true)
	
	# Spawn initial ghost
	_spawn_ghost()

func _exit_build_mode() -> void:
	active_build_mode = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player.has_method("set_frozen"):
		player.set_frozen(false)
	
	_despawn_ghost()

func _input(event: InputEvent) -> void:
	if not active_build_mode:
		return
		
	if event.is_action_pressed("ui_left"):
		_change_construction_item(floor_scene)
	elif event.is_action_pressed("ui_right"):
		_change_construction_item(wall_scene)
	elif event.is_action_pressed("primary_click"):
		if current_ghost and current_ghost.visible:
			_place_object()

func _change_construction_item(new_scene: PackedScene) -> void:
	current_scene_to_build = new_scene
	_despawn_ghost()
	_spawn_ghost()

func _spawn_ghost() -> void:
	if current_scene_to_build:
		current_ghost = current_scene_to_build.instantiate()
		add_child(current_ghost)
		# Use script constant for enum
		if current_ghost.has_method("set_state"):
			current_ghost.set_state(ConstructionItemScript.State.GHOST)

func _despawn_ghost() -> void:
	if current_ghost:
		current_ghost.queue_free()
		current_ghost = null

func _handle_building_logic() -> void:
	if not current_ghost:
		return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var from = build_camera.project_ray_origin(mouse_pos)
	var to = from + build_camera.project_ray_normal(mouse_pos) * RAY_LENGTH
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	# query.collision_mask = ... # Set if specific layers needed (e.g., ground/floors only)
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var hit_position = result.position
		var hit_collider = result.collider
		
		# Snapping Logic
		var snapped_transform = Transform3D(Basis(), hit_position)
		var _found_snap = false
		
		# Check for markers if hitting a valid structure
		# Assuming collider is part of a construction item (SingleFloor)
		# Node structure: SingleFloor -> floor-thick -> StaticBody3D -> CollisionShape
		# So collider is StaticBody3D. Owner or parent logic:
		var root_node = hit_collider.owner
		if not root_node and hit_collider.get_parent():
			root_node = hit_collider.get_parent().get_parent() # Heuristic for imported scenes
			
		# Check type using preloaded script
		if root_node and root_node is ConstructionItemScript:
			# Look for Markers
			var best_dist = snap_threshold
			var best_marker = null
			
			for child in root_node.get_children():
				if child is Marker3D:
					var marker_global_pos = child.global_position
					var dist = hit_position.distance_to(marker_global_pos)
					if dist < best_dist:
						best_dist = dist
						best_marker = child
			
			if best_marker:
				snapped_transform = best_marker.global_transform
				_found_snap = true
				
				# For walls (or generally), align rotation to marker
				# Markers on floor should be oriented such that -Z (Forward) points OUT or ALONG the edge appropriate for the wall 
				# The current_ghost will adopt this transform
				
		# Apply transform
		current_ghost.global_transform = snapped_transform
		current_ghost.visible = true
	else:
		# Hide ghost if pointing at void? Or detect ground plane (y=0)?
		# For now, let's plane-cast to Y=0 if no hit, or just hide
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(from, build_camera.project_ray_normal(mouse_pos))
		
		if intersection:
			current_ghost.global_position = intersection
			current_ghost.global_rotation = Vector3.ZERO
			current_ghost.visible = true
		else:
			current_ghost.visible = false

func _place_object() -> void:
	var new_obj = current_scene_to_build.instantiate()
	get_parent().add_child(new_obj) # Add to main scene root preferably
	new_obj.global_transform = current_ghost.global_transform
	if new_obj.has_method("set_state"):
		new_obj.set_state(ConstructionItemScript.State.PLACED)
