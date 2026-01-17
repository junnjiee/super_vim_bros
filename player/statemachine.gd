extends CharacterBody2D

# Define all possible states
enum State {
	IDLE,
	WALK,
	JUMP,
	FALL,
	ATTACK,
	BLOCK,
	HITSTUN,
	DEATH,
	DASH,
	INSERT,
}

@export var speed: float = 200.0
@export var jump_force := 350.0
@export var max_health: int = 100
@export var invuln_time := 0.4
@export var attack_time := 0.2
@export var input_buffer_time := 0.25
@export var input_enabled := true
@export var dash_unit_size: int = 64
@export var dir_attack_travel_time: float = 0.12
@export var parry_window_time: float = 0.1

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var current_state: State = State.IDLE
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimatedSprite2D/AnimationPlayer
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hitbox_highlight: ColorRect = $AttackHitbox/ColorRect
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var collision_highlight: ColorRect = $CollisionHighlight
@onready var block_bubble: Polygon2D = $BlockBubble
var health: int = max_health
var invulnerable := false
var pending_d := false
var pending_d_timer := 0.0
var attack_direction := Vector2.ZERO
var attack_requested := false
var attack_animation := "attack_dir"
var attack_tiles := 1
var neutral_combo_step := 0
var neutral_combo_timer := 0.0
var last_remote_animation: StringName = &""
var last_remote_flip_h := false
var block_pressed := false
var block_start_time_ms := 0

# Count input buffering
var pending_count: String = ""
var pending_count_timer: float = 0.0

# Dash tracking
var dash_target: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.ZERO
var attack_travel_tween: Tween = null

# INSERT mode tracking
var in_insert_mode := false
var insert_obstacles: Array = []
const MAX_INSERT_OBSTACLES = 8
const OBSTACLE_SCENE = preload("res://player/insert_obstacle.tscn")

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
		attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	if animated_sprite:
		last_remote_animation = animated_sprite.animation
		last_remote_flip_h = animated_sprite.flip_h
	if hitbox_highlight:
		hitbox_highlight.visible = false
	if collision_highlight:
		var box_size = _get_collision_box_size()
		collision_highlight.size = box_size
		collision_highlight.position = -box_size / 2
		collision_highlight.visible = true
	if block_bubble:
		block_bubble.visible = false
	enter_state(current_state)


func _physics_process(delta):
	if not _is_local_authority():
		_process_remote_visuals()
		return
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

	var on_floor = is_on_floor()

	# Apply vertical physics every frame (skip during teleport dash and death)
	if not on_floor and current_state not in [State.DASH, State.DEATH]:
		velocity.y += gravity * delta
	if input_enabled and on_floor and current_state not in [State.ATTACK, State.HITSTUN, State.DEATH, State.DASH] and Input.is_key_pressed(KEY_K):
		velocity.y = -jump_force
		change_state(State.JUMP)

	# Call the handler for whatever state we're in
	match current_state:
		State.IDLE:
			state_idle(delta)
		State.WALK:
			state_walk(delta)
		State.JUMP:
			state_jump(delta)
		State.FALL:
			state_fall(delta)
		State.ATTACK:
			state_attack(delta)
		State.BLOCK:
			state_block(delta)
		State.HITSTUN:
			state_hitstun(delta)
		State.DEATH:
			state_death(delta)
		State.DASH:
			state_dash(delta)
		State.INSERT:
			state_insert(delta)

	# Apply movement/gravity
	move_and_slide()
	_update_collision_highlight()



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
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
		State.WALK:
			animated_sprite.play("walk")
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
		State.JUMP:
			animated_sprite.play("jump")
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
		State.FALL:
			animated_sprite.play("falling")
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
		State.ATTACK:
			animated_sprite.play(attack_animation)
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				_configure_attack_hitbox(attack_tiles, attack_direction)
			if block_bubble:
				block_bubble.visible = false
			_start_attack_recovery()
		State.BLOCK:
			animated_sprite.play("block")
			animated_sprite.speed_scale = 1.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = true
		State.HITSTUN:
			animated_sprite.play("hit")
			animated_sprite.speed_scale = 1.0
			invulnerable = true
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
			_start_hitstun_recovery()
		State.DEATH:
			animated_sprite.play("death")
			animated_sprite.speed_scale = 1.0
			input_enabled = false
			invulnerable = true
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
			_start_death_cleanup()
		State.DASH:
			animated_sprite.play("disappear")
			animated_sprite.speed_scale = 3.0
			invulnerable = true
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false
			if block_bubble:
				block_bubble.visible = false
			if collision_polygon:
				collision_polygon.disabled = true
			velocity = Vector2.ZERO
			_start_dash_sequence()
		State.INSERT:
			animated_sprite.play("idle")
			animated_sprite.speed_scale = 1.0
			animated_sprite.modulate = Color(1.0, 1.0, 0.7)  # Yellow tint
			in_insert_mode = true
			if attack_hitbox:
				attack_hitbox.monitoring = false
			if hitbox_highlight:
				hitbox_highlight.visible = false


