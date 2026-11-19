class_name DialogueBox
extends Control

## The speech box along the bottom of the screen.
##
## It is the pack's own **premade** dialogue plate, drawn whole and scaled by a
## whole number -- not a plate cut up and reassembled. The portrait window, the
## wooden rails around it, the bubble and the little tail pointing back at the
## speaker are all one piece of art, laid out by the person who drew it. An
## earlier version nine-sliced the bubble and placed the tail beside a separate
## frame by hand; the join never sat right, and there was no reason for it --
## the asset already is the layout. Everything below is therefore a measured
## position *inside* that image, and the image itself is never stretched.
##
## Unlike the other windows this one does not take the screen -- the farm stays
## visible behind it and there is no wash over the world, because you are
## standing in front of whoever is talking and should still see them. It is
## still a window as far as the HUD is concerned: the clock stops and the
## player stands still while it is up (`HUD.is_inventory_open`).
##
## The text types out a character at a time, which is the whole of the feel.
## Pressing on while it is still typing finishes the line instead of skipping
## it -- a line you have not read yet is never thrown away by an eager press.
## Pressing on a finished line moves to the next, and the pack's own
## click-to-continue chevron says so.
##
## **One line at a time, and it has to fit.** The bubble is as tall as it is
## drawn: the speaker's name and one line of speech, no wrapping. `fits()` says
## whether a line is short enough, and `test_town` runs every written line of
## every character through it, so a line too long to read is a failing test
## rather than a line cut off in play.

## The player pressed on and the line was already finished.
signal advanced

const PLATE := preload("res://Assets/UI/Dialog_Plate.png")
## The pack's "click to continue" marker: seven 16px frames of a little chevron
## bobbing. It is the signal every game of this kind uses, so it says "press
## on" without a word of text.
const MORE_SHEET := preload("res://Assets/UI/Dialog_More.png")
const MORE_CELL := 16
const MORE_FRAMES := 7

const INK := UISkin.TEXT_COLOR
const MUTED := UISkin.MUTED_COLOR

## The plate, at the size it was drawn.
const PLATE_SIZE := Vector2(304, 64)
## The dark window in it, measured off the art (its one solid purple block).
const RECESS := Rect2(16, 15, 32, 32)
## The bubble's pale inside, likewise (its one solid cream block).
const BUBBLE := Rect2(58, 20, 235, 31)

## Where the speaker's name and their line sit inside the bubble. The bubble's
## pale inside is 31 tall and a row of this face is 11, so two rows and a clear
## margin above and below is all it holds: 4, 11, 11, 5.
##
## The left inset is bigger than the right because the bubble's tail notches
## into its left edge about two thirds of the way down -- text set flush with
## the rim ran straight into the notch.
const ROW := 11.0
const PAD_LEFT := 13.0
const PAD_RIGHT := 8.0
const PAD_TOP := 4.0
const NAME_AT := Vector2(BUBBLE.position.x + PAD_LEFT, BUBBLE.position.y + PAD_TOP)
const LINE_AT := Vector2(BUBBLE.position.x + PAD_LEFT, BUBBLE.position.y + PAD_TOP + ROW)
## The marker sits in the bottom right corner, out of the line's way.
const MORE_CORNER := Vector2(BUBBLE.end.x - PAD_RIGHT - MORE_CELL,
		BUBBLE.end.y - MORE_CELL - 1.0)
## How wide a line may be before it runs under the marker.
const LINE_WIDTH := BUBBLE.size.x - PAD_LEFT - PAD_RIGHT - MORE_CELL

## The face is drawn at 1:1 in the middle of the recess, which leaves a good
## margin of window all round it. At 2:1 the cat fills the window corner to
## corner and reads as crammed in rather than framed.
const FACE_SIZE := Vector2(14, 16)

## How far the plate floats off the bottom of the screen, in screen pixels.
## Clear of the hotbar, which stands 10 off the edge and is about 90 tall at
## the default zoom.
const BOTTOM_MARGIN := 100
const MAX_FILL := 0.92

## Characters a second, while typing.
const SPEED := 42.0
## Frames a second for the "press on" marker.
const MORE_FPS := 10.0

var hud: HUD

var _frame: Control
var _plate: TextureRect
var _face: TextureRect
var _who: Label
var _text: Label
var _more: TextureRect
## The whole line being typed, and how much of it is on screen.
var _line := ""
var _shown := 0.0
var _more_time := 0.0
## The frame the box opened on, so the press that started the conversation
## cannot also turn its first page.
var _opened_frame := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	set_process(false)
	get_viewport().size_changed.connect(_recenter)
	Dialogue.started.connect(_on_started)
	Dialogue.line_shown.connect(_on_line)
	Dialogue.finished.connect(_on_finished)


