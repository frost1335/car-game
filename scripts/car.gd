extends CharacterBody2D
class_name Car

# - Resistance -
@export var friction: float = -55.0
@export var drag: float = -0.06

# - Handbrake / drifting -
@export var handbrake_friction: float = -30.0

var acceleration: Vector2 = Vector2.ZERO
var handbraking: bool = false

func _apply_resistance(delta: float) -> void:
	if velocity.length() < 5.0:
		velocity = Vector2.ZERO
	var friction_force := velocity * friction * delta
	var drag_force := velocity * velocity.length() * drag * delta
	acceleration += friction_force + drag_force

	if handbraking:
		acceleration += velocity * handbrake_friction * delta
