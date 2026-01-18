extends CanvasLayer

@onready var player1_health: ProgressBar = $MarginContainer/HBoxContainer/Player1Container/HealthBar
@onready var player1_label: Label = $MarginContainer/HBoxContainer/Player1Container/NameLabel
@onready var player1_health_text: Label = $MarginContainer/HBoxContainer/Player1Container/HealthText

@onready var player2_health: ProgressBar = $MarginContainer/HBoxContainer/Player2Container/HealthBar
@onready var player2_label: Label = $MarginContainer/HBoxContainer/Player2Container/NameLabel
@onready var player2_health_text: Label = $MarginContainer/HBoxContainer/Player2Container/HealthText
@onready var win_screen: Control = $WinScreen
@onready var win_label: Label = $WinScreen/Panel/VBoxContainer/WinLabel
@onready var restart_button: Button = $WinScreen/Panel/VBoxContainer/RestartButton

var player1: CharacterBody2D = null
var player2: CharacterBody2D = null
var game_over := false

func _ready() -> void:
	# Wait a frame for players to be spawned
	await get_tree().process_frame
	_find_and_connect_players()

	# Listen for new players joining
	get_tree().node_added.connect(_on_node_added)
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if win_screen:
		win_screen.visible = false

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
	elif player_num == 2:
		player2_health_text.text = "DEAD"
	if multiplayer.multiplayer_peer == null:
		return
	if game_over:
		return
	if player1 == null or player2 == null:
		return
	var winner_num = 2 if player_num == 1 else 1
	_show_win_screen(winner_num)


func _show_win_screen(winner_num: int) -> void:
	game_over = true
	if win_label:
		win_label.text = "Player %d Wins" % winner_num
		var color = _get_player_title_color(winner_num)
		win_label.modulate = color
	if win_screen:
		win_screen.visible = true


func _on_restart_pressed() -> void:
	if multiplayer.multiplayer_peer == null:
		_restart_game()
		return
	if multiplayer.is_server():
		_broadcast_restart()
	else:
		_request_restart.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_restart() -> void:
	if not multiplayer.is_server():
		return
	_broadcast_restart()


func _broadcast_restart() -> void:
	_restart_game.rpc()


@rpc("authority", "call_local", "reliable")
func _restart_game() -> void:
	game_over = false
	if win_screen:
		win_screen.visible = false
	get_tree().reload_current_scene()
