extends CharacterBody2D

# Define all possible states
enum State {
	IDLE,
	WALK,
	ATTACK,
	HITSTUN,
	DEATH,
	DASH,
}

@export var speed: float = 200.0
@export var jump_force := 350.0
@export var max_health: int = 100
@export var invuln_time := 0.4
@export var attack_time := 0.2
@export var input_buffer_time := 0.25
@export var input_enabled := true
@export var dash_speed: float = 800.0
@export var dash_unit_size: int = 64

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var current_state: State = State.IDLE
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimatedSprite2D/AnimationPlayer
@onready var attack_hitbox: Area2D = $AnimatedSprite2D/AttackHitbox
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
var health: int = max_health
var invulnerable := false
var pending_d := false
var pending_d_timer := 0.0
var attack_direction := Vector2.ZERO
var attack_requested := false
var attack_animation := "attack_dir"
var neutral_combo_step := 0
var neutral_combo_timer := 0.0
var hitbox_offset := Vector2.ZERO

# Count input buffering
var pending_count: String = ""
var pending_count_timer: float = 0.0

# Dash tracking
var dash_target: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.ZERO
var dash_remaining_time: float = 0.0

signal health_changed(current: int, max: int)
signal died


func _ready():
	# Add player to group for easy lookup
	add_to_group("player")
	# Enter the initial state
	health = max_health
	emit_signal("health_changed", health, max_health)
	if animation_player:
		animation_player.stop()
	if attack_hitbox:
		attack_hitbox.monitoring = false
		hitbox_offset = attack_hitbox.position
		attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	enter_state(current_state)


func _physics_process(delta):
	if neutral_combo_timer > 0.0 and current_state != State.ATTACK:
		neutral_combo_timer -= delta
		if neutral_combo_timer <= 0.0:
			neutral_combo_step = 0

	if pending_d:
		pending_d_timer -= delta
		if pending_d_timer <= 0.0:
			pending_d = false

	# Count buffer timeout
	if pending_count_timer > 0.0:
		pending_count_timer -= delta
		if pending_count_timer <= 0.0:
			pending_count = ""

	# Apply vertical physics every frame (skip during horizontal dash)
	if not is_on_floor() and not (current_state == State.DASH and dash_direction.x != 0):
		velocity.y += gravity * delta
	if input_enabled and is_on_floor() and Input.is_key_pressed(KEY_K):
		velocity.y = -jump_force

	# Call the handler for whatever state we're in
	match current_state:
		State.IDLE:
			state_idle(delta)
		State.WALK:
			state_walk(delta)
		State.ATTACK:
			state_attack(delta)
		State.HITSTUN:
			state_hitstun(delta)
		State.DEATH:
			state_death(delta)
		State.DASH:
			state_dash(delta)

	# Apply movement/gravity
	move_and_slide()



# === STATE CHANGE FUNCTION ===

func change_state(new_state: State):
	if new_state == current_state:
		return  # Already in this state

	exit_state(current_state)   # Clean up old state
	current_state = new_state
	enter_state(new_state)       # Set up new state


# === ENTER/EXIT HANDLERS ===

func enter_state(state: State):
	match state:
		State.IDLE:
			animated_sprite.play("idle")
			if attack_hitbox:
				attack_hitbox.monitoring = false
		State.WALK:
			animated_sprite.play("walk")
			if attack_hitbox:
				attack_hitbox.monitoring = false
		State.ATTACK:
			animated_sprite.play(attack_animation)
			if attack_hitbox:
				attack_hitbox.monitoring = true
			_start_attack_recovery()
		State.HITSTUN:
			animated_sprite.play("hit")
			invulnerable = true
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			_start_hitstun_recovery()
		State.DEATH:
			animated_sprite.play("death")
			input_enabled = false
			invulnerable = true
			if attack_hitbox:
				attack_hitbox.monitoring = false
			_start_death_cleanup()
		State.DASH:
			animated_sprite.play("walk")  # Use walk animation for dashing


func exit_state(state: State):
	# Clean up when leaving a state (optional)
	match state:
		State.IDLE:
			pass  # Nothing to clean up
		State.WALK:
			pass
		State.ATTACK:
			pass
		State.HITSTUN:
			pass
		State.DEATH:
			pass
		State.DASH:
			pass  # Nothing to clean up


# === STATE LOGIC ===

func state_idle(_delta):
	# Check for movement input
	var direction = get_input_direction(_delta)
	velocity.x = 0.0

	if input_enabled and attack_requested:
		attack_requested = false
		change_state(State.ATTACK)
		return

	if direction != Vector2.ZERO:
		change_state(State.WALK)


func state_walk(_delta):
	var direction = get_input_direction(_delta)

	if input_enabled and attack_requested:
		attack_requested = false
		change_state(State.ATTACK)
		return

	# No input? Go back to idle
	if direction == Vector2.ZERO:
		velocity.x = 0.0
		change_state(State.IDLE)
		return

	# Move the player
	velocity.x = direction.x * speed

	# Flip sprite based on direction
	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
		_update_hitbox_side()


func state_attack(_delta):
	# Lock movement while attacking
	velocity.x = 0.0
	if attack_direction.x != 0:
		animated_sprite.flip_h = attack_direction.x < 0
		_update_hitbox_side()


func state_hitstun(_delta):
	# Lock movement while invulnerable from a hit
	velocity.x = 0.0


func state_death(_delta):
	velocity = Vector2.ZERO


