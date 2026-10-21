extends Node2D

# - Explosion Animation Player
@onready var explosion_animation: AnimationPlayer = $AnimationPlayer

# - Camera shake params
@export var shake_strength: float = 0.6
@export var shake_range: float = 900.0    # beyond this distance, no shake

func _ready() -> void:
	rotation = randf() * TAU
	scale = Vector2.ONE * randf_range(0.9, 1.1)

	explosion_animation.animation_finished.connect(_on_animation_finished)
	explosion_animation.play("boom")

func _on_animation_finished(_anim_name: StringName) -> void:
	queue_free()

func _shake() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null or not cam.has_method("add_trauma"):
		return
	var dist := cam.get_screen_center_position().distance_to(global_position)
	var falloff := clampf(1.0 - dist / shake_range, 0.0, 1.0)
	cam.add_trauma(shake_strength * falloff)