func bind(target: HUD) -> void:
	hud = target
	_build()
	_recenter()


func is_open() -> bool:
	return visible


## True once the whole line is on screen.
func is_line_done() -> bool:
	return _shown >= float(_line.length())


## Whether `line` fits the bubble on one line at the game's one font size. The
## writing has to obey the art, not the other way round.
static func fits(line: String) -> bool:
	return UIFont.body().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1,
			UIFont.SIZE).x <= LINE_WIDTH


## What a press does: finish the line if it is still typing, otherwise move on.
## The HUD routes the key here, and `Player` never sees it.
func press() -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	if not is_line_done():
		_shown = float(_line.length())
		_text.text = _line
		_more_time = 0.0
		_more.visible = true
		return
	advanced.emit()
	Dialogue.advance()


func _process(delta: float) -> void:
	if not is_line_done():
		_shown = minf(_shown + SPEED * delta, float(_line.length()))
		_text.text = _line.substr(0, int(_shown))
		if is_line_done():
			_more_time = 0.0
			_more.visible = true
		return
	# The marker runs its loop while the line waits to be turned.
	_more_time += delta * MORE_FPS
	var frame := int(_more_time) % MORE_FRAMES
	(_more.texture as AtlasTexture).region = Rect2(frame * MORE_CELL, 0, MORE_CELL, MORE_CELL)


func _on_started(who: String, face: Texture2D, tint: Color) -> void:
	_who.text = who
	_face.texture = face
	_face.modulate = tint
	_face.visible = face != null
	visible = true
	_opened_frame = Engine.get_process_frames()
	set_process(true)
	_recenter()


func _on_line(line: String, _index: int, _total: int) -> void:
	_line = line
	_shown = 0.0
	_text.text = ""
	_more.visible = false


func _on_finished() -> void:
	visible = false
	set_process(false)
	_line = ""
	_shown = 0.0


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	# One frame holding the plate and everything measured onto it, scaled whole.
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)

	_plate = TextureRect.new()
	_plate.texture = PLATE
	_plate.stretch_mode = TextureRect.STRETCH_KEEP
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_plate.size = PLATE_SIZE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_plate)

	# The speaker's own sprite, in the plate's window. There are no drawn
	# portraits in either pack, so a face is whoever is talking.
	_face = TextureRect.new()
	_face.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.size = FACE_SIZE
	_face.position = (RECESS.position + (RECESS.size - FACE_SIZE) * 0.5).floor()
	_face.visible = false
	_frame.add_child(_face)

	_who = _label("", MUTED, NAME_AT)
	_text = _label("", INK, LINE_AT)

	_more = TextureRect.new()
	_more.texture = AtlasTexture.new()
	(_more.texture as AtlasTexture).atlas = MORE_SHEET
	(_more.texture as AtlasTexture).region = Rect2(0, 0, MORE_CELL, MORE_CELL)
	_more.stretch_mode = TextureRect.STRETCH_KEEP
	_more.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_more.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_more.position = MORE_CORNER
	_more.size = Vector2(MORE_CELL, MORE_CELL)
	_more.visible = false
	_frame.add_child(_more)


## A label placed at a measured spot on the plate rather than laid out by a
## container: the plate is a drawing, and everything on it has a place in it.
## Added to the tree before its text is set, which is the order this face
## needs (`Docs/TECH_NOTES.md` §9).
func _label(text: String, color: Color, at: Vector2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIFont.body())
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	_frame.add_child(label)
	label.position = at
	label.size = Vector2(LINE_WIDTH, ROW)
	# Centred in its own row, so the two rows sit evenly in the bubble instead
	# of hanging from their baselines.
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = text
	return label


func _zoom() -> int:
	var want: int = hud.ui_scale if hud != null else 2
	var room := get_viewport_rect().size * MAX_FILL
	while want > 1 and (PLATE_SIZE.x * want > room.x or PLATE_SIZE.y * want > room.y):
		want -= 1
	return want


## Centred across the screen and standing BOTTOM_MARGIN off its bottom edge.
func _recenter() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _frame == null:
		return
	var zoom := _zoom()
	_frame.scale = Vector2.ONE * zoom
	_frame.size = PLATE_SIZE
	_frame.position = Vector2((size.x - PLATE_SIZE.x * zoom) * 0.5,
			size.y - PLATE_SIZE.y * zoom - BOTTOM_MARGIN).round()
