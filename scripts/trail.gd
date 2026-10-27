extends Line2D

func add_world_point(target_position: Vector2) -> void:
	add_point(target_position)

func detach() -> void:
	var tween = create_tween()

	tween.tween_property(self, "modulate:a", 0, 3.5)
	tween.tween_callback(queue_free)
