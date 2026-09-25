extends CharacterBody2D

# --- Movement (same bicycle model as the player car) ---
@export var engine_power: float = 700.0
@export var friction: float = -55.0
@export var drag: float = -0.06
@export var steering_angle: float = 12.0        # LOWER = turns worse
@export var wheel_base: float = 70.0
@export var traction_slow: float = 0.7
@export var traction_fast: float = 0.1
@export var traction_speed_threshold: float = 200.0
@export var max_speed: float = 900.0

# --- Crash ---
# Minimum CLOSING speed (px/s) along the contact normal to wreck.
# Low value = cruisers detonate constantly. Tune against your top speed (~500).
@export var explode_impact_speed: float = 120.0

# --- Arrest ---
@export var arrest_brake: float = 400.0         # how hard we stop once the player is caught

# --- Obstacle impacts ---
@export var min_impact_speed: float = 100.0   # below this, no penalty (lets you nudge walls)
@export var impact_speed_loss: float = 0.6    # fraction of speed scrubbed on a full head-on hit
@export var push_scale: float = 0.8           # impulse applied to RigidBody2D props
@export var wreck_impact_speed: float = 250.0 # at or above this -> destroyed

# Nearby objects list
var nearby: Array[Node2D] = []

# Emits the position because the node frees itself -- the listener needs to
# know WHERE to spawn the explosion effect.
signal exploded(at_position: Vector2)

var target: Node2D = null
var acceleration: Vector2 = Vector2.ZERO
var steer_direction: float = 0.0
var dead: bool = false
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


func _physics_process(delta: float) -> void:
	# queue_free() is DEFERRED to end of frame, so a wrecked car can still get
	# one more physics tick. This flag -- not is_instance_valid() -- is the guard.
	if dead:
		return
		
	acceleration = Vector2.ZERO
	if chasing and target and is_instance_valid(target):
		_chase()
	else:
		_pull_over()
	_apply_resistance(delta)
	_calculate_steering(delta)

	velocity += acceleration * delta

	var pre_move_velocity := velocity

	velocity = velocity.limit_length(max_speed)

	move_and_slide()

	_resolve_contacts()

	if not dead:
		_handle_obstacle_impacts(pre_move_velocity)


func _on_player_busted() -> void:
	# Caught them. We are NOT wrecked -- different outcome, different path.
	chasing = false


func _pull_over() -> void:
	# Stop steering and brake against our own travel direction.
	# normalized() on a zero vector returns ZERO in Godot 4, so this is safe at rest.
	steer_direction = 0.0
	acceleration = -velocity.normalized() * arrest_brake


func _chase() -> void:
	var to_target := target.global_position - global_position
	var max_steer := deg_to_rad(steering_angle)
	var max_steer_avoid := deg_to_rad(steering_angle + 4)
	var chosenn_deg := INF
	var directions: Array[float] = []
	
	steer_direction = clamp(transform.x.angle_to(to_target), -max_steer, max_steer)
	acceleration = transform.x * engine_power
	
	for object in nearby:
		var to_object = object.global_position - global_position
		var obj_deg = rad_to_deg(transform.x.angle_to(to_object))
		var target_deg = rad_to_deg(transform.x.angle_to(to_target))
		var radius = object.get_meta("radius")

		var point_angle = rad_to_deg(asin(radius / to_object.length())) + 20
		
		print(point_angle)
		
		# reset chosen direction
		chosenn_deg = INF
	
		if obj_deg < 60 and obj_deg >= 0:
			if target_deg > obj_deg:
				chosenn_deg = obj_deg + point_angle
			else:
				chosenn_deg =obj_deg - point_angle
		
		if obj_deg < 0 and obj_deg > -60:
			if target_deg > obj_deg:
				chosenn_deg = obj_deg + point_angle
			else:
				chosenn_deg = obj_deg - point_angle
		
		if chosenn_deg != INF:
			directions.append(chosenn_deg)
	
	if directions.size():
		var final_direction = (directions.max() + directions.min()) / 2
		steer_direction = clamp(deg_to_rad(final_direction), -max_steer_avoid, max_steer_avoid)

func _resolve_contacts() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other == null or not is_instance_valid(other):
			continue

		if other.is_in_group("player"):
			# The player owns the bust state; it guards against double-firing.
			if other.has_method("bust"):
				other.bust()

		elif other.is_in_group("police"):
			if _closing_speed(c, other) >= explode_impact_speed:
				# Whoever DETECTS the pair wrecks BOTH -- a stationary car that
				# gets rammed reports no slide collision of its own.
				explode()
				if other.has_method("explode"):
					other.explode()
				return       # we're dead; stop reading collisions


func _closing_speed(c: KinematicCollision2D, other: Object) -> float:
	var other_vel := Vector2.ZERO
	if other is CharacterBody2D:
		other_vel = other.velocity
	# How fast we're driving INTO each other along the contact normal.
	# A side-swipe at speed projects to ~0 -> scrape, not explosion.
	return absf((velocity - other_vel).dot(c.get_normal()))


func explode() -> void:
	if dead:      # idempotent -- safe to call from the other car
		return
	dead = true
	exploded.emit(global_position)
	queue_free()


func _apply_resistance(delta: float) -> void:
	if velocity.length() < 5.0:
		velocity = Vector2.ZERO
	var friction_force := velocity * friction * delta
	var drag_force := velocity * velocity.length() * drag * delta
	acceleration += drag_force + friction_force


func _calculate_steering(delta: float) -> void:
	var rear_wheel := position - transform.x * wheel_base / 2.0
	var front_wheel := position + transform.x * wheel_base / 2.0
	rear_wheel += velocity * delta
	front_wheel += velocity.rotated(steer_direction) * delta
	var new_heading := rear_wheel.direction_to(front_wheel)

	var grip := traction_slow
	if velocity.length() > traction_speed_threshold:
		grip = traction_fast

	var d := new_heading.dot(velocity.normalized())
	if d > 0:
		velocity = velocity.lerp(new_heading * velocity.length(), grip)
	elif d < 0:
		velocity = -new_heading * velocity.length()

	rotation = new_heading.angle()

func _handle_obstacle_impacts(pre_velocity: Vector2) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var other := c.get_collider()
		if other == null or not is_instance_valid(other):
			continue

		# Cars are handled by the existing contact logic -- don't double-dip
		if other.is_in_group("police") or other.is_in_group("player"):
			continue

		# Shove movable props out of the way
		if other is RigidBody2D:
			var into := -c.get_normal()
			var closing := pre_velocity.dot(into)   # how fast we're driving INTO it
			if closing > 0.0:
				# impulse = desired velocity change * mass  ->  predictable result
				other.apply_central_impulse(into * closing * push_scale * other.mass)
			continue

		# How hard did we drive INTO the surface? (0 = parallel scrape)
		var impact := absf(pre_velocity.dot(c.get_normal()))

		# Hard enough hit -> destroyed
		if impact >= wreck_impact_speed:
			explode()          # police_car.gd
			return

		# Survivable hit -> just lose speed
		if impact < min_impact_speed:
			continue
		var severity := clampf(impact / maxf(pre_velocity.length(), 1.0), 0.0, 1.0)
		velocity *= 1.0 - impact_speed_loss * severity

func _on_area_2d_body_entered(obj: Node2D) -> void:
	nearby.append(obj)


func _on_area_2d_body_exited(obj: Node2D) -> void:
	var idx = nearby.find(obj)
	nearby.remove_at(idx)
