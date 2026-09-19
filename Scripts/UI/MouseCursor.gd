class_name MouseCursor
extends Node

## Swaps the hardware cursor between the pack's cat-paw sprites.
##
## Pointing is the resting cursor; holding is shown when whatever is under the
## cursor can actually be acted on -- a tree to chop, soil to hoe, and later an
## item lying on the ground to pick up.

enum State { POINTING, HOLDING }

const SPRITES := {
	State.POINTING: "res://Assets/Mouse sprites/Catpaw pointing Mouse icon.png",
	State.HOLDING: "res://Assets/Mouse sprites/Catpaw holding Mouse icon.png",
}

## The sprites are 16x16, which is a speck on a desktop window, so they are
## scaled up by whole numbers with nearest-neighbour to stay crisp.
@export_range(1, 8) var pixel_scale: int = 3
## Where the click lands, in source pixels. The paw has no obvious tip, so the
## default is its middle; move it to a toe if that reads better to you.
@export var hotspot := Vector2(8, 8)

var _textures: Dictionary = {}
var _state: int = -1


func _ready() -> void:
	for state: int in SPRITES:
		_textures[state] = _scaled(SPRITES[state])
	set_state(State.POINTING)


func set_state(state: int) -> void:
	if state == _state or not _textures.has(state):
		return
	_state = state
	Input.set_custom_mouse_cursor(_textures[state], Input.CURSOR_ARROW, hotspot * pixel_scale)


func _scaled(path: String) -> ImageTexture:
	var source: Texture2D = load(path)
	var image := source.get_image()
	image.resize(
		image.get_width() * pixel_scale,
		image.get_height() * pixel_scale,
		Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)