func exit_state(state: State):
	# Clean up when leaving a state (optional)
	match state:
		State.IDLE:
			pass  # Nothing to clean up
		State.WALK:
			pass
		State.ATTACK:
			pass
		State.BLOCK:
			pass
		State.HITSTUN:
			pass
		State.DEATH:
			pass
		State.DASH:
			pass  # Nothing to clean up
		State.INSERT:
			animated_sprite.modulate = Color(1.0, 1.0, 1.0)  # Reset color
			in_insert_mode = false
			# Keep tracking obstacles to enforce FIFO limit across insert sessions


# === STATE LOGIC ===

func state_idle(_delta):
	# Check for movement input
	var direction = get_input_direction(_delta)
	velocity.x = 0.0

	if block_pressed and is_on_floor():
		change_state(State.BLOCK)
		return

	if input_enabled and attack_requested:
		attack_requested = false
		change_state(State.ATTACK)
		return

	if direction != Vector2.ZERO:
		change_state(State.WALK)
		return

	if not is_on_floor():
		if velocity.y < 0:
			change_state(State.JUMP)
		else:
			change_state(State.FALL)


func state_walk(_delta):
	var direction = get_input_direction(_delta)

	if block_pressed and is_on_floor():
		change_state(State.BLOCK)
		return

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

	if not is_on_floor():
		if velocity.y < 0:
			change_state(State.JUMP)
		else:
			change_state(State.FALL)


func state_attack(_delta):
	# Lock movement while attacking
	if is_on_floor():
		velocity.x = 0.0
	else:
		# Keep existing horizontal momentum mid-air
		velocity.x = velocity.x
	_update_attack_hitbox_center()
	if attack_direction.x != 0:
		animated_sprite.flip_h = attack_direction.x < 0


func state_hitstun(_delta):
	# Lock movement while invulnerable from a hit
	velocity.x = 0.0


func state_block(_delta):
	velocity.x = 0.0
	if not block_pressed:
		if block_bubble:
			block_bubble.visible = false
		change_state(State.IDLE)
		return
	var frames = animated_sprite.sprite_frames.get_frame_count("block")
	if frames > 0:
		var last = frames - 1
		if animated_sprite.frame >= last:
			animated_sprite.frame = last
			animated_sprite.stop()


func state_death(_delta):
	velocity = Vector2.ZERO


func state_dash(_delta):
	velocity = Vector2.ZERO


func state_jump(_delta):
	var direction = get_input_direction(_delta)
	velocity.x = direction.x * speed
	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
	if velocity.y > 0:
		change_state(State.FALL)
		return
	if is_on_floor():
		if direction == Vector2.ZERO:
			change_state(State.IDLE)
		else:
			change_state(State.WALK)


func state_fall(_delta):
	var direction = get_input_direction(_delta)
	velocity.x = direction.x * speed
	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0
	if is_on_floor():
		if direction == Vector2.ZERO:
			change_state(State.IDLE)
		else:
			change_state(State.WALK)


func state_insert(_delta):
	# Lock horizontal movement while in insert mode
	velocity.x = 0.0
	# Gravity is applied in _physics_process, so player will fall if airborne


# === HELPER FUNCTIONS ===

func _is_local_authority() -> bool:
	# If no multiplayer peer, we're in singleplayer - always have authority
	if multiplayer.multiplayer_peer == null:
		return true
	return is_multiplayer_authority()


