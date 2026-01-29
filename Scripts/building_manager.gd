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
		var _hit_normal = result.normal
		
		# Construction Logic
		var snapped_transform = Transform3D(Basis(), hit_position)
		var _found_snap = false
		
		# 1. Check if we hit an existing ConstructionItem (Structure)
		# Node structure: SingleFloor -> floor-thick -> StaticBody3D -> CollisionShape
		var root_node = hit_collider.owner
		if not root_node and hit_collider.get_parent():
			root_node = hit_collider.get_parent().get_parent()
			
		if root_node and root_node is ConstructionItemScript:
			# hitting an existing structure: Try to snap to its markers
			var best_dist = snap_threshold
			var best_marker = null
			
			# Find all markers recursively or in known "SnapPoint" group
			var markers = _find_markers(root_node)
			
			for marker in markers:
				var marker_global_pos = marker.global_position
				var dist = hit_position.distance_to(marker_global_pos)
				if dist < best_dist:
					# Check for occupancy (is something already built here?)
					if not _is_position_occupied(marker_global_pos):
						best_dist = dist
						best_marker = marker
			
			if best_marker:
				snapped_transform = best_marker.global_transform
				_found_snap = true
				
		elif current_scene_to_build == floor_scene:
			# 2. Hitting Ground (and building a Floor): Grid Snap
			# Snap to XZ grid (assuming Y is up)
			var grid_size = 1.0 # Assuming 1x1 tiles based on markers
			var snapped_x = round(hit_position.x / grid_size) * grid_size
			var snapped_z = round(hit_position.z / grid_size) * grid_size
			var snapped_y = hit_position.y # Keep ground height or snap if needed
			
			snapped_transform.origin = Vector3(snapped_x, snapped_y, snapped_z)
			_found_snap = true
			
		# Apply transform
		current_ghost.global_transform = snapped_transform
		current_ghost.visible = true
	else:
		# Fallback: Plane cast for ground grid snapping if ray misses
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(from, build_camera.project_ray_normal(mouse_pos))
		
		if intersection:
			var grid_size = 1.0
			var snapped_x = round(intersection.x / grid_size) * grid_size
			var snapped_z = round(intersection.z / grid_size) * grid_size
			
			current_ghost.global_position = Vector3(snapped_x, 0, snapped_z)
			current_ghost.global_rotation = Vector3.ZERO
			current_ghost.visible = true
		else:
			current_ghost.visible = false

func _find_markers(node: Node) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	for child in node.get_children():
		if child is Marker3D:
			markers.append(child)
		# Search deeper (e.g., inside SnapPoint node)
		if child.get_child_count() > 0:
			markers.append_array(_find_markers(child))
	return markers

func _is_position_occupied(pos: Vector3) -> bool:
	var space_state = get_world_3d().direct_space_state
	# Sphere check with small radius to see if a structure is already there
	var params = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1 # Small radius check
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 1 # Match construction layer
	
	var intersections = space_state.intersect_shape(params)
	
	# If we find a valid ConstructionItem at this exact spot, it's occupied
	for hit in intersections:
		var collider = hit.collider
		var root = collider.owner
		if not root and collider.get_parent(): root = collider.get_parent().get_parent()
		
		if root and root is ConstructionItemScript:
			# If we are building a wall, we care if there is ALREADY a wall here
			# If we are building a floor, maybe we care if there is a floor? 
			# User requirement: "double wall placing... slot is already filled"
			# Heuristic: Check if the existing item is of the same type we are trying to build?
			# Or if ANY construction item is there.
			# For now: if ANY buildable collision logic is detected at marker, block it.
			# Note: Markers are usually at edges. Wall centers match markers. 
			return true
			
	return false

func _place_object() -> void:
	var new_obj = current_scene_to_build.instantiate()
	get_parent().add_child(new_obj) # Add to main scene root preferably
	new_obj.global_transform = current_ghost.global_transform
	if new_obj.has_method("set_state"):
		new_obj.set_state(ConstructionItemScript.State.PLACED)
