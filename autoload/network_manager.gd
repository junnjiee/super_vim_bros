extends Node

# Signals for connection lifecycle
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed

# Constants
const DEFAULT_PORT = 7777
const MAX_PLAYERS = 2

var peer: ENetMultiplayerPeer = null

func _ready():
	# Connect to multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# Host a game on the specified port
func host_game(port: int = DEFAULT_PORT) -> int:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: " + str(error))
		return error

	multiplayer.multiplayer_peer = peer
	print("Server started on port ", port)

	# Host is also a player, emit signal for host
	player_connected.emit(1)  # Server ID is always 1
	return OK

# Join a game at the specified IP and port
func join_game(ip: String, port: int = DEFAULT_PORT) -> int:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)
	if error != OK:
		push_error("Failed to create client: " + str(error))
		return error

	multiplayer.multiplayer_peer = peer
	print("Connecting to server at ", ip, ":", port)
	return OK

# Disconnect from the current game
func disconnect_from_game() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	print("Disconnected from game")

# Called when a peer connects (server only)
func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	player_connected.emit(id)

# Called when a peer disconnects
func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	player_disconnected.emit(id)

# Called when successfully connected to server (client only)
func _on_connected_to_server() -> void:
	print("Successfully connected to server")
	connection_succeeded.emit()
	# Emit player_connected for local player
	player_connected.emit(multiplayer.get_unique_id())

# Called when connection to server fails (client only)
func _on_connection_failed() -> void:
	print("Connection to server failed")
	peer = null
	multiplayer.multiplayer_peer = null
	connection_failed.emit()
