extends Node2D

@onready var player_spawner: Node = $PlayerSpawner
@onready var hud: CanvasLayer = $HUD
@onready var game_end_screen: CanvasLayer = $GameEndScreen


func _ready() -> void:
	# Connect HUD's game_over signal to show the end screen
	hud.game_over.connect(_on_game_over)

	# Connect GameEndScreen's play_again signal to respawn players
	game_end_screen.play_again_requested.connect(_on_play_again_requested)


func _on_game_over(winner_peer_id: int, loser_peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null:
		# Single player - just show directly
		_show_game_over_screen(winner_peer_id, loser_peer_id)
	elif multiplayer.is_server():
		# Server broadcasts to all (including itself)
		_broadcast_game_over.rpc(winner_peer_id, loser_peer_id)
	else:
		# Client notifies server to broadcast
		_request_game_over.rpc_id(1, winner_peer_id, loser_peer_id)


@rpc("any_peer", "reliable")
func _request_game_over(winner_peer_id: int, loser_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Server received request from client, broadcast to all
	_broadcast_game_over.rpc(winner_peer_id, loser_peer_id)


@rpc("authority", "call_local", "reliable")
func _broadcast_game_over(winner_peer_id: int, loser_peer_id: int) -> void:
	_show_game_over_screen(winner_peer_id, loser_peer_id)


func _show_game_over_screen(winner_peer_id: int, loser_peer_id: int) -> void:
	# Determine if the local player won
	var local_peer_id = 1
	if multiplayer.multiplayer_peer != null:
		local_peer_id = multiplayer.get_unique_id()

	var local_won = (local_peer_id == winner_peer_id)
	game_end_screen.show_winner(local_won, winner_peer_id, loser_peer_id)


func _on_play_again_requested() -> void:
	# Reset HUD and respawn players
	hud.reset_hud()
	player_spawner.respawn_all_players()
