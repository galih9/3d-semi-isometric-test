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
			print("Debug: Clicked to place (Ghost Visible)")
			_place_object()
		else:
			print("Debug: Clicked but ghost not visible")

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
		
		# Construction Logic
		var snapped_transform = Transform3D(Basis(), hit_position)
		var _found_snap = false
		var is_valid_placement = false
		
		# 1. Hitting an existing ConstructionItem (Structure)
		var root_node = _get_construction_root(hit_collider)
		
		# DEBUG: What are we hitting?
		print("Debug: Raycast hit: ", hit_collider.name, " (", hit_collider.get_path(), ")")
		if root_node:
			print("Debug: Found Root: ", root_node.name)
		else:
			print("Debug: Root NOT found for ", hit_collider.name)
			
		if root_node:
			# Attempt Snapping
			var best_dist = snap_threshold
			var best_marker = null
			
			var markers = _find_markers(root_node)
			print("Debug: Markers found: ", markers.size())
			
			for marker in markers:
				var marker_global_pos = marker.global_position
				var dist = hit_position.distance_to(marker_global_pos)
				if dist < best_dist:
					best_dist = dist
					best_marker = marker
			
			if best_marker:
				print("Debug: Snapping to ", best_marker.name)
				snapped_transform = best_marker.global_transform
				_found_snap = true
				
				# Occupancy Check
				# If we are building a WALL, we only care if another WALL is there. Floors don't matter.
				var building_a_wall = (current_scene_to_build == wall_scene)
				var is_occupied = _is_position_occupied(best_marker.global_position, hit_collider, building_a_wall)
				
				if is_occupied:
					print("Debug: Snap found but OCCUPIED (Red)")
				
				if not is_occupied:
					is_valid_placement = true
				else:
					is_valid_placement = false # Found snap, but occupied -> Red
				

		# 2. Hitting Ground (Grid Snap)
		elif current_scene_to_build == floor_scene:
			# Grid Snap logic for Floors (Center Snap)
			var grid_size = 1.0
			var snapped_x = round(hit_position.x / grid_size) * grid_size
			var snapped_z = round(hit_position.z / grid_size) * grid_size
			var snapped_y = hit_position.y
			
			snapped_transform.origin = Vector3(snapped_x, snapped_y, snapped_z)
			_found_snap = true
			
			if not _is_position_occupied(snapped_transform.origin):
				is_valid_placement = true
			else:
				is_valid_placement = false

		elif current_scene_to_build == wall_scene:
			# Grid Snap logic for Walls (Edge Snapping)
			var grid_size = 1.0
			var half_grid = grid_size * 0.5
			
			# Determine center of the cell
			var cell_x = round(hit_position.x / grid_size) * grid_size
			var cell_z = round(hit_position.z / grid_size) * grid_size
			var cell_center = Vector3(cell_x, hit_position.y, cell_z)
			
			# Determine which edge is closest
			var diff = hit_position - cell_center
			
			# If closer to X edge (East/West) -> Wall runs along Z axis (Default rotation)
			if abs(diff.x) > abs(diff.z):
				var direction = sign(diff.x)
				snapped_transform.origin = cell_center + Vector3(direction * half_grid, 0, 0)
				# Default Wall matches Z-axis, check if we need to rotate?
				# Wall is -0.5 to 0.5 in Z. If we place at X offset, it separates cells left/right.
				# It should run along Z. So Rotation = 0.
				snapped_transform.basis = Basis.from_euler(Vector3(0, 0, 0))
			else:
				# Closer to Z edge (North/South) -> Wall runs along X axis
				var direction = sign(diff.z)
				snapped_transform.origin = cell_center + Vector3(0, 0, direction * half_grid)
				# Rotate 90 degrees to run along X
				snapped_transform.basis = Basis.from_euler(Vector3(0, deg_to_rad(90), 0))
			
			_found_snap = true
			
			# Check occupancy (Pass hit_collider to ignore the ground)
			if not _is_position_occupied(snapped_transform.origin, hit_collider, true):
				is_valid_placement = true
			else:
				is_valid_placement = false


		# Ghost Handling
		if _found_snap:
			current_ghost.global_transform = snapped_transform
			current_ghost.visible = true
			
			# Set Color (Green/Red)
			if current_ghost.has_method("set_ghost_valid"):
				current_ghost.set_ghost_valid(is_valid_placement)
				
			# Store validity for input handling
			current_ghost.set_meta("is_valid", is_valid_placement)
			
		else:
			# No snap found. 
			# User request: "If invalid it should show red" (Visible but invalid)
			# We show it at the hit position, but red.
			current_ghost.global_position = hit_position
			current_ghost.global_rotation = Vector3.ZERO
			current_ghost.visible = true
			
			if current_ghost.has_method("set_ghost_valid"):
				current_ghost.set_ghost_valid(false)
			current_ghost.set_meta("is_valid", false)
			
	else:
		# Fallback: Plane cast (Grid)
		var plane = Plane(Vector3.UP, 0)
		var intersection = plane.intersects_ray(from, build_camera.project_ray_normal(mouse_pos))
		
		if intersection:
			var grid_size = 1.0
			var snapped_x = round(intersection.x / grid_size) * grid_size
			var snapped_z = round(intersection.z / grid_size) * grid_size
			
			current_ghost.global_position = Vector3(snapped_x, 0, snapped_z)
			current_ghost.global_rotation = Vector3.ZERO
			current_ghost.visible = true
			
			# Validity Logic for Fallback
			var is_valid = false
			if current_scene_to_build == floor_scene:
				# Floor can be placed on grid if not occupied by another floor
				if not _is_position_occupied(current_ghost.global_position, null, false):
					is_valid = true
			
			# Walls cannot be placed on grid fallback
			
			if current_ghost.has_method("set_ghost_valid"):
				current_ghost.set_ghost_valid(is_valid)
			current_ghost.set_meta("is_valid", is_valid)
			
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

