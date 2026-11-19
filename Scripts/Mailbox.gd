class_name Mailbox
extends Node2D

## The mailbox beside the house, and the flag that says there is something in
## it.
##
## A node rather than a painted tile, for the same reason the collector is one:
## it changes with the state of the game, and a tile cannot. It uses the same
## `interactable` group, so walking up to it and using it is the same gesture
## as a chest.
##
## The pack's sheet is an animation of a letter popping up over the box. Only
## two of its frames are used here -- the letter fully up, in two positions a
## pixel apart -- which bob slowly while there is unread post, so the box waves
## at the player from across the farm. With nothing unread it shows the plain
## closed box instead.

const GROUP := &"interactable"

const SHEET := preload("res://Assets/Objects/Mailbox.png")
## The sheet is a grid of 32x48 cells, five across and seven down.
const CELL := Vector2i(32, 48)
## The plain closed box.
const FRAME_EMPTY := Vector2i(0, 4)
## The two frames with the letter up, a pixel apart, that make the wave.
const FRAMES_MAIL: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2)]
## Where the box's foot is inside a cell. **Measured**, not guessed: the post
## stands on y 41 and is centred on x 12 in every frame used here.
const ORIGIN := Vector2(12, 41)

## Seconds between the letter's two positions.
const WAVE := 0.55

@export_group("Scene")
## Layer that supplies the grid, so the cell to reach can be worked out from
## where the box stands. A sibling named "Grass Layer", as Farm and Collector.
@export var ground_layer_path: NodePath = ^"../Grass Layer"

var _sprite: Sprite2D
var _layer: TileMapLayer
var _wave := 0.0
var _frame := 0


func _ready() -> void:
	add_to_group(GROUP)
	_layer = get_node_or_null(ground_layer_path) as TileMapLayer

	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = -ORIGIN
	add_child(_sprite)

	Mail.changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	_wave += delta
	if _wave < WAVE:
		return
	_wave -= WAVE
	_frame = (_frame + 1) % FRAMES_MAIL.size()
	_show(FRAMES_MAIL[_frame])


## The cell it stands on, which is what the player has to reach.
func interact_cell() -> Vector2i:
	if _layer == null:
		return Vector2i.ZERO
	return _layer.local_to_map(_layer.to_local(global_position))


## What using it would do, for the prompt. Always something: an empty box can
## still be opened, and the window then says so.
func interact_verb() -> String:
	return "mailbox"


## Opens the post. The HUD owns the window, as it owns every other one.
func interact(_player: Node) -> bool:
	var hud := get_tree().get_first_node_in_group(HUD.GROUP) as HUD
	if hud == null:
		return false
	hud.open_mail()
	return true


## The flag waves while something is unread, and the box is plain once it is
## all read. `_process` only runs while there is something to wave.
func _refresh() -> void:
	var waiting := Mail.has_unread()
	set_process(waiting)
	if waiting:
		_frame = 0
		_wave = 0.0
		_show(FRAMES_MAIL[0])
	else:
		_show(FRAME_EMPTY)


func _show(frame: Vector2i) -> void:
	_sprite.texture = UISkin.atlas(SHEET,
			Rect2(frame.x * CELL.x, frame.y * CELL.y, CELL.x, CELL.y))
