extends CharacterBody2D
class_name Car

# - Engine / movement -
@export var engine_power: float = 800.0
@export var max_speed := 900.0
@export var max_reverse_speed: float = 250.0

# - Steering (bicycle model) -
@export var steering_angle: float = 15.0
@export var wheel_base: float = 70.0

# - Traction -
@export var traction_slow: float = 0.7
@export var traction_fast: float = 0.1
@export var traction_speed_threshold: float = 200.0

# - Resistance -
@export var friction: float = -55.0
@export var drag: float = -0.06

# - Handbrake / drifting -
@export var handbrake_friction: float = -30.0
@export var handbrake_traction: float = 0.04

# - Obstacle impacts -
@export var min_impact_speed: float = 100.0      # below this, no penalty (lets you nudge walls)
@export var impact_speed_loss: float = 0.6      # fraction of speed scrubbed on a full head-on hit
@export var push_scale: float = 0.8             # impulse applied to RigidBody2D props
@export var wreck_impact_speed: float = 150.0   # at or above this -> destroyed
@export var car_mass: float = 40.0              # much heavier than a cone

# - Trail Scenes
@export var trail: PackedScene

var steer_direction: float = 0.0
var acceleration: Vector2 = Vector2.ZERO
var handbraking: bool = false
var trail_left: Line2D
var trail_right: Line2D
var _roll_distance: float = 0.0
var slip: float

var _dead: bool = false

func _ready() -> void:
	trail_left = trail.instantiate()
	trail_right = trail.instantiate()
	get_tree().current_scene.add_child.call_deferred(trail_left)
	get_tree().current_scene.add_child.call_deferred(trail_right)

func _physics_process(delta: float) -> void:
	acceleration = Vector2.ZERO

	_drive(delta)

	_apply_resistance(delta)

	_calculate_steering(delta)
	
	velocity += acceleration * delta

	var pre_move_velocity := velocity

	velocity = velocity.limit_length(max_speed)

	move_and_slide()

	_post_move()
	

	if not _dead:
		_update_visuals(delta)
		_handle_obstacle_impacts(pre_move_velocity)

func _apply_resistance(delta: float) -> void:
	if velocity.length() < 5.0:
		velocity = Vector2.ZERO
	var friction_force := velocity * friction * delta
	var drag_force := velocity * velocity.length() * drag * delta
	acceleration += friction_force + drag_force

	if handbraking:
		acceleration += velocity * handbrake_friction * delta

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
			var closing := pre_velocity.dot(into)
			if closing > 0.0:
				var impulse: float = closing * push_scale * other.mass
				other.apply_central_impulse(into * impulse)
				# Newton's third law, by hand -- CharacterBody2D won't do this for us
				velocity -= into * (impulse / car_mass)
			continue

		# How hard did we drive INTO the surface? (0 = parallel scrape)
		var impact := absf(pre_velocity.dot(c.get_normal()))

		# Hard enough hit -> destroyed
		if impact >= wreck_impact_speed:
			_destroy()
			return

		# Survivable hit -> just lose speed
		if impact < min_impact_speed:
			continue
		var severity := clampf(impact / maxf(pre_velocity.length(), 1.0), 0.0, 1.0)
		velocity *= 1.0 - impact_speed_loss * severity

func _calculate_steering(delta: float) -> void:
	var rear_wheel := position - transform.x * wheel_base / 2.0
	var front_wheel := position + transform.x * wheel_base / 2.0
	rear_wheel += velocity * delta
	front_wheel += velocity.rotated(steer_direction) * delta
	var new_heading := rear_wheel.direction_to(front_wheel)

	var grip := traction_slow
	if velocity.length() > traction_speed_threshold:
		grip = traction_fast
	if handbraking:
		grip = handbrake_traction

	var d := new_heading.dot(velocity.normalized())
	if handbraking:
		velocity = velocity.lerp(new_heading * velocity.length(), grip)
	elif d > 0:
		velocity = velocity.lerp(new_heading * velocity.length(), grip)
	elif d < 0:
		velocity = -new_heading * min(velocity.length(), max_reverse_speed)

	rotation = new_heading.angle()


func _drive(_delta: float) -> void:
	pass

func _post_move() -> void:
	pass

func _destroy() -> void:
	pass

func _update_visuals(delta: float) -> void:
	$Visuals/WheelFL.rotation = steer_direction
	$Visuals/WheelFR.rotation = steer_direction
	
	var forward_speed := velocity.dot(transform.x)      # signed: negative when reversing
	_roll_distance += forward_speed * delta
	var frame_index := posmod(int(_roll_distance / 32), 4)
	
	slip = absf(velocity.dot(transform.y))
	
	$Visuals/Body.position.y = velocity.dot(transform.y) * 1.3 * delta
	$Visuals/Shadow.position.y = velocity.dot(transform.y) * 1.2 * delta
	
	$Visuals/WheelFL.frame = frame_index
	$Visuals/WheelFR.frame = frame_index
	$Visuals/WheelRL.frame = frame_index
	$Visuals/WheelRR.frame = frame_index
	
	if handbraking and slip > 120:
		if trail_left and trail_right:
			if trail_left.has_method("add_world_point") and trail_right.has_method("add_world_point"):
				trail_left.add_world_point($Visuals/WheelRL.global_position)
				trail_right.add_world_point($Visuals/WheelRR.global_position)
		else:
			trail_left = trail.instantiate()
			trail_right = trail.instantiate()

			get_tree().current_scene.add_child.call_deferred(trail_left)
			get_tree().current_scene.add_child.call_deferred(trail_right)
	else:
		if trail_left and trail_right:
			if trail_left.has_method("detach") and trail_right.has_method("detach"):
				trail_left.detach()
				trail_right.detach()

		trail_left = null
		trail_right = null
