extends Node2D

@onready var lightbar_ainmation = $AnimationPlayer

func _ready() -> void:
	lightbar_ainmation.play("light")
	lightbar_ainmation.seek(randf() * lightbar_ainmation.current_animation_length)
	lightbar_ainmation.speed_scale = randf_range(0.9, 1.1)
