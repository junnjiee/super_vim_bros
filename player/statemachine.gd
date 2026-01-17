extends CharacterBody2D

# Define all possible states
enum State {
	IDLE,
	WALK,
	# Add more later: JUMP, ATTACK, HITSTUN, etc.
}

@export var speed: float = 200.0
@export var jump_force := 350.0
@export var max_health: int = 100
@export var invuln_time := 0.4

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var current_state: State = State.IDLE
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
var health: int = max_health
var invulnerable := false

signal health_changed(current: int, max: int)
signal died


func _ready():
	# Enter the initial state
	health = max_health
	emit_signal("health_changed", health, max_health)
	enter_state(current_state)


func _physics_process(delta):
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


func exit_state(state: State):
	# Clean up when leaving a state (optional)
	match state:
		State.IDLE:
			pass  # Nothing to clean up
		State.WALK:
			pass


# === STATE LOGIC ===

func state_idle(_delta):
	# Check for movement input
	var direction = get_input_direction(_delta)
	velocity.x = 0.0

	if direction != Vector2.ZERO:
		change_state(State.WALK)


func state_walk(_delta):
	var direction = get_input_direction(_delta)
	
	# No input? Go back to idle
	if direction == Vector2.ZERO:
		velocity.x = 0.0
		if is_on_floor():
			change_state(State.IDLE)
		return

	# Move the player
	velocity.x = direction.x * speed

	# Flip sprite based on direction
	if direction.x != 0:
		animated_sprite.flip_h = direction.x < 0


# === HELPER FUNCTIONS ===

func get_input_direction(delta) -> Vector2:
	var direction = Vector2.ZERO
	if Input.is_key_pressed(KEY_H):
		direction.x -= 1
	if Input.is_key_pressed(KEY_L):
		direction.x += 1

	return direction


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
	invulnerable = true
	await get_tree().create_timer(invuln_time).timeout
	invulnerable = false

		
