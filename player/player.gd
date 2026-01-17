extends CharacterBody2D


@export var speed := 200.0

func _physics_process(delta):
	var direction := Vector2.ZERO

	# Vim movement keys
	if Input.is_key_pressed(KEY_H):
		direction.x -= 1
	if Input.is_key_pressed(KEY_L):
		direction.x += 1
	if Input.is_key_pressed(KEY_K):
		direction.y -= 1
	if Input.is_key_pressed(KEY_J):
		direction.y += 1

	print(global_position, velocity)
	
	direction = direction.normalized()
	velocity = direction * speed
	move_and_slide()
