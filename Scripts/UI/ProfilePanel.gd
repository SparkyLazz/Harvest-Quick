@tool
class_name ProfilePanel
extends Control

## The left half of the inventory window: who you are.
##
## A framed cat at the top left with a few lines of detail beside him, and
## the rest of the panel left open. The frame is the item box nine-sliced;
## at 40x42 its middle lands at exactly 32x32, which is one cell of the
## emote sheet, so the cat fills the opening without being scaled.
##
## Teemo's sheet is a 32x32 grid where each row is one mood and the filled
## cells across that row are its frames, so a mood is a row and a length,
## nothing more. The portrait plays the current mood on a loop; clicking
## him moves to the next one.
##
## The detail lines hold placeholder text. Feed them with [method set_line]
## once there is something to say, and the hearts with [method set_health].
##
## The artist drew each heart three ways — full, half and empty — so half a
## point of damage has a picture and the row never has to fake one by
## scaling or tinting.

## Emitted when the portrait is clicked, with the mood now showing.
signal poked(mood: int)

const CELL: int = 32

## Frames per row of the emote sheet, in row order. Rows the artist left
## part-empty simply have fewer.
const MOOD_FRAMES: Array[int] = [1, 2, 5, 4, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1]

## Which row to sit on when nothing has happened yet: the two-frame blink.
const IDLE_MOOD: int = 1

## The three states of a heart, on the inventory sheet.
const HEART_FULL := Rect2(7, 25, 18, 16)
const HEART_HALF := Rect2(39, 25, 18, 16)
const HEART_EMPTY := Rect2(71, 25, 18, 16)

## The mood on show, as a row of the sheet.
@export var mood: int = IDLE_MOOD:
	set(value):
		mood = posmod(value, MOOD_FRAMES.size())
		_frame = 0
		_elapsed = 0.0
		_apply_frame()

## Seconds each frame is held.
@export var frame_time: float = 0.45

## Clicking cycles to the next mood. Off, the portrait only watches.
@export var click_cycles_mood: bool = true

@export_group("Health")
## Half-hearts filled. Two per heart, so 7 is three and a half.
@export var health: int = 10:
	set(value):
		health = maxi(value, 0)
		_apply_health()
## Half-hearts the row can hold. Hearts past this are not drawn at all.
@export var max_health: int = 10:
	set(value):
		max_health = maxi(value, 0)
		_apply_health()

@onready var _cat: TextureRect = $Frame/Cat
@onready var _button: Button = $Click
@onready var _lines: Control = $Lines
@onready var _hearts: Control = $Hearts

var _frame: int = 0
var _elapsed: float = 0.0

func _ready() -> void:
	_apply_frame()
	_apply_health()
	if Engine.is_editor_hint():
		set_process(false)
		return
	_button.pressed.connect(_on_pressed)

func _process(delta: float) -> void:
	var count := MOOD_FRAMES[mood]
	if count <= 1:
		return
	_elapsed += delta
	if _elapsed < frame_time:
		return
	_elapsed -= frame_time
	_frame = (_frame + 1) % count
	_apply_frame()

## How many detail lines the scene holds.
func line_count() -> int:
	return _lines.get_child_count() if _lines != null else 0

## Writes [param text] on detail line [param index], counting from the top.
func set_line(index: int, text: String) -> void:
	if _lines == null or index < 0 or index >= _lines.get_child_count():
		return
	(_lines.get_child(index) as Label).text = text

## Sets the row to [param current] half-hearts out of [param maximum].
func set_health(current: int, maximum: int = -1) -> void:
	if maximum >= 0:
		max_health = maximum
	health = current

func _apply_health() -> void:
	if not is_node_ready() or _hearts == null:
		return
	for i in _hearts.get_child_count():
		var heart := _hearts.get_child(i) as TextureRect
		var atlas := heart.texture as AtlasTexture
		if atlas == null:
			continue
		# Two half-hearts to a heart: this one covers half-points 2i and 2i+1.
		var filled := clampi(health - i * 2, 0, 2)
		heart.visible = i * 2 < max_health
		atlas.region = [HEART_EMPTY, HEART_HALF, HEART_FULL][filled]

func _on_pressed() -> void:
	if click_cycles_mood:
		mood = mood + 1
	poked.emit(mood)

func _apply_frame() -> void:
	if not is_node_ready():
		return
	var atlas := _cat.texture as AtlasTexture
	if atlas == null:
		return
	atlas.region = Rect2(_frame * CELL, mood * CELL, CELL, CELL)
