extends Node

# Exports for player scene and spawn points
@export var player_scene: PackedScene
@export var spawn_point_1: NodePath  # Left spawn (host)
@export var spawn_point_2: NodePath  # Right spawn (client)

# Track spawned players
var spawned_players = {}

func _ready():
	add_to_group("player_spawner")
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
	# If player already exists, remove the old one first to ensure fresh spawn
	if spawned_players.has(peer_id):
		var old_player = spawned_players[peer_id]
		if is_instance_valid(old_player):
			old_player.queue_free()
		spawned_players.erase(peer_id)

	if not player_scene:
		push_error("Player scene not set in PlayerSpawner")
		return

	var player = player_scene.instantiate()
	player.name = "Player_%s" % peer_id
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


@rpc("any_peer", "reliable")
func request_despawn(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		_despawn_player(peer_id)
		return
	if not multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		return
	_despawn_player.rpc(peer_id)


func spawn_local_player() -> void:
	if not player_scene:
		push_error("Player scene not set")
		return

	var spawn_point = get_node(spawn_point_1) as Node2D
	if not spawn_point:
		push_error("Spawn point not found")
		return

	var player = player_scene.instantiate()
	player.name = "Player_Local"
	player.global_position = spawn_point.global_position
	# Authority defaults to 1 when no peer exists
	get_parent().add_child(player)
	spawned_players[1] = player
	print("Local player spawned at ", spawn_point.global_position)


# Clear all spawned players (used before respawning)
func clear_all_players() -> void:
	for peer_id in spawned_players.keys():
		var player = spawned_players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
	spawned_players.clear()

	# Also clear any players in the group that might not be tracked
	# (e.g., if despawn timing caused dictionary inconsistency)
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player):
			player.queue_free()

	print("All players cleared")


# Respawn all players - called when both players agree to play again
func respawn_all_players() -> void:
	if multiplayer.multiplayer_peer == null:
		# Singleplayer mode
		clear_all_players()
		# Wait a frame for cleanup
		await get_tree().process_frame
		spawn_local_player()
		return

	# Multiplayer mode - only server handles this
	if not multiplayer.is_server():
		return

	# First, clear all players on all clients
	_clear_all_players_rpc.rpc()

	# Wait a frame for cleanup to complete
	await get_tree().process_frame

	# Respawn server player (peer ID 1)
	var spawn_point_1_node = get_node(spawn_point_1) as Node2D
	if spawn_point_1_node:
		_spawn_player.rpc(1, spawn_point_1_node.global_position)

	# Respawn client players
	for peer_id in multiplayer.get_peers():
		if peer_id != 1:
			var spawn_point_2_node = get_node(spawn_point_2) as Node2D
			if spawn_point_2_node:
				_spawn_player.rpc(peer_id, spawn_point_2_node.global_position)


@rpc("authority", "call_local", "reliable")
func _clear_all_players_rpc() -> void:
	clear_all_players()