func get_input_direction(delta) -> Vector2:
	var direction = Vector2.ZERO
	if not _is_local_authority():
		return Vector2.ZERO
	if not input_enabled:
		return direction
	if Input.is_key_pressed(KEY_H):
		direction.x -= 1
	if Input.is_key_pressed(KEY_L):
		direction.x += 1

	return direction


func _configure_attack_hitbox(tile_count: int, direction: Vector2) -> void:
	if not attack_hitbox or not attack_shape:
		return
	var shape = attack_shape.shape
	var forward = direction
	if forward == Vector2.ZERO:
		forward = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT

	# Smooth travel for directional attacks (3 tiles only)
	if tile_count > 2:
		var target = global_position + forward * dash_unit_size * tile_count
		var travel_time = _get_animation_length(attack_animation)
		_start_attack_travel(target, travel_time)

	# Size the hitbox to 1x1 tile for neutral, collision box for directional
	var box_size = _get_collision_box_size()
	if tile_count <= 2:
		box_size = Vector2(dash_unit_size, dash_unit_size)
	if shape is RectangleShape2D:
		shape.size = box_size

	var center = Vector2(
		round(global_position.x / dash_unit_size) * dash_unit_size,
		round(global_position.y / dash_unit_size) * dash_unit_size
	)
	if tile_count <= 2:
		center.x += forward.x * dash_unit_size

	attack_hitbox.global_position = center
	attack_hitbox.monitoring = true

	if hitbox_highlight:
		hitbox_highlight.visible = true
		hitbox_highlight.size = box_size
		hitbox_highlight.position = -hitbox_highlight.size / 2


func _update_attack_hitbox_center() -> void:
	if not attack_hitbox or not attack_shape:
		return
	var box_size = _get_collision_box_size()
	if attack_tiles == 1:
		box_size = Vector2(dash_unit_size, dash_unit_size)
	var shape = attack_shape.shape
	if shape is RectangleShape2D:
		shape.size = box_size
	var center = Vector2(
		round(global_position.x / dash_unit_size) * dash_unit_size,
		round(global_position.y / dash_unit_size) * dash_unit_size
	)
	if attack_tiles == 1:
		var forward = attack_direction
		if forward == Vector2.ZERO:
			forward = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
		center.x += forward.x * dash_unit_size
	elif attack_tiles == 2:
		var forward_air = attack_direction
		if forward_air == Vector2.ZERO:
			forward_air = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
		center.x += forward_air.x * dash_unit_size
	attack_hitbox.global_position = center
	if hitbox_highlight:
		hitbox_highlight.visible = true
		hitbox_highlight.size = box_size
		hitbox_highlight.position = -hitbox_highlight.size / 2


func _process_remote_visuals() -> void:
	if not animated_sprite:
		return
	if animated_sprite.animation != last_remote_animation or not animated_sprite.is_playing():
		animated_sprite.play(animated_sprite.animation)
		last_remote_animation = animated_sprite.animation
	if animated_sprite.flip_h != last_remote_flip_h:
		last_remote_flip_h = animated_sprite.flip_h
		_update_attack_hitbox_center()


