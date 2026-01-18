extends CanvasLayer

signal game_over(winner_peer_id: int, loser_peer_id: int)

@onready var player1_health: ProgressBar = $MarginContainer/HBoxContainer/Player1Container/HealthBar
@onready var player1_label: Label = $MarginContainer/HBoxContainer/Player1Container/NameLabel
@onready var player1_health_text: Label = $MarginContainer/HBoxContainer/Player1Container/HealthText

@onready var player2_health: ProgressBar = $MarginContainer/HBoxContainer/Player2Container/HealthBar
@onready var player2_label: Label = $MarginContainer/HBoxContainer/Player2Container/NameLabel
@onready var player2_health_text: Label = $MarginContainer/HBoxContainer/Player2Container/HealthText

var player1: CharacterBody2D = null
var player2: CharacterBody2D = null
var player1_peer_id: int = -1
var player2_peer_id: int = -1

func _ready() -> void:
	# Wait a frame for players to be spawned
	await get_tree().process_frame
	_find_and_connect_players()

	# Listen for new players joining
	get_tree().node_added.connect(_on_node_added)

func _find_and_connect_players() -> void:
	var players = get_tree().get_nodes_in_group("player")

	for player in players:
		if player1 == null:
			player1 = player
			_connect_player(player, 1)
		elif player2 == null:
			player2 = player
			_connect_player(player, 2)
		else:
			break

func _on_node_added(node: Node) -> void:
	# Defer the check because node_added fires before _ready(),
	# and the player joins the "player" group in _ready()
	_try_connect_player.call_deferred(node)


func _try_connect_player(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node.is_in_group("player"):
		return
	# Avoid double-connecting
	if node == player1 or node == player2:
		return
	if player1 == null:
		player1 = node
		_connect_player(node, 1)
	elif player2 == null:
		player2 = node
		_connect_player(node, 2)

func _connect_player(player: CharacterBody2D, player_num: int) -> void:
	# Track peer ID for this player
	var peer_id = player.get_multiplayer_authority()
	if player_num == 1:
		player1_peer_id = peer_id
	else:
		player2_peer_id = peer_id

	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed.bind(player_num))

		# Initialize health bar
		var max_health = player.get("max_health")
		var current_health = player.get("health")
		if max_health != null and current_health != null:
			_on_health_changed(current_health, max_health, player_num)

	if player.has_signal("died"):
		player.died.connect(_on_player_died.bind(player_num))
	_apply_player_color(player, player_num)


func _apply_player_color(player: CharacterBody2D, player_num: int) -> void:
	var color = _get_player_title_color(player_num)
	if player.has_method("set_player_color"):
		player.set_player_color(color)


func _get_player_title_color(player_num: int) -> Color:
	if player_num == 1:
		return player1_label.get_theme_color("font_color")
	return player2_label.get_theme_color("font_color")

func _on_health_changed(current: int, max: int, player_num: int) -> void:
	if player_num == 1:
		player1_health.max_value = max
		player1_health.value = current
		player1_health_text.text = "%d/%d" % [current, max]
	elif player_num == 2:
		player2_health.max_value = max
		player2_health.value = current
		player2_health_text.text = "%d/%d" % [current, max]

func _on_player_died(player_num: int) -> void:
	if player_num == 1:
		player1_health_text.text = "DEAD"
		# Player 1 died, Player 2 wins
		game_over.emit(player2_peer_id, player1_peer_id)
	elif player_num == 2:
		player2_health_text.text = "DEAD"
		# Player 2 died, Player 1 wins
		game_over.emit(player1_peer_id, player2_peer_id)


func reset_hud() -> void:
	# Reset HUD state for a new round
	player1 = null
	player2 = null
	player1_peer_id = -1
	player2_peer_id = -1
	player1_health_text.text = "100/100"
	player2_health_text.text = "100/100"
	player1_health.value = 100
	player2_health.value = 100
	# Re-find players after respawn
	await get_tree().process_frame
	_find_and_connect_players()
