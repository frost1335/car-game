extends Line2D

@onready var RearRightWheel = $"../Visuals/WheelRR"

func _process(delta: float) -> void:
	add_point(RearRightWheel.global_position)
