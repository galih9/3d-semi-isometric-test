extends Node3D

@onready var label_3d: Label3D = $Label3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hit_delay_timer: Timer = $HitDelay
@onready var area_3d: Area3D = $Area3D

var hits_remaining: int = 8
var player_in_range: bool = false
var can_hit: bool = true

func _ready() -> void:
	# Connect signals
	area_3d.body_entered.connect(_on_area_3d_body_entered)
	area_3d.body_exited.connect(_on_area_3d_body_exited)
	hit_delay_timer.timeout.connect(_on_hit_delay_timeout)
	
	# Ensure initial state
	label_3d.visible = false
	can_hit = true

func _unhandled_input(event: InputEvent) -> void:
	if player_in_range and event.is_action_pressed("interact"):
		if can_hit:
			harvest_tree()

func harvest_tree() -> void:
	if hits_remaining <= 0:
		return
		
	can_hit = false
	hits_remaining -= 1
	
	animation_player.play("hit")
	hit_delay_timer.start()
	
	if hits_remaining <= 0:
		# Wait for animation to finish or just Queue free? 
		# "8 hit total before dissapeared". 
		# Let's wait for the hit animation to play a bit or fully
		# But the timer is 0.8s. The animation is 0.8s.
		# If we play animation, we should wait.
		# We can connect to animation_finished signal for the last hit, 
		# or just rely on the timer if we want to be safe.
		# But to be responsive, let's queue_free after a slight delay or rely on animation finish.
		# Simpler: Connect animation_finished for the kill.
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)

func _on_hit_delay_timeout() -> void:
	can_hit = true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.name == "Player":
		player_in_range = true
		label_3d.visible = true

func _on_area_3d_body_exited(body: Node3D) -> void:
	if body.name == "Player":
		player_in_range = false
		label_3d.visible = false

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "hit" and hits_remaining <= 0:
		queue_free()
