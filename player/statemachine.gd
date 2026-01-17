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
@export var count_timeout := 5.0
@export var d_command_timeout := 4.0
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
@onready var neutral_attack_sfx: AudioStreamPlayer = $NeutralAttackSfx
var _health: int = 0
var _last_health_reported: int = -1
var _last_max_health_reported: int = -1
var health: int:
	set(value):
		if value == _health:
			return
		_health = value
		_emit_health_changed_if_needed()
	get:
		return _health
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

# Ranged attack cooldown
var ranged_cooldown_timer: float = 0.0
@export var ranged_cooldown: float = 0.75

# Dash tracking
var dash_target: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.ZERO
var attack_travel_tween: Tween = null

# INSERT mode tracking
var in_insert_mode := false
var insert_obstacles: Array = []
const MAX_INSERT_OBSTACLES = 8
const OBSTACLE_SCENE = preload("res://player/insert_obstacle.tscn")
const PROJECTILE_SCENE = preload("res://player/projectile.tscn")

signal health_changed(current: int, max: int)
signal died


func _ready():
	# Add player to group for easy lookup
	add_to_group("player")
	# Enter the initial state
	health = max_health
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
	_emit_health_changed_if_needed()
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

	# Ranged attack cooldown
	if ranged_cooldown_timer > 0.0:
		ranged_cooldown_timer -= delta

	var on_floor = is_on_floor()

	# Apply vertical physics every frame (skip during teleport dash and death)
	if not on_floor and current_state not in [State.DASH, State.DEATH]:
		velocity.y += gravity * delta
	if input_enabled and on_floor and current_state not in [State.ATTACK, State.HITSTUN, State.DEATH, State.DASH, State.INSERT] and Input.is_key_pressed(KEY_K):
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
			if attack_animation.begins_with("neutral_") or attack_animation == "attack_jump":
				_play_neutral_attack_sfx()
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
			# Kill attack travel tween when exiting ATTACK to prevent position conflicts
			if attack_travel_tween and attack_travel_tween.is_valid():
				attack_travel_tween.kill()
				attack_travel_tween = null
		State.BLOCK:
			pass
		State.HITSTUN:
			pass
		State.DEATH:
			pass
		State.DASH:
			# Re-enable collision if interrupted mid-dash
			if collision_polygon:
				collision_polygon.disabled = false
			invulnerable = false
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


func _play_neutral_attack_sfx() -> void:
	if neutral_attack_sfx:
		neutral_attack_sfx.stop()
		neutral_attack_sfx.play()


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

	# INSERT mode: Handle separately to prevent other actions
	if current_state == State.INSERT:
		# Esc or Ctrl+C to exit INSERT mode
		if code == KEY_ESCAPE or (event.ctrl_pressed and code == KEY_C):
			if is_on_floor():
				change_state(State.IDLE)
			else:
				change_state(State.FALL)
			return

		# Letter keys A-Z to spawn obstacles
		if code >= KEY_A and code <= KEY_Z:
			var letter = char(code)
			_create_obstacle_at_cursor(letter)
			return

		# Number keys 0-9 to spawn obstacles
		if code >= KEY_0 and code <= KEY_9:
			var letter = char(code)
			_create_obstacle_at_cursor(letter)
			return

		# Ignore all other keys in INSERT mode
		return

	# Check for ranged attacks first (d0 and d$) before standalone 0 and $
	if pending_d and pending_d_timer > 0.0:
		# Ranged attack: d0 (fire left)
		if code == KEY_0:
			pending_d = false
			if ranged_cooldown_timer <= 0.0:
				_fire_projectile(Vector2.LEFT)
				ranged_cooldown_timer = ranged_cooldown
			return

		# Ranged attack: d$ (fire right)
		if code == KEY_4 and event.shift_pressed:
			pending_d = false
			if ranged_cooldown_timer <= 0.0:
				_fire_projectile(Vector2.RIGHT)
				ranged_cooldown_timer = ranged_cooldown
			return

	# Number key detection for count buffering
	# Vim '0' command: dash to start of platform (x=300) - only if not pending_d
	if code == KEY_0 and pending_count == "":
		_initiate_absolute_dash(300.0)
		return

	# Vim '$' command (Shift+4): dash to end of platform (x=1550) - only if not pending_d
	if code == KEY_4 and event.shift_pressed:
		_initiate_absolute_dash(1550.0)
		return

	# Number key detection for count buffering (1-9, or 0 after another digit)
	if code >= KEY_0 and code <= KEY_9:
		# Only accumulate if we haven't reached 2 digits
		if pending_count.length() < 2:
			var digit = code - KEY_0
			pending_count += str(digit)
			pending_count_timer = count_timeout
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
		pending_d_timer = d_command_timeout
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


