extends Control

@onready var play_button: Button = $CenterContainer/PlayButton

func _ready() -> void:
	# Ensure mouse is visible in menu
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	play_button.pressed.connect(_on_play_pressed)

func _on_play_pressed() -> void:
	# Change to the main game scene
	# Assuming main.tscn is in the root or Scenes folder. 
	# Based on previous file list, "main.tscn" is in the root.
	get_tree().change_scene_to_file("res://main.tscn")
