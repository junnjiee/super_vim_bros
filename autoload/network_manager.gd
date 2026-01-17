extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed

const DEFAULT_PORT = 7777
const MAX_PLAYERS = 2

var peer: ENetMultiplayerPeer = null

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

func host_game(port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)

	if error != OK:
		push_error("Failed to host game on port %d: %s" % [port, error_string(error)])
		return error

	multiplayer.multiplayer_peer = peer
	print("Hosting game on port %d" % port)
	player_connected.emit(1)  # Emit for host (peer_id 1)
	return OK

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, port)

	if error != OK:
		push_error("Failed to connect to %s:%d: %s" % [ip, port, error_string(error)])
		return error

	multiplayer.multiplayer_peer = peer
	print("Attempting to connect to %s:%d" % [ip, port])
	return OK

func disconnect_game() -> void:
	if peer:
		peer.close()
		peer = null

	multiplayer.multiplayer_peer = null
	print("Disconnected from game")

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	print("Successfully connected to server")
	connection_succeeded.emit()
	var my_peer_id = multiplayer.get_unique_id()
	player_connected.emit(my_peer_id)

func _on_connection_failed() -> void:
	print("Connection to server failed")
	connection_failed.emit()
	disconnect_game()
