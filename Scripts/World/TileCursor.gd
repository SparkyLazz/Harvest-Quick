class_name TileCursor
extends Node2D

## The four brackets that sit on the tile the player is about to act on.
##
## The same cursor the hotbar puts round the chosen slot, moved into the
## world. Four corner sprites rather than a box, so the thing being pointed
## at stays visible through the middle of it.
##
## It is only ever drawn over a tile where the held thing would actually do
## something. That is the whole of the feedback: no red cross, no greyed-out
## frame, nothing to read — if the brackets are there the swing will land,
## and if they are not it will not. A cursor that appears everywhere and
## changes colour asks the player to look twice; this one asks them to look
## once.
##
## It hangs off the player but is [member Node2D.top_level], so the player's
## own movement does not drag it around: it is told a tile and puts itself
## there, stepping from square to square the way a tile cursor should.

## The sheet of corner brackets. Six columns by five rows of 16-pixel cells:
## columns in pairs make a palette, rows in pairs make a set of four corners.
@export var sheet: Texture2D

## Which column pair. 0 is white, 1 light wood, 2 dark wood.
@export_range(0, 2) var palette: int = 1

## Which row pair. 0 is the brighter set, 1 the softer one.
@export_range(0, 1) var variant: int = 0

## How far outside the tile the brackets sit, in pixels.
##
## Not decoration. Each bracket is eight by nine and four of them laid on a
## sixteen-pixel tile meet in the middle and read as a filled box — the shape
## stops being a corner once the corners touch. Pushed out a few pixels they
## separate, the tile shows through, and what is under the cursor stays
## readable, which is the only reason to use brackets rather than a rectangle.
@export var margin: float = 4.0

## One cell of the selector sheet.
const CELL := 16.0

## Where the bracket actually sits inside its cell, and how big it is. The
## artist centred each one rather than putting it in a corner, so the cell is
## mostly empty and the useful part has to be cut out of it.
const GLYPH_INSET := Vector2(4.0, 4.0)
const GLYPH_SIZE := Vector2(8.0, 9.0)

var _area: Vector2 = Vector2(CELL, CELL)

func _ready() -> void:
	top_level = true
	z_index = 100
	visible = false

## Puts the brackets round the area starting at [param at] — a point in
## global space, its top-left corner — covering [param area] pixels.
func show_at(at: Vector2, area: Vector2) -> void:
	var changed := not visible or _area != area
	global_position = at
	_area = area
	visible = true
	if changed:
		queue_redraw()

func hide_cursor() -> void:
	if visible:
		visible = false

## Draws each bracket at its own corner of the area, grown by [member
## margin] so the four of them do not meet.
##
## For a single tile this is a frame round the square. For anything wider the
## brackets spread to the outer corners and the middle is left open, so a
## two-by-two shed is framed rather than tiled over.
func _draw() -> void:
	if sheet == null:
		return
	var origin := -Vector2(margin, margin)
	var span := _area + Vector2(margin, margin) * 2.0
	var far := span - GLYPH_SIZE
	var col := float(palette) * CELL * 2.0 + GLYPH_INSET.x
	var row := float(variant) * CELL * 2.0 + GLYPH_INSET.y
	var corners := [
		[Vector2.ZERO, Vector2(col, row)],
		[Vector2(far.x, 0.0), Vector2(col + CELL, row)],
		[Vector2(0.0, far.y), Vector2(col, row + CELL)],
		[Vector2(far.x, far.y), Vector2(col + CELL, row + CELL)],
	]
	for corner in corners:
		draw_texture_rect_region(
			sheet,
			Rect2(origin + (corner[0] as Vector2), GLYPH_SIZE),
			Rect2(corner[1] as Vector2, GLYPH_SIZE))
