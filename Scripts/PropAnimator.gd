class_name PropAnimator
extends Node

## Opens and shuts painted props, by stamping one frame over the next.
##
## Godot can animate a tile on its own, but only on a loop -- right for water,
## wrong for a chest, which has to open when it is used and then stay open. So
## the frames are ordinary tiles here and this walks the cell along them.
##
## Where the frames are comes off the tile itself: the first one carries how
## many follow it (`frames`) and how far apart they sit on the sheet (`step`),
## beside the verb that says what using it does. Painting a new animated prop
## and tagging it is therefore the whole job -- nothing here needs editing.
##
## Every frame carries its own index, so a cell always describes itself: which
## prop it is, how far along it is, and where its first frame sits. That means
## nothing here has to be remembered between uses -- open or shut is read off
## the tilemap, which is also the thing that saves and loads.

## Fires when a prop finishes moving, with its cell and whether it ended open.
signal finished(cell: Vector2i, opened: bool)

## Seconds each frame is held. Five frames at this rate is a brisk quarter
## second, which is about how long a lid takes.
@export_range(0.01, 0.5, 0.005) var frame_time: float = 0.055

## Cells part-way through a move, so a second press cannot start a second run
## of the same lid on top of the first.
var _moving: Dictionary = {}


## The floor a prop is used from. Everything is drawn facing the camera, so a
## prop's front is the cell below it -- that is where the player stands, and
## where its hitbox belongs.
static func front_of(cell: Vector2i) -> Vector2i:
	return cell + Vector2i(0, 1)


## The prop `cell` acts on: the one painted there, or the one standing directly
## behind it. A prop's hitbox is the floor in front of it, so standing on that
## floor is enough -- the chest does not have to be stepped into, and the facing
## does not have to be lined up.
static func reached_from(layer: TileMapLayer, cell: Vector2i) -> Vector2i:
	if layer == null:
		return cell
	if layer.get_cell_tile_data(cell) != null:
		return cell
	var behind := cell - Vector2i(0, 1)
	return behind if layer.get_cell_tile_data(behind) != null else cell


## What the tile at `cell` is and how it animates, or an empty dictionary when
## it is not something that can be used.
static func describe(layer: TileMapLayer, cell: Vector2i) -> Dictionary:
	if layer == null:
		return {}
	var data := layer.get_cell_tile_data(cell)
	if data == null:
		return {}
	var verb := str(data.get_custom_data("interact"))
	if verb.is_empty():
		return {}
	var frames := maxi(int(data.get_custom_data("frames")), 1)
	var step := maxi(int(data.get_custom_data("step")), 1)
	var index := clampi(int(data.get_custom_data("frame")), 0, frames - 1)
	return {
		"verb": verb,
		"frames": frames,
		"step": step,
		"frame": index,
		"source": layer.get_cell_source_id(cell),
		# Wind back from wherever it is to where it started.
		"base": layer.get_cell_atlas_coords(cell) - Vector2i(step * index, 0),
	}


## Where frame `index` of a prop whose first frame is `base` sits on the sheet.
static func frame_at(base: Vector2i, step: int, index: int) -> Vector2i:
	return base + Vector2i(step * index, 0)


## Is this prop standing open? Read off the tile, not off memory.
func is_open(layer: TileMapLayer, cell: Vector2i) -> bool:
	var prop := describe(layer, cell)
	return not prop.is_empty() and int(prop["frame"]) >= int(prop["frames"]) - 1


## Can this prop move at all? A dresser is usable but has only one frame.
func can_animate(layer: TileMapLayer, cell: Vector2i) -> bool:
	var prop := describe(layer, cell)
	return not prop.is_empty() and int(prop["frames"]) > 1


## True while this prop's frames are still running.
func is_moving(cell: Vector2i) -> bool:
	return _moving.has(cell)


## Opens a shut prop, shuts an open one. False when there was nothing to do --
## including mid-move, so a second press is not quietly swallowed while a lid
## is still travelling.
func toggle(layer: TileMapLayer, cell: Vector2i) -> bool:
	if is_moving(cell) or not can_animate(layer, cell):
		return false
	play(layer, cell, not is_open(layer, cell))
	return true


## Runs the frames from where the prop is to either end, stamping each over the
## cell as it goes. Returns at once; `finished` fires at the end.
func play(layer: TileMapLayer, cell: Vector2i, opening: bool) -> void:
	if _moving.has(cell):
		return
	var prop := describe(layer, cell)
	if prop.is_empty():
		return
	var frames: int = prop["frames"]
	var from: int = prop["frame"]
	var to: int = frames - 1 if opening else 0
	if frames <= 1 or from == to:
		return
	_moving[cell] = true
	var forward := to > from
	var tween := create_tween()
	var index := from
	while index != to:
		index += 1 if forward else -1
		tween.tween_callback(_stamp.bind(layer, cell, prop, index))
		tween.tween_interval(frame_time)
	tween.tween_callback(func() -> void:
		_moving.erase(cell)
		finished.emit(cell, opening))


## Shuts every open prop on a layer, for leaving a room.
func close_all(layer: TileMapLayer) -> void:
	if layer == null:
		return
	for cell in layer.get_used_cells():
		if is_open(layer, cell):
			var prop := describe(layer, cell)
			_stamp(layer, cell, prop, 0)


func _stamp(layer: TileMapLayer, cell: Vector2i, prop: Dictionary, index: int) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.set_cell(cell, int(prop["source"]),
			frame_at(prop["base"], int(prop["step"]), index), 0)
