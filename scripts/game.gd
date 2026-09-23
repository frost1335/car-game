extends Node2D

@onready var game_over := $GameOver

func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	player.busted.connect(_on_busted)
	player.wrecked.connect(_on_wrecked)

func _on_busted() -> void:
	game_over.show_screen()

func _on_wrecked(_at: Vector2) -> void:
	game_over.show_screen()