func _initiate_absolute_dash(target_x: float):
	# Dash to an absolute x position (for 0 and $ commands)
	var target = global_position
	target.x = target_x

	dash_target = target
	dash_direction = Vector2.LEFT if target_x < global_position.x else Vector2.RIGHT
	change_state(State.DASH)


func _fire_projectile(direction: Vector2) -> void:
	if multiplayer.multiplayer_peer == null:
		_spawn_projectile_local(direction, _get_projectile_spawn_pos(direction))
		return
	if multiplayer.is_server():
		_broadcast_projectile_spawn(direction)
	else:
		_request_projectile_spawn.rpc_id(1, direction)


@rpc("any_peer", "reliable")
func _request_projectile_spawn(direction: Vector2) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_broadcast_projectile_spawn(direction)


func _broadcast_projectile_spawn(direction: Vector2) -> void:
	var spawn_pos = _get_projectile_spawn_pos(direction)
	_spawn_projectile.rpc(direction, spawn_pos)


@rpc("any_peer", "call_local", "reliable")
func _spawn_projectile(direction: Vector2, spawn_pos: Vector2) -> void:
	if not _is_server_rpc_sender():
		return
	_spawn_projectile_local(direction, spawn_pos)


func _spawn_projectile_local(direction: Vector2, spawn_pos: Vector2) -> void:
	var projectile = PROJECTILE_SCENE.instantiate()
	if multiplayer.multiplayer_peer != null:
		projectile.set_multiplayer_authority(get_multiplayer_authority(), true)
	projectile.initialize(direction, self)
	projectile.global_position = spawn_pos
	get_parent().add_child(projectile)


func _get_projectile_spawn_pos(direction: Vector2) -> Vector2:
	return global_position + direction * dash_unit_size


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
	if health == 0:
		emit_signal("died")
		change_state(State.DEATH)
		return
	if block_pressed:
		return
	change_state(State.HITSTUN)


@rpc("any_peer", "reliable")
func network_apply_damage(amount: int):
	apply_damage(amount)


func _start_hitstun_recovery() -> void:
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false
	change_state(State.IDLE)


func _start_attack_recovery() -> void:
	var finished = await animated_sprite.animation_finished
	if current_state != State.ATTACK:
		# State changed during attack (e.g., player initiated a dash), don't interfere
		return
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
	if not _is_local_authority():
		return
	_apply_damage_to_target(body, 10)


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


func _emit_health_changed_if_needed() -> void:
	if _health == _last_health_reported and max_health == _last_max_health_reported:
		return
	_last_health_reported = _health
	_last_max_health_reported = max_health
	emit_signal("health_changed", _health, max_health)


func _apply_damage_to_target(body: Node, amount: int) -> void:
	if not body.has_method("apply_damage"):
		return
	if multiplayer.multiplayer_peer == null:
		body.apply_damage(amount)
		return
	var target_id = body.get_multiplayer_authority()
	if target_id == multiplayer.get_unique_id():
		body.apply_damage(amount)
		return
	if body.has_method("network_apply_damage"):
		body.network_apply_damage.rpc_id(target_id, amount)


# === INSERT MODE OBSTACLE FUNCTIONS ===

func _create_obstacle_at_cursor(letter: String) -> void:
	if multiplayer.multiplayer_peer == null:
		_create_obstacle_at_cursor_local(letter)
		return
	if multiplayer.is_server():
		_broadcast_obstacle_spawn(letter)
	else:
		_request_obstacle_spawn.rpc_id(1, letter)


@rpc("any_peer", "reliable")
func _request_obstacle_spawn(letter: String) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != get_multiplayer_authority():
		return
	_broadcast_obstacle_spawn(letter)


func _broadcast_obstacle_spawn(letter: String) -> void:
	_spawn_obstacle.rpc(letter)


@rpc("any_peer", "call_local", "reliable")
func _spawn_obstacle(letter: String) -> void:
	if not _is_server_rpc_sender():
		return
	_create_obstacle_at_cursor_local(letter)


func _create_obstacle_at_cursor_local(letter: String) -> void:
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


func _is_server_rpc_sender() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		return multiplayer.is_server()
	return sender_id == 1
