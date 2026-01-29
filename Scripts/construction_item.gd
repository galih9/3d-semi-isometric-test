extends Node3D
class_name ConstructionItem

enum State {GHOST, PLACED}

var current_state: State = State.PLACED
var ghost_material_override: StandardMaterial3D

@onready var collision_shapes: Array[CollisionShape3D] = []
@onready var mesh_instances: Array[MeshInstance3D] = []

func _ready() -> void:
	# Find all collision shapes and meshes recursively if needed, 
	# but for now we assume they are children or grandchildren.
	_find_children_nodes(self)

func _find_children_nodes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			collision_shapes.append(child)
		elif child is MeshInstance3D:
			mesh_instances.append(child)
		
		# Recursive search
		if child.get_child_count() > 0:
			_find_children_nodes(child)

func set_state(state: State) -> void:
	current_state = state
	
	match state:
		State.GHOST:
			# Disable collisions
			for shape in collision_shapes:
				shape.disabled = true
			
			# Apply visual ghost effect (e.g., transparency/green tint)
			_apply_ghost_visuals()
			
		State.PLACED:
			# Enable collisions
			for shape in collision_shapes:
				shape.disabled = false
			
			# Restore original visuals
			_restore_visuals()

func _apply_ghost_visuals() -> void:
	if not ghost_material_override:
		ghost_material_override = StandardMaterial3D.new()
		ghost_material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_material_override.albedo_color = Color(0.2, 1.0, 0.2, 0.5) # Semi-transparent green
	
	for mesh in mesh_instances:
		# Store original material if not already? 
		# For simplicity, we just override component materials
		mesh.material_override = ghost_material_override

func _restore_visuals() -> void:
	for mesh in mesh_instances:
		mesh.material_override = null
