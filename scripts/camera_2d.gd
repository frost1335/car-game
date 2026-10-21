extends Camera2D

@export var decay: float = 2.5                     # trauma lost per second
@export var max_offset: Vector2 = Vector2(24, 18)  # pixels at full trauma

var trauma: float = 0.0

func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)

func _process(delta: float) -> void:
	if trauma <= 0.0:
		offset = Vector2.ZERO
		return
	trauma = maxf(trauma - decay * delta, 0.0)
	var shake := trauma * trauma
	offset = Vector2(
		randf_range(-1.0, 1.0) * max_offset.x * shake,
		randf_range(-1.0, 1.0) * max_offset.y * shake
	)
