class_name TileCursor
extends Node2D

## Aims the player's tools at a tile under the mouse.
##
## The world owns the tile data and the rules about what each tool may do to a
## tile; this only works out which cell is being aimed at, whether it is in
## reach, and draws the highlight. The player asks it for a target when a swing
## starts and tells it to apply when the swing lands.
##
## Keeping the effect off the input frame matters: the swing animations are
## two-thirds of a second, and applying on the button press makes the tile
## change before the tool has visibly moved.

@export var world_path: NodePath = ^".."
@export var player_path: NodePath = ^"../Player"
## How far the player can reach, in tiles, measured from the tile they stand on.
@export var reach: int = 4

@export_group("Highlight")
@export var valid_colour := Color(1.0, 1.0, 1.0, 0.85)
@export var blocked_colour := Color(0.35, 0.35, 0.4, 0.5)
@export var line_width: float = 1.0

var target: Vector2i = Vector2i.MAX
## True when the player's current tool would actually do something here.
var actionable: bool = false

@onready var _world: WorldGenerator = get_node(world_path)
@onready var _player: Player = get_node(player_path)

var _cursor: MouseCursor


func _ready() -> void:
	_cursor = get_node_or_null(^"../MouseCursor") as MouseCursor


func _process(_delta: float) -> void:
	var cell := _world.cell_at(get_global_mouse_position())
	var could := actionable
	actionable = _in_reach(cell) and _can_act(cell)
	if cell != target or could != actionable:
		target = cell
		queue_redraw()
	if _cursor != null:
		_cursor.set_state(MouseCursor.State.HOLDING if actionable else MouseCursor.State.POINTING)


## Chebyshev distance, so the reachable area is a square around the player and
## corners are not unfairly short of it.
func _in_reach(cell: Vector2i) -> bool:
	var standing := _world.cell_at(_player.global_position)
	var delta := (cell - standing).abs()
	return maxi(delta.x, delta.y) <= reach


func _can_act(cell: Vector2i) -> bool:
	match _player.current_tool:
		Player.Tool.HOE:
			return _world.can_till(cell)
		Player.Tool.AXE:
			return _world.can_chop(cell)
		Player.Tool.WATERING_CAN:
			return _world.can_water(cell)
	return false


## Runs the current tool on a cell. Called by the player when a swing finishes,
## and re-checks rather than trusting the target captured at the start -- the
## player may have walked out of reach mid-swing.
func apply(cell: Vector2i) -> bool:
	if not _in_reach(cell):
		return false
	match _player.current_tool:
		Player.Tool.HOE:
			return _world.till(cell)
		Player.Tool.AXE:
			return _world.chop(cell)
		Player.Tool.WATERING_CAN:
			return _world.water(cell)
	return false


func _draw() -> void:
	if target == Vector2i.MAX:
		return
	var size := Vector2(_world.tile_size())
	var origin := to_local(_world.cell_centre(target)) - size * 0.5
	draw_rect(Rect2(origin, size), valid_colour if actionable else blocked_colour,
		false, line_width)
