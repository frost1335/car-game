extends Line2D

@onready var RearLeftWheel = $"../Visuals/WheelRL"

func _process(delta: float) -> void:
	add_point(RearLeftWheel.global_position)
