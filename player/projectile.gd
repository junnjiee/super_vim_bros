extends Area2D

const SPEED = 600.0
const MAX_RANGE = 800.0
const KNOCKBACK = 280.0

var direction: Vector2 = Vector2.RIGHT
var owner_player: Node2D = null
var distance_traveled: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func initialize(dir: Vector2, owner: Node2D) -> void:
	direction = dir
	owner_player = owner

func _physics_process(delta: float) -> void:
	var movement = direction * SPEED * delta
	position += movement
	distance_traveled += movement.length()

	# Destroy if max range reached
	if distance_traveled >= MAX_RANGE:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Deal damage if it's a player and not the owner
	if body.has_method("apply_damage") and body != owner_player:
		if multiplayer.multiplayer_peer == null or is_multiplayer_authority():
			_apply_damage_to_target(body, 3, direction.normalized() * KNOCKBACK)

	# Destroy projectile on any collision
	queue_free()


func _apply_damage_to_target(body: Node2D, amount: int, knockback: Vector2 = Vector2.ZERO) -> void:
	if not body.has_method("apply_damage"):
		return
	if multiplayer.multiplayer_peer == null:
		body.apply_damage(amount, knockback)
		return
	var target_id = body.get_multiplayer_authority()
	if target_id == multiplayer.get_unique_id():
		body.apply_damage(amount, knockback)
		return
	if body.has_method("network_apply_damage"):
		body.network_apply_damage.rpc_id(target_id, amount, knockback)
