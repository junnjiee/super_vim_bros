extends Area2D

@export var lethal_damage := 9999


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.has_method("apply_damage"):
		body.apply_damage(lethal_damage)
	elif body.has_method("queue_free"):
		body.queue_free()
	call_deferred("_maybe_reset_scene")


func _maybe_reset_scene() -> void:
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Node and p.is_visible_in_tree():
			return
	get_tree().reload_current_scene()
