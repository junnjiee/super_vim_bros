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

	# Instantiate the player
	var player = player_scene.instantiate()

	# Determine spawn point based on peer ID
	# Server (ID 1) spawns at left, client spawns at right
	var spawn_point: Node2D
	if peer_id == 1:
		spawn_point = get_node(spawn_point_1)
	else:
		spawn_point = get_node(spawn_point_2)

	if not spawn_point:
		push_error("Spawn point not found")
		player.queue_free()
		return

	# Set player position
	player.global_position = spawn_point.global_position

	# Set multiplayer authority to the peer
	player.set_multiplayer_authority(peer_id)

	# Add to scene
	get_parent().add_child(player)

	# Track the spawned player
	spawned_players[peer_id] = player

	print("Player spawned for peer ", peer_id, " at ", spawn_point.global_position)


func _on_player_disconnected(peer_id: int):
	# Remove the player when they disconnect
	if spawned_players.has(peer_id):
		var player = spawned_players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		spawned_players.erase(peer_id)
		print("Player removed for peer ", peer_id)
