extends CharacterBody2D

# Define all possible states
enum State {
	IDLE,
	WALK,
	ATTACK,
	HITSTUN,
}

@export var speed: float = 200.0
@export var jump_force := 350.0
@export var max_health: int = 100
@export var invuln_time := 0.4
@export var attack_time := 0.2
@export var input_buffer_time := 0.25

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var current_state: State = State.IDLE
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimatedSprite2D/AnimationPlayer
var health: int = max_health
var invulnerable := false
var pending_d := false
var pending_d_timer := 0.0
var attack_direction := Vector2.ZERO
var attack_requested := false
var attack_animation := "attack_dir"
var neutral_combo_step := 0
var neutral_combo_timer := 0.0

signal health_changed(current: int, max: int)
signal died


func _ready():
	# Enter the initial state
	health = max_health
	emit_signal("health_changed", health, max_health)
	if animation_player:
		animation_player.stop()
	enter_state(current_state)


func _physics_process(delta):
	if neutral_combo_timer > 0.0:
		neutral_combo_timer -= delta
		if neutral_combo_timer <= 0.0:
			neutral_combo_step = 0

	if pending_d:
		pending_d_timer -= delta
		if pending_d_timer <= 0.0:
			pending_d = false

	# Apply vertical physics every frame
	if not is_on_floor():
		velocity.y += gravity * delta
	if is_on_floor() and Input.is_key_pressed(KEY_K):
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
		State.WALK:
			animated_sprite.play("walk")	
		State.ATTACK:
			animated_sprite.play(attack_animation)
			_start_attack_recovery()
		State.HITSTUN:
			animated_sprite.play("hit")
			invulnerable = true
			neutral_combo_step = 0
			neutral_combo_timer = 0.0
			_start_hitstun_recovery()


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


# === STATE LOGIC ===

func state_idle(_delta):
	# Check for movement input
	var direction = get_input_direction(_delta)
	velocity.x = 0.0

	if attack_requested:
		attack_requested = false
		change_state(State.ATTACK)
		return

	if direction != Vector2.ZERO:
		change_state(State.WALK)


func state_walk(_delta):
	var direction = get_input_direction(_delta)

	if attack_requested:
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


func state_attack(_delta):
	# Lock movement while attacking
	velocity.x = 0.0
	if attack_direction.x != 0:
		animated_sprite.flip_h = attack_direction.x < 0


func state_hitstun(_delta):
	# Lock movement while invulnerable from a hit
	velocity.x = 0.0


# === HELPER FUNCTIONS ===

func get_input_direction(delta) -> Vector2:
	var direction = Vector2.ZERO
	if Input.is_key_pressed(KEY_H):
		direction.x -= 1
	if Input.is_key_pressed(KEY_L):
		direction.x += 1

	return direction


func _input(event) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	if current_state == State.ATTACK or current_state == State.HITSTUN:
		return

	var code = event.keycode

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


func apply_damage(amount: int) -> void:
	if amount <= 0:
		return
	if invulnerable:
		return
	health = max(health - amount, 0)
	emit_signal("health_changed", health, max_health)
	if health == 0:
		emit_signal("died")
		return
	change_state(State.HITSTUN)


func _start_hitstun_recovery() -> void:
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false
	change_state(State.IDLE)


func _start_attack_recovery() -> void:
	await get_tree().create_timer(attack_time).timeout
	change_state(State.IDLE)

		
