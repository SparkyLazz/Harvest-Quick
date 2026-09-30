class_name PlacementGhost
extends Node2D

## The square of light over the tile a thing would land on.
##
## Drawn rather than drawn from a sprite, because what it has to show is one
## rectangle in one of two colours and an atlas region would be three files
## of ceremony for that. It follows the tile, not the player, so it steps
## from square to square instead of sliding — which is the whole point, since
## a thing lands on a tile and not on a point.
##
## It hangs off the player but is [member Node2D.top_level], so the player's
## own movement does not drag it around; it is told a tile and puts itself
## there. Lifted clear of the y-sorted layer by [member CanvasItem.z_index]
## so it is never hidden behind the very thing it is measuring.

## Fill over ground the thing may be set down on.
@export var valid_colour := Color(0.55, 0.9, 0.45, 0.35)
## Fill over ground it may not.
@export var invalid_colour := Color(0.95, 0.4, 0.38, 0.35)
## How solid the outline is, against the fill.
@export var edge_strength: float = 2.4

var _size: Vector2 = Vector2(16.0, 16.0)
var _valid: bool = true

func _ready() -> void:
	top_level = true
	z_index = 100
	visible = false

## Puts the square over [param at] — a point in global space, the top-left
## corner of the area — covering [param area] pixels, and colours it for
## [param valid].
func show_at(at: Vector2, area: Vector2, valid: bool) -> void:
	var changed := not visible or _valid != valid or _size != area
	global_position = at
	_size = area
	_valid = valid
	visible = true
	if changed:
		queue_redraw()

func hide_ghost() -> void:
	if visible:
		visible = false

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, _size)
	var fill := valid_colour if _valid else invalid_colour
	draw_rect(rect, fill, true)
	# The outline is the fill again at full strength rather than a colour of
	# its own, so the two can never drift apart when the fill is retuned.
	var edge := Color(fill.r, fill.g, fill.b, minf(fill.a * edge_strength, 1.0))
	draw_rect(rect, edge, false, 1.0)
