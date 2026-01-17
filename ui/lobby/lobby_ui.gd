extends CanvasLayer

@onready var ip_input: LineEdit = $Panel/VBoxContainer/IPInput
@onready var port_input: LineEdit = $Panel/VBoxContainer/PortInput
@onready var host_button: Button = $Panel/VBoxContainer/HostButton
@onready var join_button: Button = $Panel/VBoxContainer/JoinButton
@onready var status_label: Label = $Panel/VBoxContainer/StatusLabel

func _ready():
	# Set default values
	ip_input.text = "127.0.0.1"
	port_input.text = "7777"
	status_label.text = "Ready"

	# Connect buttons
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Connect to network manager signals
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.player_connected.connect(_on_player_connected)

func _on_host_pressed():
	var port = int(port_input.text)
	status_label.text = "Hosting on port %d..." % port

	var error = NetworkManager.host_game(port)
	if error != OK:
		status_label.text = "Failed to host: Error %d" % error
		return

	status_label.text = "Hosting on port %d. Waiting for player..." % port
	_disable_ui()

func _on_join_pressed():
	var ip = ip_input.text
	var port = int(port_input.text)
	status_label.text = "Connecting to %s:%d..." % [ip, port]

	var error = NetworkManager.join_game(ip, port)
	if error != OK:
		status_label.text = "Failed to connect: Error %d" % error
		return

	_disable_ui()

func _on_connection_succeeded():
	status_label.text = "Connected! Starting game..."
	await get_tree().create_timer(1.0).timeout
	hide()

func _on_connection_failed():
	status_label.text = "Connection failed"
	_enable_ui()

func _on_player_connected(peer_id: int):
	if multiplayer.is_server() and peer_id != 1:
		status_label.text = "Player connected! Starting game..."
		await get_tree().create_timer(1.0).timeout
		hide()

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
