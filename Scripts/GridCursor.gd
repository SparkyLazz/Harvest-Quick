class_name GridCursor
extends Node2D

## Marks the tile the player will act on: four small corner brackets and a faint
## fill, green when the held item can do something there and red when it can't.
## Kept small on purpose so it reads as a hint rather than covering the soil.

@export_group("Look")
## Colour when the held item can act on the tile.
@export var valid_color: Color = Color("5fd45a")
## Colour when it can't.
@export var invalid_color: Color = Color("e0524e")
## Length of each bracket arm, in pixels.
@export_range(1, 8) var arm_length: int = 3
## Alpha of the fill inside the tile. 0 leaves just the brackets.
@export_range(0.0, 0.5, 0.01) var fill_alpha: float = 0.14
## How far the brackets breathe in and out, in pixels. 0 holds them still.
@export_range(0.0, 2.0, 0.5) var pulse: float = 1.0

var player: Player

var _cell := Vector2i.ZERO
var _valid := false
var _time := 0.0

func _ready() -> void:
	# Positioned in world space so it does not ride along with the player.
	top_level = true
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	if player == null:
		return
	_time += delta
	_cell = player.facing_cell()
	_valid = player.can_use_at(_cell)
	global_position = player.cell_center(_cell).round()
	queue_redraw()


func _draw() -> void:
	var color := valid_color if _valid else invalid_color
	var half := 8
	# Brackets sit inside the tile and swing out by the pulse.
	var out := roundi(absf(sin(_time * 4.0)) * pulse)
	var lo := -half - out
	var hi := half + out
	draw_rect(Rect2(-half, -half, half * 2, half * 2), Color(color, fill_alpha))
	var arm := arm_length
	for corner in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var x := lo if corner.x < 0 else hi
		var y := lo if corner.y < 0 else hi
		# Horizontal arm, then vertical arm, both growing inward from the corner.
		var hx := x if corner.x < 0 else x - arm
		var vy := y if corner.y < 0 else y - arm
		var hy := y if corner.y < 0 else y - 1
		var vx := x if corner.x < 0 else x - 1
		draw_rect(Rect2(hx, hy, arm, 1), color)
		draw_rect(Rect2(vx, vy, 1, arm), color)
