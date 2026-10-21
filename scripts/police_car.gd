extends Car

@export var explode_impact_speed: float = 80.0

# - Arrest
@export var arrest_brake: float = 350.0         # how hard we stop once the player is caught

# - Obstacle impacts
@export var steer_rate := 2.0

# - Explosion Scene
@export var explosion_scene: PackedScene

# Emits the position because the node frees itself -- the listener needs to
# know WHERE to spawn the explosion effect.
signal exploded(at_position: Vector2)

# Nearby objects list
var nearby: Array[Node2D] = []

var target: Node2D = null
var chasing: bool = true

func _ready() -> void:
	add_to_group("police")
	target = get_tree().get_first_node_in_group("player")

	# Listen to the player's existing signal. No new signal needed on our side --
	# one emit, every cruiser reacts, nothing to wire up per spawned instance.
	if target and target.has_signal("busted"):
		target.busted.connect(_on_player_busted)
		# Spawned AFTER the player was already caught? Don't start a dead chase.
		if target.has_method("is_busted") and target.is_busted():
			chasing = false

func _drive(delta: float) -> void:
	if _dead:
		return

	if chasing and target and is_instance_valid(target):
		_chase(delta)
	else:
		_pull_over()

func _post_move() -> void:
	_resolve_contacts()

func _on_player_busted() -> void:
	# Caught them. We are NOT wrecked -- different outcome, different path.
	chasing = false

func _pull_over() -> void:
	# Stop steering and brake against our own travel direction.
	# normalized() on a zero vector returns ZERO in Godot 4, so this is safe at rest.
	steer_direction = 0.0
	acceleration = -velocity.normalized() * arrest_brake

func _chase(delta) -> void:
	var to_target := target.global_position - global_position
	var max_steer := deg_to_rad(steering_angle)
	var max_steer_avoid := deg_to_rad(steering_angle + 4)
	var chosenn_deg := INF
	var directions: Array[float] = []
	
	acceleration = transform.x * engine_power
	
	for object in nearby:
		if not is_instance_valid(object):
			continue
		
		var to_object = object.global_position - global_position
		var obj_deg = rad_to_deg(transform.x.angle_to(to_object))
		var target_deg = rad_to_deg(transform.x.angle_to(to_target))
		
		var radius = object.get_meta("radius", 20.0) # 20.0 is a default
		var distance = to_object.length()
		
		var half_angular = rad_to_deg(asin(radius / distance))
		var margin = 30.0

		# reset chosen direction
		chosenn_deg = INF
	
		if abs(obj_deg) < half_angular + margin:
			if target_deg > obj_deg:
				chosenn_deg = obj_deg + (half_angular + 60.0)
			else:
				chosenn_deg = obj_deg - (half_angular + 60.0)

		if chosenn_deg != INF:
			directions.append(chosenn_deg)
	
	if directions.size():
		var final_direction = (directions.max() + directions.min()) / 2
		var desired = clamp(deg_to_rad(final_direction), -max_steer_avoid, max_steer_avoid)
		
		steer_direction = move_toward(steer_direction, desired, steer_rate * delta)
	else:
		steer_direction = clamp(transform.x.angle_to(to_target), -max_steer, max_steer)

func _resolve_contacts() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other == null or not is_instance_valid(other):
			continue

		if other.is_in_group("player"):
			# The player owns the bust state; it guards against double-firing.
			if other.has_method("bust"):
				# When the player is caught the police car destroyed during the process
				_destroy()
				other.bust()

		elif other.is_in_group("police"):
			if _closing_speed(c, other) >= explode_impact_speed:
				# Whoever DETECTS the pair wrecks BOTH -- a stationary car that
				# gets rammed reports no slide collision of its own.
				_destroy()
				if other.has_method("_destroy"):
					other._destroy()
				return       # we're dead; stop reading collisions

func _closing_speed(c: KinematicCollision2D, other: Object) -> float:
	var other_vel := Vector2.ZERO
	if other is CharacterBody2D:
		other_vel = other.velocity
	# How fast we're driving INTO each other along the contact normal.
	# A side-swipe at speed projects to ~0 -> scrape, not explosion.
	return absf((velocity - other_vel).dot(c.get_normal()))

func _destroy() -> void:
	_spawn_explosion()
	if _dead:      # idempotent -- safe to call from the other car
		return
	_dead = true
	exploded.emit(global_position)
	queue_free()

func _spawn_explosion() -> void:
	if explosion_scene == null:
		return
	var boom := explosion_scene.instantiate()
	boom.global_position = global_position
	get_tree().current_scene.add_child.call_deferred(boom)

func _on_area_2d_body_entered(obj: Node2D) -> void:
	nearby.append(obj)

func _on_area_2d_body_exited(obj: Node2D) -> void:
	var idx = nearby.find(obj)

	if idx != -1:
		nearby.remove_at(idx)
