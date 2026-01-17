extends CharacterBody2D


@export var speed := 200.0
@export var jump_force := 350.0

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _physics_process(delta):
	
	var direction = 0
	# Vim movement keys
	if Input.is_key_pressed(KEY_H):
		direction -= 1
	if Input.is_key_pressed(KEY_L):
		direction += 1 
	
	velocity.x = direction * speed
	
	if not is_on_floor():
		velocity.y += gravity * delta
		
	if is_on_floor() and Input.is_key_pressed(KEY_K):
		velocity.y = -jump_force

	print(global_position, velocity)
	
		# --- Animation ---
	if direction != 0:
		$AnimatedSprite2D.play("walk")
	else:
		$AnimatedSprite2D.play("idle")

	# --- Flip sprite ---
	if direction < 0:
		$AnimatedSprite2D.flip_h = direction > 0 

	move_and_slide()
