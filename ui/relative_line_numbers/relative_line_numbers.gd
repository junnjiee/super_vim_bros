extends CanvasLayer

# Vim-style relative line numbers displayed along the left side of the viewport

# Configuration
@export var row_height: int = 64  # Pixels per row (sprite height)
@export var visible_rows: int = 24  # Number of rows to display (above and below)
@export var gutter_width: int = 60  # Width of the gutter background
@export var current_row_color: Color = Color(1.0, 1.0, 0.0)  # Yellow for "0"
@export var relative_number_color: Color = Color(0.6, 0.6, 0.6)  # Gray for relative numbers
@export var gutter_bg_color: Color = Color(0.1, 0.1, 0.1, 0.7)  # Dark semi-transparent

# References
var player: Node2D = null
var camera: Camera2D = null
var gutter_background: ColorRect
var number_container: Control
var label_pool: Array[Label] = []

func _ready():
	# Set up gutter background
	gutter_background = ColorRect.new()
	gutter_background.color = gutter_bg_color
	gutter_background.size = Vector2(gutter_width, 0)  # Height will be set in _process
	gutter_background.position = Vector2(0, 0)
	add_child(gutter_background)

	# Set up number container
	number_container = Control.new()
	add_child(number_container)

	# Create label pool
	for i in range(visible_rows):
		var label = Label.new()
		label.add_theme_font_size_override("font_size", 14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = Vector2(gutter_width, 20)
		number_container.add_child(label)
		label_pool.append(label)

	# Find player reference (will be added to group in player script)
	call_deferred("_find_player")

func _find_player():
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0]

	# Try to find camera
	var cameras = get_tree().get_nodes_in_group("camera")
	if cameras.size() > 0:
		camera = cameras[0]

func _process(_delta):
	if not player:
		return

	# Get viewport size
	var viewport_size = get_viewport().get_visible_rect().size

	# Update gutter background height
	gutter_background.size.y = viewport_size.y

	# Calculate player's current row
	var player_row = floor(player.global_position.y / row_height)

	# Calculate viewport vertical range
	var viewport_top = 0
	var viewport_bottom = viewport_size.y

	# Calculate how many rows fit in viewport
	var rows_in_viewport = int(ceil(viewport_size.y / row_height)) + 2  # Extra rows for overscan

	# Calculate starting world row (top of viewport)
	var camera_offset = 0
	if camera:
		camera_offset = camera.get_screen_center_position().y - viewport_size.y / 2

	var top_world_row = floor(camera_offset / row_height)
	var camera_row_offset = camera_offset - (top_world_row * row_height)

	# Update labels
	var label_index = 0
	rows_in_viewport = min(rows_in_viewport, label_pool.size())
	for i in range(rows_in_viewport):
		if label_index >= label_pool.size():
			break

		var world_row = top_world_row + i
		var relative_distance = world_row - player_row

		var label = label_pool[label_index]
		label.position = Vector2(
			0,
			i * row_height - camera_row_offset + (row_height / 2.0) - (label.size.y / 2.0)
		)

		# Set text and color based on relative distance
		if relative_distance == 0:
			label.text = "0"
			label.add_theme_color_override("font_color", current_row_color)
		else:
			label.text = str(abs(relative_distance))
			label.add_theme_color_override("font_color", relative_number_color)

		label.visible = true
		label_index += 1

	# Hide unused labels
	for i in range(label_index, label_pool.size()):
		label_pool[i].visible = false

func get_player_row() -> int:
	if player:
		return floor(player.global_position.y / row_height)
	return 0

func get_world_y_for_row(row: int) -> float:
	return row * row_height
