extends Node

# Exports for player scene and spawn points
@export var player_scene: PackedScene
@export var spawn_point_1: NodePath  # Left spawn (host)
@export var spawn_point_2: NodePath  # Right spawn (client)

# Track spawned players
var spawned_players = {}

func _ready():
	# Only server spawns players
	if not multiplayer.is_server():
		return

	# Connect to NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)


func _on_player_connected(peer_id: int):
	# Only server handles spawning
	if not multiplayer.is_server():
		return

	if not player_scene:
		push_error("Player scene not set in PlayerSpawner")
		return

	# Determine spawn point based on peer ID
	# Server (ID 1) spawns at left, client spawns at right
	var spawn_point: Node2D
	if peer_id == 1:
		spawn_point = get_node(spawn_point_1) as Node2D
	else:
		spawn_point = get_node(spawn_point_2) as Node2D

	if not spawn_point:
		push_error("Spawn point not found")
		return

	var existing_player_ids = spawned_players.keys()
	_spawn_player.rpc(peer_id, spawn_point.global_position)
	# Ensure late-joining peers receive already-spawned players (e.g. host).
	for existing_peer_id in existing_player_ids:
		var existing_player = spawned_players[existing_peer_id]
		if not is_instance_valid(existing_player):
			continue
		_spawn_player.rpc_id(peer_id, existing_peer_id, existing_player.global_position)


func _on_player_disconnected(peer_id: int):
	# Only server handles despawning
	if not multiplayer.is_server():
		return

	_despawn_player.rpc(peer_id)


@rpc("authority", "call_local", "reliable")
func _spawn_player(peer_id: int, spawn_position: Vector2) -> void:
	if spawned_players.has(peer_id):
		return

	if not player_scene:
		push_error("Player scene not set in PlayerSpawner")
		return

	var player = player_scene.instantiate()
	player.global_position = spawn_position
	player.set_multiplayer_authority(peer_id, true)
	get_parent().add_child(player)
	spawned_players[peer_id] = player
	print("Player spawned for peer ", peer_id, " at ", spawn_position)


@rpc("authority", "call_local", "reliable")
func _despawn_player(peer_id: int) -> void:
	if not spawned_players.has(peer_id):
		return

	var player = spawned_players[peer_id]
	if is_instance_valid(player):
		player.queue_free()
	spawned_players.erase(peer_id)
	print("Player removed for peer ", peer_id)
