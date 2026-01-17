extends Node2D

# Configuration
@export var cell_size: int = 64  # Matches dash_unit_size
@export var line_color: Color = Color(0.5, 0.5, 0.5, 0.6)
@export var line_width: float = 2.0
@export var camera: Camera2D

# Line pools
var horizontal_lines: Array[Line2D] = []
var vertical_lines: Array[Line2D] = []

# Pool sizes
const H_LINE_COUNT = 50
const V_LINE_COUNT = 50


func _ready():
	_create_line_pools()

	# Auto-find camera if not assigned
	if camera == null:
		var cameras = get_tree().get_nodes_in_group("camera")
		if cameras.size() > 0:
			camera = cameras[0]
			print("Grid overlay: Found camera in group")
		else:
			print("Grid overlay: WARNING - No camera found!")
	else:
		print("Grid overlay: Camera already assigned")


func _create_line_pools():
	# Create horizontal lines
	for i in range(H_LINE_COUNT):
		var line = Line2D.new()
		line.width = line_width
		line.default_color = line_color
		line.z_index = 10
		add_child(line)
		horizontal_lines.append(line)

	# Create vertical lines
	for i in range(V_LINE_COUNT):
		var line = Line2D.new()
		line.width = line_width
		line.default_color = line_color
		line.z_index = 10
		add_child(line)
		vertical_lines.append(line)

	print("Grid overlay: Created ", horizontal_lines.size(), " horizontal and ", vertical_lines.size(), " vertical lines")


func _process(_delta):
	if camera == null:
		return
	_update_grid_lines()


func _update_grid_lines():
	# Get camera viewport bounds
	var viewport_size = get_viewport_rect().size
	var camera_pos = camera.get_screen_center_position()

	# Account for camera zoom
	var zoom = camera.zoom
	var visible_width = viewport_size.x / zoom.x
	var visible_height = viewport_size.y / zoom.y

	# Calculate visible bounds
	var left = camera_pos.x - visible_width / 2
	var right = camera_pos.x + visible_width / 2
	var top = camera_pos.y - visible_height / 2
	var bottom = camera_pos.y + visible_height / 2

	# Add some padding to ensure coverage
	var padding = cell_size * 2
	left -= padding
	right += padding
	top -= padding
	bottom += padding

	# Snap bounds to grid
	var grid_left = floor(left / cell_size) * cell_size
	var grid_right = ceil(right / cell_size) * cell_size
	var grid_top = floor(top / cell_size) * cell_size
	var grid_bottom = ceil(bottom / cell_size) * cell_size

	# Update horizontal lines
	var h_index = 0
	var y = grid_top
	while y <= grid_bottom and h_index < horizontal_lines.size():
		var line = horizontal_lines[h_index]
		line.clear_points()
		line.add_point(Vector2(grid_left, y))
		line.add_point(Vector2(grid_right, y))
		y += cell_size
		h_index += 1

	# Hide unused horizontal lines
	while h_index < horizontal_lines.size():
		horizontal_lines[h_index].clear_points()
		h_index += 1

	# Update vertical lines
	var v_index = 0
	var x = grid_left
	while x <= grid_right and v_index < vertical_lines.size():
		var line = vertical_lines[v_index]
		line.clear_points()
		line.add_point(Vector2(x, grid_top))
		line.add_point(Vector2(x, grid_bottom))
		x += cell_size
		v_index += 1

	# Hide unused vertical lines
	while v_index < vertical_lines.size():
		vertical_lines[v_index].clear_points()
		v_index += 1
