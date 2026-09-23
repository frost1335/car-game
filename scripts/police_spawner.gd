extends Node2D

@export var police_scene: PackedScene = preload("res://scenes/PoliceCar.tscn")   # drag PoliceCar.tscn into this slot
@export var spawn_interval: float = 4.0    # seconds between spawns
@export var spawn_radius: float = 700.0    # distance from player; keep > view size
@export var max_police: int = 5            # cap so you don't get swarmed

var player: Node2D = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

	var timer := Timer.new()
	timer.wait_time = spawn_interval
	timer.timeout.connect(_spawn_police)
	add_child(timer)
	timer.start()


func _spawn_police() -> void:
	if police_scene == null:
		return
	# Re-find the player if we don't have it yet
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		return
	if get_tree().get_nodes_in_group("police").size() >= max_police:
		return

	var police := police_scene.instantiate()
	# Random direction around the player -> "spawns from any direction"
	var angle := randf() * TAU
	police.global_position = player.global_position + Vector2.RIGHT.rotated(angle) * spawn_radius
	get_tree().current_scene.add_child(police)
