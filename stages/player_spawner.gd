extends Node

@export var player_scene: PackedScene
@export var spawn_point_1: NodePath  # Left side (host)
@export var spawn_point_2: NodePath  # Right side (client)

var spawn_1: Marker2D
var spawn_2: Marker2D

func _ready():
	# Resolve NodePaths to actual nodes
	if spawn_point_1:
		spawn_1 = get_node(spawn_point_1)
	if spawn_point_2:
		spawn_2 = get_node(spawn_point_2)

	if not multiplayer.is_server():
		return

	# Connect to network manager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

func _on_player_connected(peer_id: int):
	print("Spawning player for peer: %d" % peer_id)

	# Check if spawn points are valid
	if not spawn_1 or not spawn_2:
		push_error("Spawn points not set! Cannot spawn player.")
		return

	# Determine spawn position based on peer ID
	# Peer ID 1 is always the server/host
	var spawn_position: Vector2
	if peer_id == 1:
		spawn_position = spawn_1.global_position
	else:
		spawn_position = spawn_2.global_position

	# Instantiate player
	var player = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.global_position = spawn_position

	# Set multiplayer authority
	player.set_multiplayer_authority(peer_id)

	# Add to scene
	get_parent().add_child(player, true)

	print("Player spawned at position: %s with authority: %d" % [spawn_position, peer_id])

func _on_player_disconnected(peer_id: int):
	print("Removing player for peer: %d" % peer_id)

	# Find and remove the player node
	var player_name = "Player_%d" % peer_id
	var player = get_parent().get_node_or_null(player_name)

	if player:
		player.queue_free()
		print("Player removed: %s" % player_name)
