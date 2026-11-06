class_name UIFont
extends RefCounted

## The one face all of the game's text is set in: the pack's 5x5 capitals, the
## face the clock's date plate was designed with. The developer picked it for
## everything (2026-11-06) because it is the easiest to read; the heavier 7x7
## and 7x5 faces that headings and descriptions used before are retired.
##
## title(), body() and small() are kept as roles, so every call site still says
## what its text is. They all hand back the same face: a heading is told from
## a description by its colour instead -- the dark ink over the soft brown, the
## way the clock plate sets the date under the season. To give headings a face
## of their own again, change title() here and nothing else.
##
## The face is drawn on a 5px grid and only lands every stroke on a whole pixel
## at SIZE (measured: at 10 it already doubles some strokes and not others), so
## never ask for another size -- scale the node instead, by whole numbers.
##
## The hard edges come from its import settings -- antialiasing None, subpixel
## positioning Disabled, in Assets/Fonts/*.ttf.import -- so the editor shows it
## exactly as the game does. If text ever goes soft, check those first.

## The one size the face is drawn at.
const SIZE := 8
## The same size, under the name the clock plate has always used.
const SMALL_SIZE := SIZE

const _FACE := preload("res://Assets/Fonts/pixelFont-2-5x5-sproutLands.ttf")

## The eight one-pixel steps around a pixel.
const _AROUND: Array[Vector2] = [
	Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0),
	Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1),
]


## Draws `text` in `ink`, ringed by a one-pixel `halo`, at `baseline`.
##
## Make the halo the colour of whatever the text normally sits on: where the
## letters' rings run together it then vanishes, and it only shows where the
## text crosses something else -- a stack count over its icon, a "+3" over
## grass -- the way the pack's drop sprites wear their cream outline.
##
## Do not reach for the font's own outline_size on this face: it strokes the
## glyph's vector shape, which at 1 is half a pixel a side and breaks up into
## dots, at 2 chips every corner, and at 3 fills the one-pixel gaps between
## letters until a count reads as a dark block. Measured off renders.
static func draw_haloed(item: CanvasItem, baseline: Vector2, text: String,
		align: HorizontalAlignment, width: float, ink: Color, halo: Color) -> void:
	for step in _AROUND:
		item.draw_string(_FACE, baseline + step, text, align, width, SIZE, halo)
	item.draw_string(_FACE, baseline, text, align, width, SIZE, ink)


## Names, headings, tabs and stack counts.
static func title() -> FontFile:
	return _FACE


## Descriptions and values.
static func body() -> FontFile:
	return _FACE


## Tight spots, like the clock's date plate.
static func small() -> FontFile:
	return _FACE
