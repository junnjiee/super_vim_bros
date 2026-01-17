extends StaticBody2D

# Properties
var letter: String = ""
var lifetime: float = 10.0
var player_color: Color = Color(0.5, 0.5, 0.5, 0.5)

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual_rect: ColorRect = $ColorRect
@onready var letter_label: Label = $Label


func _ready():
	# Set up collision layer (layer 2 for walls/platforms)
	collision_layer = 2
	collision_mask = 0

	# Configure visual ColorRect
	if visual_rect:
		visual_rect.size = Vector2(64, 64)
		visual_rect.position = Vector2(-32, -32)  # Center it
		visual_rect.color = player_color

	# Configure letter label
	if letter_label:
		letter_label.text = letter
		letter_label.position = Vector2(-32, -32)
		letter_label.size = Vector2(64, 64)
		letter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter_label.add_theme_font_size_override("font_size", 32)

	# Set up lifetime timer
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.one_shot = true
	timer.timeout.connect(_on_lifetime_expired)
	add_child(timer)
	timer.start()


func _on_lifetime_expired():
	queue_free()


func initialize(pos: Vector2, ltr: String, color: Color):
	position = pos
	letter = ltr
	player_color = color
