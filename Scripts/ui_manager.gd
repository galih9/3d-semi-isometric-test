extends CanvasLayer

# --- Nodes ---
@onready var hud: Control = $HUD
@onready var ammo_label: Label = $HUD/AmmoLabel
@onready var hp_bar: ProgressBar = $HUD/HPBar
@onready var hp_label: Label = $HUD/HPBar/HPLabel
@onready var pause_menu: Control = $PauseMenu
@onready var resume_button: Button = $PauseMenu/ResumeButton
@onready var game_over_menu: Control = $GameOverMenu
@onready var restart_button: Button = $GameOverMenu/RestartButton

# --- State ---
var player: Node3D
var gun: Node3D
var is_game_over: bool = false

func _ready() -> void:
	# Hide menus
	pause_menu.visible = false
	game_over_menu.visible = false
	hud.visible = true
	
	# Connect Button
	restart_button.pressed.connect(_on_restart_pressed)
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	
	# Find Player and Gun to connect signals
	# We wait a frame to ensure they are ready
	await get_tree().process_frame
	
	player = get_tree().get_first_node_in_group("player")
	if not player:
		# Fallback
		player = get_tree().root.find_child("Player", true, false)
	
	if player:
		if player.has_signal("health_changed"):
			player.health_changed.connect(_on_health_changed)
		if player.has_signal("player_died"):
			player.player_died.connect(_on_player_died)
			
		# Try to find gun on player
		# Assuming structure: Player -> ... -> Gun
		# Or check member variable 'gun' in player script
		if "gun" in player and player.gun:
			gun = player.gun
			if gun.has_signal("ammo_changed"):
				gun.ammo_changed.connect(_on_ammo_changed)
			# Initial update
			if "current_ammo" in gun:
				_on_ammo_changed(gun.current_ammo)
		
		# Initial HP update
		if "current_hp" in player and "max_hp" in player:
			_on_health_changed(player.current_hp, player.max_hp)

func _input(event: InputEvent) -> void:
	if is_game_over:
		return
		
	if event.is_action_pressed("ui_cancel"): # ESC
		toggle_pause()

func toggle_pause() -> void:
	var tree = get_tree()
	tree.paused = not tree.paused
	
	if tree.paused:
		pause_menu.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		pause_menu.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume_pressed() -> void:
	toggle_pause()

func _on_health_changed(current: float, max_v: float) -> void:
	if hp_bar:
		hp_bar.max_value = max_v
		hp_bar.value = current
	if hp_label:
		hp_label.text = "HP: %d / %d" % [int(current), int(max_v)]

func _on_ammo_changed(amount: int) -> void:
	if ammo_label:
		if amount == 0:
			ammo_label.text = "RELOADING..."
		else:
			ammo_label.text = "Ammo: %d" % amount

func _on_player_died() -> void:
	is_game_over = true
	get_tree().paused = true
	game_over_menu.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_restart_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