func _get_construction_root(node: Node) -> Node:
	var current = node
	# Traverse up up to 5 levels to find the root with the script
	for i in range(5):
		if not current:
			break
			
		# Debug: check what we are looking at
		# print("Debug: Checking ", current.name, " has methods? ", current.has_method("set_state"))
		
		# Duck-typing check instead of strict class check to avoid reloading issues
		if current.has_method("set_state") and current.has_method("set_ghost_valid"):
			return current
		current = current.get_parent()
	return null

func _find_collision_objects(node: Node, results: Array) -> void:
	if node is CollisionObject3D:
		results.append(node.get_rid())
	for child in node.get_children():
		_find_collision_objects(child, results)

func _is_position_occupied(pos: Vector3, ignored_collider: Object = null, checking_for_wall: bool = false) -> bool:
	var space_state = get_world_3d().direct_space_state
	# Sphere check with small radius to see if a structure is already there
	var params = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.25 # slightly larger for fuzzy match
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 1 # Match construction layer
	
	if ignored_collider and ignored_collider is CollisionObject3D:
		params.exclude = [ignored_collider.get_rid()]
	
	var intersections = space_state.intersect_shape(params)
	
	for hit in intersections:
		var collider = hit.collider
		var root = _get_construction_root(collider)
		
		if root:
			var root_path = root.scene_file_path.to_lower() if root.scene_file_path else ""
			if checking_for_wall:
				# Use scene file path for more robust check
				if "wall" in root_path:
					print("Debug: Blocked by WALL: ", root.name)
					return true # Blocked by another Wall
			else:
				if "floor" in root_path:
					return true # Blocked by another Floor
	return false

func _place_object() -> void:
	if current_ghost.has_meta("is_valid") and not current_ghost.get_meta("is_valid"):
		return # Block placement if invalid
		
	var new_obj = current_scene_to_build.instantiate()
	get_parent().add_child(new_obj) # Add to main scene root preferably
	new_obj.global_transform = current_ghost.global_transform
	if new_obj.has_method("set_state"):
		new_obj.set_state(ConstructionItemScript.State.PLACED)
