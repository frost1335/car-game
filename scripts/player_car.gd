extends Car 

# - Braking -
@export var braking: float = -450.0

# --- Handbrake / drifting ---
@export var handbrake_steering_mult: float = 1.6

# --- Bust roll-out ---
@export var bust_roll_time: float = 2.0    # seconds of slow rolling before full stop
@export var bust_speed: float = 80.0       # crawl speed while busted
@export var bust_decel: float = 500.0      # how fast we drop down to bust_speed

# Connect to THIS, once, in your main scene. It never changes as police spawn/die.
signal busted
signal wrecked(at_position: Vector2)

var _bust_timer: float = 0.0

func _drive(delta: float) -> void:
	if _dead:
		if _bust_timer <= 0.0:
			return                      # already finished, nothing to do
			
		_bust_timer -= delta

		if _bust_timer <= 0.0:
			velocity = Vector2.ZERO     # roll-out finished
			acceleration = Vector2.ZERO
			return
		
		_bust_roll(delta)
	else:
		_get_input()

func _post_move() -> void:
	_check_police_contact()
	
# Called by police that hit us, AND by ourselves when we ram a stopped cruiser.
# Guarded, so both paths firing in the same frame is harmless.
func bust() -> void:
	if _dead:
		return
	_dead = true
	_bust_timer = bust_roll_time
	busted.emit()

func _destroy() -> void:
	if _dead:
		return
	_dead = true
	_bust_timer = 0.0          # zero timer = instant freeze, no roll-out
	velocity = Vector2.ZERO
	wrecked.emit(global_position)

# Lets police cars that spawn AFTER the arrest know not to start chasing.
func is_busted() -> bool:
	return _dead

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
	acceleration = transform.x * engine_power
	
	handbraking = Input.is_action_pressed("handbrake")

	var steer_amount := steering_angle
	if handbraking:
		steer_amount *= handbrake_steering_mult

	var turn := Input.get_axis("turn_left", "turn_right")
	steer_direction = turn * deg_to_rad(steer_amount)
	
	if Input.is_action_pressed("brake"):
		acceleration = transform.x * braking
