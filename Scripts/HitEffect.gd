extends Node3D

@onready var sprite = $Sprite3D
var timer: float = 0.0
var current_frame: int = 0
var frame_duration: float = 0.07 # Adjust speed here
var total_frames: int = 4

func _ready() -> void:
	if not sprite:
		return
	
	# Default setup just in case the scene didn't set it
	sprite.hframes = 2
	sprite.vframes = 2
	sprite.frame = 0
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _process(delta: float) -> void:
	timer += delta
	if timer >= frame_duration:
		timer = 0.0
		current_frame += 1
		
		# If we finished all frames, delete the effect
		if current_frame >= total_frames:
			queue_free()
		elif sprite:
			sprite.frame = current_frame
