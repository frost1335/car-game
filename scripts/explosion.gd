extends Node2D

@onready var explosion_animation: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	explosion_animation.play("boom")              # match your animation name
	explosion_animation.animation_finished.connect(queue_free)
