extends CanvasLayer

@onready var restart_button: Button = $Center/Box/RestartButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# CanvasLayer is a Node, NOT a CanvasItem, so it has no show()/hide().
	# Toggle the `visible` property instead (this exists in Godot 4).
	visible = false
	restart_button.pressed.connect(_on_restart_pressed)

# The main scene calls this when the player's `busted` signal fires.
func show_screen() -> void:
	visible = true
	
func _on_restart_pressed() -> void:
	restart()
 
func _unhandled_input(event: InputEvent) -> void:
	# Keyboard restart -- you'll hit this hundreds of times while tuning.
	# Guard on `visible` so R does nothing during normal play.
	if visible and event.is_action_pressed("restart"):
		restart()
 
func restart() -> void:
	# Rebuilds the whole scene from scratch: player, police, spawner, all reset.
	get_tree().reload_current_scene()
