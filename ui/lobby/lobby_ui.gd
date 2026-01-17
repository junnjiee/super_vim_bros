extends CanvasLayer

signal singleplayer_requested

@onready var ip_input: LineEdit = $Panel/VBoxContainer/IPInput
@onready var port_input: LineEdit = $Panel/VBoxContainer/PortInput
@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var singleplayer_button: Button = $Panel/VBoxContainer/SingleplayerButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

func _ready():
	# Connect button signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	singleplayer_button.pressed.connect(_on_singleplayer_button_pressed)

	# Connect to NetworkManager signals
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Set default values
	ip_input.text = "127.0.0.1"
	port_input.text = "7777"
	status_label.text = "Ready"


func _on_host_button_pressed():
	var port = int(port_input.text)
	if port <= 0:
		status_label.text = "Invalid port"
		return

	status_label.text = "Hosting game..."
	_disable_ui()

	var error = NetworkManager.host_game(port)
	if error != OK:
		status_label.text = "Failed to host: " + str(error)
		_enable_ui()
		return

	var local_ip = NetworkManager.get_local_ip()
	status_label.text = "Waiting for player...\nYour IP: " + local_ip


func _on_join_button_pressed():
	var ip = ip_input.text
	var port = int(port_input.text)

	if ip.is_empty():
		status_label.text = "Invalid IP address"
		return

	if port <= 0:
		status_label.text = "Invalid port"
		return

	status_label.text = "Connecting..."
	_disable_ui()

	var error = NetworkManager.join_game(ip, port)
	if error != OK:
		status_label.text = "Failed to connect: " + str(error)
		_enable_ui()


func _on_player_connected(peer_id: int):
	# If we're the server and a client connects, start the game
	if multiplayer.is_server() and peer_id != 1:
		status_label.text = "Starting game..."
		await get_tree().create_timer(1.0).timeout
		hide()
	# If we're the client and we just connected
	elif not multiplayer.is_server() and peer_id == multiplayer.get_unique_id():
		status_label.text = "Connected! Starting game..."
		await get_tree().create_timer(1.0).timeout
		hide()


func _on_player_disconnected(peer_id: int):
	status_label.text = "Player disconnected"
	show()
	_enable_ui()


func _on_connection_succeeded():
	status_label.text = "Connected successfully!"


func _on_connection_failed():
	status_label.text = "Connection failed"
	_enable_ui()


func _disable_ui():
	host_button.disabled = true
	join_button.disabled = true
	ip_input.editable = false
	port_input.editable = false


func _enable_ui():
	host_button.disabled = false
	join_button.disabled = false
	ip_input.editable = true
	port_input.editable = true


func _on_singleplayer_button_pressed():
	status_label.text = "Starting singleplayer..."
	singleplayer_requested.emit()
	hide()