func state_dash(delta):
	dash_remaining_time -= delta

	# Set velocity for collision detection via move_and_slide()
	if dash_direction.y != 0:
		velocity.y = dash_direction.y * dash_speed
		velocity.x = 0
	else:
		velocity.x = dash_direction.x * dash_speed
		velocity.y = 0  # Suspend gravity during horizontal dash

	# End conditions
	if dash_remaining_time <= 0 or is_on_wall():
		velocity = Vector2.ZERO
		change_state(State.IDLE)


# === HELPER FUNCTIONS ===

func get_input_direction(delta) -> Vector2:
	var direction = Vector2.ZERO
	if not is_multiplayer_authority():
		return Vector2.ZERO
	if not input_enabled:
		return direction
	if Input.is_key_pressed(KEY_H):
		direction.x -= 1
	if Input.is_key_pressed(KEY_L):
		direction.x += 1

	return direction


func _update_hitbox_side() -> void:
	if not attack_hitbox:
		return
	var offset_x = abs(hitbox_offset.x)
	attack_hitbox.position.x = -offset_x if animated_sprite.flip_h else offset_x


func _input(event) -> void:
	if not is_multiplayer_authority():
		return
	if not input_enabled:
		return
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if current_state == State.HITSTUN:
		return

	var code = event.keycode

	# Number key detection for count buffering
	if code >= KEY_0 and code <= KEY_9:
		# Only accumulate if we haven't reached 2 digits
		if pending_count.length() < 2:
			var digit = code - KEY_0
			pending_count += str(digit)
			pending_count_timer = input_buffer_time
		return

	# Movement key detection with count
	if pending_count != "":
		var count = int(pending_count)
		if count > 0:
			if code == KEY_H:
				_initiate_dash(Vector2.LEFT, count, false)
				pending_count = ""
				return
			elif code == KEY_L:
				_initiate_dash(Vector2.RIGHT, count, false)
				pending_count = ""
				return
			elif code == KEY_J:
				_initiate_dash(Vector2.DOWN, count, true)
				pending_count = ""
				return
			elif code == KEY_K:
				_initiate_dash(Vector2.UP, count, true)
				pending_count = ""
				return

	# Neutral attack: "dd"
	if code == KEY_D:
		if pending_d and pending_d_timer > 0.0:
			pending_d = false
			attack_direction = Vector2.ZERO
			neutral_combo_step = (neutral_combo_step % 3) + 1
			neutral_combo_timer = input_buffer_time
			attack_animation = "neutral_%d" % neutral_combo_step
			attack_requested = true
			return
		pending_d = true
		pending_d_timer = input_buffer_time
		return

	# Directional attack: "d" then front/back
	if pending_d and pending_d_timer > 0.0:
		if code == KEY_W:
			pending_d = false
			attack_direction = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
			attack_animation = "attack_dir"
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			attack_requested = true
			return
		if code == KEY_B:
			pending_d = false
			attack_direction = Vector2.RIGHT if animated_sprite.flip_h else Vector2.LEFT
			attack_animation = "attack_dir"
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			attack_requested = true
			return

	# Vim movement: 'w' = forward (right) 5 tiles, 'b' = backward (left) 5 tiles
	if code == KEY_W:
		_initiate_dash(Vector2.RIGHT, 5, false)
		return
	if code == KEY_B:
		_initiate_dash(Vector2.LEFT, 5, false)
		return


func _initiate_dash(direction: Vector2, count: int, is_vertical: bool):
	# Calculate target position based on relative grid numbering
	var target = global_position

	if is_vertical:
		# Vertical movement: teleport to count grids up/down
		var current_row = round(global_position.y / dash_unit_size)
		var target_row = current_row + (count * int(direction.y))
		target.y = target_row * dash_unit_size
	else:
		# Horizontal movement: teleport to count grids left/right
		var current_col = round(global_position.x / dash_unit_size)
		var target_col = current_col + (count * int(direction.x))
		target.x = target_col * dash_unit_size

	# Test for collision at target position
	var original_pos = global_position
	global_position = target

	# Use move_and_collide to check for collisions
	var test_motion = PhysicsTestMotionParameters2D.new()
	test_motion.from = PhysicsServer2D.body_get_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM)
	test_motion.motion = Vector2.ZERO

	var result = PhysicsTestMotionResult2D.new()
	var collision = PhysicsServer2D.body_test_motion(get_rid(), test_motion, result)

	if collision:
		# Collision detected, revert to original position
		global_position = original_pos
		print("Cannot teleport: collision at target position")
	else:
		# No collision, teleport successful
		print("Teleported to: ", global_position)

		# Flip sprite based on horizontal movement
		if direction.x != 0:
			animated_sprite.flip_h = direction.x < 0


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	if invulnerable:
		return
	health = max(health - amount, 0)
	emit_signal("health_changed", health, max_health)
	if health == 0:
		emit_signal("died")
		change_state(State.DEATH)
		return
	change_state(State.HITSTUN)


@rpc("authority", "call_local", "reliable")
func network_apply_damage(amount: int):
	apply_damage(amount)


func _start_hitstun_recovery() -> void:
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false
	change_state(State.IDLE)


func _start_attack_recovery() -> void:
	var finished = await animated_sprite.animation_finished
	if current_state == State.ATTACK:
		change_state(State.IDLE)


func _start_death_cleanup() -> void:
	await animated_sprite.animation_finished
	if current_state != State.DEATH:
		return
	if collision_polygon:
		collision_polygon.disabled = true
	hide()
	set_process(false)
	set_physics_process(false)


func _on_attack_hitbox_body_entered(body: Node) -> void:
	if current_state != State.ATTACK:
		return
	if body == self:
		return
	# Only server calculates damage
	if not multiplayer.is_server():
		return
	if body.has_method("network_apply_damage"):
		body.network_apply_damage.rpc(10)

		
