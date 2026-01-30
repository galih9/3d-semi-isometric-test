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

# Grid Data System
# Stores occupied positions. Key: Vector3i (grid coord), Value: Node (or true)
var occupied_cells: Dictionary = {}
const GRID_PRECISION: float = 2.0 # Multiplier to convert 0.5 steps to integers.
# Floor (0,0,0) -> 0,0,0. Wall (0.5, 0, 0) -> 1,0,0. (If we use *2)
# Grid Size is 1.0. Wall offsets are 0.5.
# Keys will be Vector3i( round(pos.x * 2), round(pos.y * 2), round(pos.z * 2) )


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
	
	# Initialize Grid
	call_deferred("_scan_existing_placements")

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
				var is_occupied = _is_position_occupied(snapped_transform, hit_collider, building_a_wall)
				
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
			
			if not _is_position_occupied(snapped_transform, hit_collider):
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
			print("Debug: Calling occupancy check for Wall Grid Snap. Ignore: ", hit_collider.name if hit_collider else "NULL")
			if not _is_position_occupied(snapped_transform, hit_collider, true):
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
				if not _is_position_occupied(Transform3D(Basis(), current_ghost.global_position), null, false):
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

func _is_position_occupied(ghost_transform: Transform3D, ignored_collider: Object = null, checking_for_wall: bool = false) -> bool:
	var space_state = get_world_3d().direct_space_state
	var params = PhysicsShapeQueryParameters3D.new()
	
	# Default to Sphere if no ghost (fallback)
	if not current_ghost:
		var shape = SphereShape3D.new()
		shape.radius = 0.25
		params.shape = shape
		params.transform = ghost_transform
		return _check_params_occupancy(space_state, params, ignored_collider, checking_for_wall)
	
	var is_occupied = false
	var shapes_found = []
	
	# We search children so offsets are relative to Ghost Root (Identity)
	for child in current_ghost.get_children():
		_find_collision_shapes_recursive(child, shapes_found, Transform3D())
	
	if shapes_found.size() > 0:
		print("Debug: Validating Ghost with ", shapes_found.size(), " shapes.")
		for item in shapes_found:
			var shape = item["shape"]
			var local_transform = item["transform"]
			
			# HANDLE CONCAVE SHAPES (Not supported in intersect_shape)
			if shape is ConcavePolygonShape3D:
				# Converting Concave to Box (AABB) for validation
				var faces = shape.get_faces()
				if faces.size() > 0:
					var min_vec = faces[0]
					var max_vec = faces[0]
					for vertex in faces:
						min_vec = min_vec.min(vertex)
						max_vec = max_vec.max(vertex)
					
					var size = max_vec - min_vec
					var center = (min_vec + max_vec) / 2.0
					
					var box = BoxShape3D.new()
					box.size = size
					
					params.shape = box
					# Adjust transform to include AABB center offset
					params.transform = ghost_transform * local_transform * Transform3D(Basis(), center)
				else:
					# Empty concave shape? Skip or fallback.
					print("Debug: Warning - Empty Concave Shape found. Skipping.")
					continue
			else:
			# Use original Convex or Primitive shape
				params.shape = shape
				params.transform = ghost_transform * local_transform
			
			# SHRINK SHAPE SLIGHTLY (Optional now that we use Grid Data, but good for Physics check)
			params.transform.basis = params.transform.basis.scaled(Vector3(0.95, 0.95, 0.95))
			
			if _check_params_occupancy(space_state, params, ignored_collider, checking_for_wall):
				is_occupied = true
				break
	
	else:
		# Fallback if ghost has no collision shape helper
		print("Debug: Warning - No CollisionShapes found in Ghost. using Fallback Sphere.")
		var shape = SphereShape3D.new()
		shape.radius = 0.25
		params.shape = shape
		params.transform = ghost_transform
		return _check_params_occupancy(space_state, params, ignored_collider, checking_for_wall)
	
	return is_occupied

# Helper to get unique grid key from world position
func _get_cell_key(pos: Vector3) -> Vector3i:
	# Grid Logic: 1.0 units. Walls at 0.5 offsets.
	# We multiply by 2 to distinguish 0.0 and 0.5
	return Vector3i(round(pos.x * 2.0), round(pos.y * 2.0), round(pos.z * 2.0))

func _scan_existing_placements() -> void:
	occupied_cells.clear()
	# Scan parent for existing construction items
	# This is a best-effort scan for pre-placed items
	var parent_node = get_parent()
	if not parent_node: return
	
	for child in parent_node.get_children():
		# identifying construction items by script or group could be better,
		# for now, let's assume if it has 'set_state' it's one of ours.
		if child.has_method("set_state") and child != current_ghost:
			var key = _get_cell_key(child.global_position)
			occupied_cells[key] = child
			print("Debug: Registered existing item at ", key)

func _check_params_occupancy(space_state, params, ignored_collider, checking_for_wall) -> bool:
	# First: Check Grid Data (Logic Check)
	# We calculate the key for the position we are testing.
	# params.transform.origin gives the world position of the shape center.
	# For Walls, the shape center is the wall center.
	# Note: This checks the specific shape center.
	# The ghost root might be at (0,0), but a child shape might be at (0.5, 0).
	# This is actually GOOD for multi-part objects!
	var key = _get_cell_key(params.transform.origin)
	if occupied_cells.has(key):
		var occupier = occupied_cells[key]
		if occupier != ignored_collider:
			print("Debug: Validated by Grid Data! Blocked by ", occupier.name, " at ", key)
			return true

	# Second: Physics Check (Terrain/Obstacles)
	if ignored_collider and ignored_collider is CollisionObject3D:
		params.exclude = [ignored_collider.get_rid()]
	
	var intersections = space_state.intersect_shape(params)
	
	for hit in intersections:
		var collider = hit.collider
		if collider == ignored_collider: continue
			
		var root = _get_construction_root(collider)
		if root:
			# If we hit a Construction Item, we generally rely on Grid Data.
			# BUT: If the item was NOT in occupied_cells (e.g. slight misalignment or unregistered),
			# we might want to respect physics.
			# However, user says physics causes issues with neighbors.
			# So we explicitly IGNORE ConstructionItems in Physics check if we trust Grid Data.
			# Let's trust Grid Data for "Construction vs Construction".
			continue
		else:
			# Hit Terrain/Rocks/Statics
			print("Debug: Blocked by STATIC OBSTACLE: ", collider.name)
			return true
	
	return false

func _find_collision_shapes_recursive(node: Node, results: Array, parent_accumulated_transform: Transform3D = Transform3D()) -> void:
	var current_transform = parent_accumulated_transform
	if node is Node3D:
		current_transform = parent_accumulated_transform * node.transform
		
	if node is CollisionShape3D:
		results.append({
			"shape": node.shape,
			"transform": current_transform
		})
	
	for child in node.get_children():
		_find_collision_shapes_recursive(child, results, current_transform)


func _place_object() -> void:
	if current_ghost.has_meta("is_valid") and not current_ghost.get_meta("is_valid"):
		return # Block placement if invalid
		
	var new_obj = current_scene_to_build.instantiate()
	get_parent().add_child(new_obj)
	new_obj.global_transform = current_ghost.global_transform
	if new_obj.has_method("set_state"):
		new_obj.set_state(ConstructionItemScript.State.PLACED)
	
	# Register to Grid Data
	var key = _get_cell_key(new_obj.global_position)
	occupied_cells[key] = new_obj
	print("Debug: Placed and Registered at ", key)
