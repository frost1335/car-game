extends CharacterBody2D

# --- Engine / movement ---
@export var engine_power: float = 800.0
@export var braking: float = -450.0
@export var max_reverse_speed: float = 250.0
@export var max_speed := 900.0

# --- Resistance ---
@export var friction: float = -55.0
@export var drag: float = -0.06

# --- Steering (bicycle model) ---
@export var steering_angle: float = 15.0
@export var wheel_base: float = 70.0

# --- Traction ---
@export var traction_slow: float = 0.7
@export var traction_fast: float = 0.1
@export var traction_speed_threshold: float = 200.0

# --- Handbrake / drifting ---
@export var handbrake_traction: float = 0.04
@export var handbrake_friction: float = -30.0
@export var handbrake_steering_mult: float = 1.6

# --- Bust roll-out ---
@export var bust_roll_time: float = 2.0    # seconds of slow rolling before full stop
@export var bust_speed: float = 80.0       # crawl speed while busted
@export var bust_decel: float = 500.0      # how fast we drop down to bust_speed

# --- Obstacle impacts ---
@export var min_impact_speed: float = 100.0   # below this, no penalty (lets you nudge walls)
@export var impact_speed_loss: float = 0.6    # fraction of speed scrubbed on a full head-on hit
@export var push_scale: float = 0.8           # impulse applied to RigidBody2D props
@export var wreck_impact_speed: float = 250.0   # at or above this -> destroyed
@export var car_mass: float = 40.0    # much heavier than a cone

# Connect to THIS, once, in your main scene. It never changes as police spawn/die.
signal busted
signal wrecked(at_position: Vector2)

var acceleration: Vector2 = Vector2.ZERO
var steer_direction: float = 0.0
var handbraking: bool = false
var _disabled: bool = false
var _bust_timer: float = 0.0
 
func _physics_process(delta: float) -> void:
	acceleration = transform.x * engine_power

	if _disabled:
		if _bust_timer <= 0.0:
			return                      # fully stopped, nothing left to do
		_bust_timer -= delta
		if _bust_timer <= 0.0:
			velocity = Vector2.ZERO     # roll-out finished
			return
		_bust_roll(delta)
	else:
		_get_input()
		_apply_resistance(delta)

	_calculate_steering(delta)

	velocity += acceleration * delta

	var pre_move_velocity := velocity

	velocity = velocity.limit_length(max_speed)
	move_and_slide()


	if not _disabled:
		_handle_obstacle_impacts(pre_move_velocity)
		_check_police_contact()

# Called by police that hit us, AND by ourselves when we ram a stopped cruiser.
# Guarded, so both paths firing in the same frame is harmless.
func bust() -> void:
	if _disabled:
		return
	_disabled = true
	_bust_timer = bust_roll_time
	busted.emit()

func wreck() -> void:
	if _disabled:
		return
	_disabled = true
	_bust_timer = 0.0          # zero timer = instant freeze, no roll-out
	velocity = Vector2.ZERO
	wrecked.emit(global_position)

# Lets police cars that spawn AFTER the arrest know not to start chasing.
func is_busted() -> bool:
	return _disabled

func _bust_roll(delta: float) -> void:
	steer_direction = 0.0       # controls are dead
	var speed := velocity.length()
	if speed > bust_speed:
		velocity = velocity.normalized() * move_toward(speed / 1.3, bust_speed, bust_decel * delta)

func _check_police_contact() -> void:
	# Needed because move_and_slide() only reports collisions caused by OUR
	# movement -- if we ram a pinned cruiser, only we notice.
	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider()
		if other and is_instance_valid(other) and other.is_in_group("police"):
			bust()
			return

func _get_input() -> void:
	handbraking = Input.is_action_pressed("handbrake")

	var steer_amount := steering_angle
	if handbraking:
		steer_amount *= handbrake_steering_mult

	var turn := Input.get_axis("turn_left", "turn_right")
	steer_direction = turn * deg_to_rad(steer_amount)
	
	if Input.is_action_pressed("brake"):
		acceleration = transform.x * braking

func _apply_resistance(delta: float) -> void:
	if velocity.length() < 5.0:
		velocity = Vector2.ZERO
	var friction_force := velocity * friction * delta
	var drag_force := velocity * velocity.length() * drag * delta
	acceleration += drag_force + friction_force

	if handbraking:
		acceleration += velocity * handbrake_friction * delta


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
			# explode()          # police_car.gd
			wreck()          # car.gd -- use this line instead
			return

		# Survivable hit -> just lose speed
		if impact < min_impact_speed:
			continue
		var severity := clampf(impact / maxf(pre_velocity.length(), 1.0), 0.0, 1.0)
		velocity *= 1.0 - impact_speed_loss * severity
