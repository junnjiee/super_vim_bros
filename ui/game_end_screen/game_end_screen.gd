extends CanvasLayer

signal play_again_requested

@onready var panel: Panel = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel
@onready var play_again_button: Button = $Panel/VBoxContainer/PlayAgainButton

# Track which players have voted to play again
var play_again_votes: Dictionary = {}
var local_player_won: bool = false
var game_ended: bool = false
var winner_peer_id: int = -1
var loser_peer_id: int = -1


func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again_pressed)
	hide()


func show_winner(local_won: bool, winner_id: int, loser_id: int) -> void:
	game_ended = true
	local_player_won = local_won
	winner_peer_id = winner_id
	loser_peer_id = loser_id
	play_again_votes.clear()

	if local_won:
		title_label.text = "YOU WIN!"
		title_label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
	else:
		title_label.text = "YOU DIED"
		title_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))

	status_label.text = "Press Play Again to rematch"
	play_again_button.disabled = false
	show()


func hide_screen() -> void:
	game_ended = false
	play_again_votes.clear()
	hide()


func _on_play_again_pressed() -> void:
	play_again_button.disabled = true

	# Get local peer ID
	var local_peer_id = 1
	if multiplayer.multiplayer_peer != null:
		local_peer_id = multiplayer.get_unique_id()

	# Register local vote
	_register_vote(local_peer_id)

	# In multiplayer, broadcast the vote
	if multiplayer.multiplayer_peer != null:
		if multiplayer.is_server():
			_broadcast_vote.rpc(local_peer_id)
		else:
			_request_vote.rpc_id(1, local_peer_id)


func _register_vote(peer_id: int) -> void:
	play_again_votes[peer_id] = true
	_update_status()
	_check_all_voted()


func _update_status() -> void:
	var vote_count = play_again_votes.size()
	if multiplayer.multiplayer_peer == null:
		# Singleplayer - just one vote needed
		status_label.text = "Starting..."
	else:
		# Multiplayer - need both players
		if vote_count == 1:
			status_label.text = "Waiting for other player... (1/2)"
		else:
			status_label.text = "Starting..."


func _check_all_voted() -> void:
	var required_votes = 1
	if multiplayer.multiplayer_peer != null:
		required_votes = 2

	if play_again_votes.size() >= required_votes:
		# All players voted, trigger respawn
		await get_tree().create_timer(0.5).timeout
		play_again_requested.emit()
		hide_screen()


# RPC: Client requests to register their vote
@rpc("any_peer", "reliable")
func _request_vote(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Verify sender
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != 0 and sender_id != peer_id:
		return

	# Broadcast vote to all clients
	_broadcast_vote.rpc(peer_id)


# RPC: Server broadcasts a vote to all clients
@rpc("authority", "call_local", "reliable")
func _broadcast_vote(peer_id: int) -> void:
	_register_vote(peer_id)
