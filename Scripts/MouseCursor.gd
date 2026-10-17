extends Node

## The cursor says what the mouse can do.
##
## An ordinary arrow while there is nothing under the pointer, a cat's paw over
## anything that can be used, and a closed paw while a stack is being carried.
## Nothing floats over the world and nothing has to be read -- the thing you are
## already looking at changes shape.
##
## This is the real system cursor rather than a sprite drawn in the scene, so it
## cannot lag a frame behind the pointer or end up underneath a panel. The art
## is 16px, far too small on a modern screen, so each paw is blown up by
## `zoom` with no smoothing before it is handed over.

enum Shape { IDLE, POINT, GRAB }

const ART := {
	Shape.IDLE: preload("res://Assets/UI/Cursor_Arrow.png"),
	Shape.POINT: preload("res://Assets/UI/Cursor_Paw.png"),
	Shape.GRAB: preload("res://Assets/UI/Cursor_Grab.png"),
}

## How far up the 16px art is scaled. 3 puts it near a normal desktop cursor.
const ZOOM := 3
## Where the cursor actually aims, in art pixels: the arrow's tip. The paws
## share it rather than taking their own centre, so the pointer does not jump
## sideways at the moment the shape changes.
const HOTSPOT := Vector2(3, 1)

## Layer holding the furniture, by name, in whatever scene is current.
const PROPS := ^"Props"

var _shape := Shape.IDLE
var _scaled := {}
var _carrying := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for shape in ART:
		_scaled[shape] = _blow_up(ART[shape])
	_apply(Shape.IDLE, true)


func _process(_delta: float) -> void:
	if _carrying:
		_apply(Shape.GRAB)
	else:
		_apply(Shape.POINT if hovering_usable() else Shape.IDLE)


## Switches to the closed paw, for when a stack is picked up.
func set_carrying(value: bool) -> void:
	_carrying = value


## Is the pointer over something the player could use?
##
## Every prop is painted, so the answer is one lookup: does the tile under the
## pointer carry a verb in the tileset's "interact" data?
func hovering_usable() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var props := scene.get_node_or_null(PROPS) as TileMapLayer
	if props == null:
		return false
	var cell := props.local_to_map(props.to_local(props.get_global_mouse_position()))
	var data := props.get_cell_tile_data(cell)
	return data != null and str(data.get_custom_data("interact")) != ""


func shape() -> Shape:
	return _shape


func _apply(to: Shape, force: bool = false) -> void:
	if to == _shape and not force:
		return
	_shape = to
	Input.set_custom_mouse_cursor(_scaled[to], Input.CURSOR_ARROW, HOTSPOT * ZOOM)


## Nearest-neighbour blow-up: Image.resize would blur the pixels otherwise.
func _blow_up(texture: Texture2D) -> ImageTexture:
	var image := texture.get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)