func _input(event) -> void:
	if not _is_local_authority():
		return
	if not input_enabled:
		return
	if not (event is InputEventKey):
		return
	if event.echo:
		return
	if current_state in [State.HITSTUN, State.DEATH, State.DASH]:
		return

	var code = event.keycode

	if code == KEY_P:
		if event.pressed:
			block_pressed = true
			block_start_time_ms = Time.get_ticks_msec()
			if is_on_floor():
				change_state(State.BLOCK)
		else:
			block_pressed = false
			if current_state == State.BLOCK:
				change_state(State.IDLE)
		return

	if not event.pressed:
		return

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
			attack_direction = Vector2.LEFT if animated_sprite.flip_h else Vector2.RIGHT
			if is_on_floor():
				attack_tiles = 1
				neutral_combo_step = (neutral_combo_step % 3) + 1
				neutral_combo_timer = input_buffer_time
				attack_animation = "neutral_%d" % neutral_combo_step
			else:
				attack_tiles = 2
				attack_animation = "attack_jump"
				neutral_combo_step = 0
				neutral_combo_timer = 0.0
			attack_requested = true
			return
		pending_d = true
		pending_d_timer = input_buffer_time
		return

	# Directional attack: "d" then front/back
	if pending_d and pending_d_timer > 0.0:
		if code == KEY_W:
			pending_d = false
			attack_direction = Vector2.RIGHT  # absolute front
			attack_tiles = 3
			attack_animation = "attack_dir"
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			attack_requested = true
			return
		if code == KEY_B:
			pending_d = false
			attack_direction = Vector2.LEFT  # absolute back
			attack_tiles = 3
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

	# INSERT mode: 'i' to enter from IDLE/WALK
	if code == KEY_I:
		if current_state in [State.IDLE, State.WALK]:
			change_state(State.INSERT)
		return

	# INSERT mode: Esc or Ctrl+C to exit
	if current_state == State.INSERT:
		if code == KEY_ESCAPE or (event.ctrl_pressed and code == KEY_C):
			# Return to appropriate state based on floor status
			if is_on_floor():
				change_state(State.IDLE)
			else:
				change_state(State.FALL)
			return

		# INSERT mode: Letter keys A-Z to spawn obstacles
		if code >= KEY_A and code <= KEY_Z:
			var letter = char(code)
			_create_obstacle_at_cursor(letter)
			return


func _initiate_dash(direction: Vector2, count: int, is_vertical: bool):
	# Calculate target position based on relative grid numbering
	var target = global_position

	if is_vertical:
		var current_row = round(global_position.y / dash_unit_size)
		var target_row = current_row + (count * int(direction.y))
		target.y = target_row * dash_unit_size
	else:
		var current_col = round(global_position.x / dash_unit_size)
		var target_col = current_col + (count * int(direction.x))
		target.x = target_col * dash_unit_size

	dash_target = target
	dash_direction = direction
	change_state(State.DASH)


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	if invulnerable:
		return
	if block_pressed:
		var now_ms = Time.get_ticks_msec()
		var parry = (now_ms - block_start_time_ms) <= int(parry_window_time * 1000.0)
		if parry:
			_show_damage_number(0)
			return
		amount = int(ceil(amount * 0.5))
	health = max(health - amount, 0)
	_show_damage_number(amount)
	emit_signal("health_changed", health, max_health)
	if health == 0:
		emit_signal("died")
		change_state(State.DEATH)
		return
	if block_pressed:
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
		if attack_hitbox:
			attack_hitbox.monitoring = false
		if attack_travel_tween and attack_travel_tween.is_valid():
			attack_travel_tween.kill()
			attack_travel_tween = null
	if hitbox_highlight:
		hitbox_highlight.visible = false
	change_state(State.IDLE)


