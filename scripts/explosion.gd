extends Node2D

@onready var fireball: AnimatedSprite2D = $Fireball

func _ready() -> void:
	fireball.play("explode")              # match your animation name
	fireball.animation_finished.connect(queue_free)