func _start_attack_travel(target: Vector2, travel_time: float) -> void:
	if attack_travel_tween and attack_travel_tween.is_valid():
		attack_travel_tween.kill()
	attack_travel_tween = create_tween()
	attack_travel_tween.tween_property(self, "global_position", target, travel_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _get_animation_length(animation_name: String) -> float:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return dir_attack_travel_time
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		return dir_attack_travel_time
	var frames = animated_sprite.sprite_frames.get_frame_count(animation_name)
	var speed = animated_sprite.sprite_frames.get_animation_speed(animation_name)
	if speed <= 0:
		return dir_attack_travel_time
	return float(frames) / speed


func _get_collision_box_size() -> Vector2:
	if collision_polygon and collision_polygon.polygon.size() > 0:
		var min_x = INF
		var max_x = -INF
		var min_y = INF
		var max_y = -INF
		for p in collision_polygon.polygon:
			min_x = min(min_x, p.x)
			max_x = max(max_x, p.x)
			min_y = min(min_y, p.y)
			max_y = max(max_y, p.y)
		return Vector2(max_x - min_x, max_y - min_y)
	return Vector2(dash_unit_size, dash_unit_size)


func _update_collision_highlight() -> void:
	if not collision_highlight:
		return
	collision_highlight.position = -collision_highlight.size / 2


func _start_dash_sequence() -> void:
	await animated_sprite.animation_finished  # wait for disappear
	if current_state != State.DASH:
		return

	# Teleport to target and reappear
	global_position = dash_target
	if dash_direction.x != 0:
		animated_sprite.flip_h = dash_direction.x < 0

	animated_sprite.speed_scale = 3.0
	animated_sprite.play("reappear")
	await animated_sprite.animation_finished
	if current_state != State.DASH:
		return

	animated_sprite.speed_scale = 1.0
	if collision_polygon:
		collision_polygon.disabled = false
	invulnerable = false

	if is_on_floor():
		var direction = get_input_direction(0.0)
		if direction == Vector2.ZERO:
			change_state(State.IDLE)
		else:
			change_state(State.WALK)
	else:
		change_state(State.FALL)


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
	if body == self:
		return
	# Check if we should handle damage locally
	if multiplayer.multiplayer_peer == null:
		# Singleplayer mode - apply damage directly
		if body.has_method("apply_damage"):
			body.apply_damage(10)
	elif multiplayer.is_server():
		# Multiplayer mode - use RPC
		if body.has_method("network_apply_damage"):
			body.network_apply_damage.rpc(10)


func _show_damage_number(amount: int) -> void:
	var label = Label.new()
	label.text = str(amount)
	label.modulate = Color(1, 0.1, 0.1)
	label.z_index = 100
	add_child(label)

	var start_pos = Vector2(0, -dash_unit_size)
	label.position = start_pos

	var tween = create_tween()
	tween.tween_property(label, "position", start_pos + Vector2(0, -dash_unit_size * 0.5), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(label.queue_free)


# === INSERT MODE OBSTACLE FUNCTIONS ===

func _create_obstacle_at_cursor(letter: String) -> void:
	# Clean up any expired obstacles first
	_remove_invalid_obstacles()

	var facing_direction = -1 if animated_sprite.flip_h else 1
	var push_vector = Vector2(dash_unit_size * facing_direction, 0)

	# Push all existing blocks one tile forward in the facing direction
	for obstacle in insert_obstacles:
		if obstacle and is_instance_valid(obstacle):
			obstacle.global_position += push_vector

	# Remove the farthest block if we exceed the limit (FIFO)
	if insert_obstacles.size() >= MAX_INSERT_OBSTACLES:
		var oldest = insert_obstacles.pop_front()
		if oldest and is_instance_valid(oldest):
			oldest.queue_free()

	# Calculate spawn position - always spawn at position 1 (closest to player)
	var offset = dash_unit_size * facing_direction
	var spawn_pos = global_position + Vector2(offset, 0)

	# Grid-align the position
	spawn_pos.x = round(spawn_pos.x / dash_unit_size) * dash_unit_size
	spawn_pos.y = round(spawn_pos.y / dash_unit_size) * dash_unit_size

	# Spawn the new obstacle at position 1
	_spawn_obstacle_local(spawn_pos, letter)


func _spawn_obstacle_local(pos: Vector2, letter: String) -> void:
	# Instantiate the obstacle scene
	var obstacle = OBSTACLE_SCENE.instantiate()

	# Determine player color (blue for P1, red for P2, or default gray)
	var color = Color(0.5, 0.5, 0.5, 0.5)  # Default gray
	if multiplayer.multiplayer_peer != null:
		# Multiplayer mode - color by player ID
		if get_multiplayer_authority() == 1:
			color = Color(0.3, 0.3, 0.8, 0.5)  # Blue tint for P1
		else:
			color = Color(0.8, 0.3, 0.3, 0.5)  # Red tint for P2
	else:
		# Singleplayer mode - use blue tint
		color = Color(0.3, 0.3, 0.8, 0.5)

	# Initialize the obstacle
	obstacle.initialize(pos, letter, color)

	# Add to the stage (player's parent)
	var stage = get_parent()
	if stage:
		stage.add_child(obstacle)

	# Track the obstacle
	insert_obstacles.append(obstacle)


func _cleanup_insert_obstacles() -> void:
	# Queue free all obstacles
	for obstacle in insert_obstacles:
		if obstacle and is_instance_valid(obstacle):
			obstacle.queue_free()

	# Clear the array
	insert_obstacles.clear()


func _remove_invalid_obstacles() -> void:
	# Remove obstacles that have expired naturally (reached lifetime)
	var i = 0
	while i < insert_obstacles.size():
		if not is_instance_valid(insert_obstacles[i]):
			insert_obstacles.remove_at(i)
		else:
			i += 1
