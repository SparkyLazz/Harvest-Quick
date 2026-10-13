extends SceneTree

## Adds the Sprout Lands village house to the project's TileSet, cut into single
## 16x16 tiles -- one per cell of the sheet, not one per house -- each with its
## share of the wall collider and a sort origin on the house's doorstep.
##
##   godot --headless --path . --script Tools/setup_house_tiles.gd
##
## Note: a headless save drops every uid:// from the TileSet, because nothing
## loads the uid cache outside the editor. Check `git diff` after running this
## and put them back, or run it from the editor instead.
##
## Re-running replaces the source it added before rather than stacking a second
## copy, and keeps the same source id, so anything already painted with these
## tiles survives. The village pack's huts are cut the same way (a 3x3 grid of
## 64x64) and the grey brick houses as a 1x3 grid of 96x80, so either can be
## added by pointing TEXTURE at its sheet and setting GRID and HOUSE_TILES to
## match.
##
## Cutting a house into loose cells rather than one big tile is what lets you
## paint half a house, mix a roof with another wall, or butt two houses up
## against each other. The cost is that a y-sorted layer sorts every cell on its
## own, which would slice a house in half around the player -- so each cell's
## sort origin is pushed down onto the block's doorstep below, leaving all of
## them with one sort position and the house drawn as a single object.

const TILESET := "res://Tilemaps/Terrains.tres"
const TEXTURE := "res://Assets/Buildings/Small_House.png"

## The sheet is a 3x3 grid of houses, each 64x64 -- four tiles on a side.
const HOUSE_TILES := Vector2i(4, 4)
const GRID := Vector2i(3, 3)

## The walls, measured off the art and given relative to the middle of the whole
## four-by-four block. The roof above them is left open so the player can walk
## behind the house instead of around it.
const BODY := Rect2(-24, 0, 48, 29)
## Where the house meets the ground, so a player below it draws in front and a
## player above it draws behind. Also measured from the middle of the block.
const SORT_ORIGIN := 29


func _initialize() -> void:
	var tile_set: TileSet = load(TILESET)
	if tile_set == null:
		push_error("No TileSet at " + TILESET)
		quit(1)
		return

	# Replace rather than stack, so re-running does not leave two copies. The id
	# is reused so cells already painted with these tiles keep resolving.
	var source_id := -1
	for i in tile_set.get_source_count():
		var id := tile_set.get_source_id(i)
		var existing := tile_set.get_source(id) as TileSetAtlasSource
		if existing and existing.texture and existing.texture.resource_path == TEXTURE:
			source_id = id
			tile_set.remove_source(id)
			print("replacing source ", id)
			break

	var source := TileSetAtlasSource.new()
	source.texture = load(TEXTURE)
	source.texture_region_size = tile_set.tile_size
	# Added before the tiles are cut: a tile's physics layers come from the
	# TileSet it belongs to, so a source off on its own has none to set.
	source_id = tile_set.add_source(source, source_id)

	var tile_size := tile_set.tile_size
	for row in GRID.y:
		for col in GRID.x:
			var origin := Vector2i(col * HOUSE_TILES.x, row * HOUSE_TILES.y)
			for ty in HOUSE_TILES.y:
				for tx in HOUSE_TILES.x:
					_cut(source, origin + Vector2i(tx, ty), Vector2i(tx, ty), tile_size)

	var err := ResourceSaver.save(tile_set, TILESET)
	print("tile size ", tile_size, ", physics layers ", tile_set.get_physics_layers_count())
	print("source ", source_id, " now holds ", source.get_tiles_count(),
			" tiles of ", tile_size, ", save -> ", err)
	quit()


## Cuts one cell of a house and gives it the slice of the wall collider that
## falls inside it. Cells above the walls -- the roof -- get no collider at all.
func _cut(source: TileSetAtlasSource, coords: Vector2i, local: Vector2i, tile_size: Vector2i) -> void:
	source.create_tile(coords)
	var data := source.get_tile_data(coords, 0)

	# Measured from the block's middle, so every cell of a block lands on the
	# same sort position and the house draws as one object.
	var centre := Vector2(local * tile_size) + Vector2(tile_size - HOUSE_TILES * tile_size) * 0.5
	data.y_sort_origin = int(SORT_ORIGIN - centre.y)

	# The part of the walls under this cell, moved from the block's middle to
	# this cell's own middle.
	var cell := Rect2(centre - Vector2(tile_size) * 0.5, Vector2(tile_size))
	var part := cell.intersection(BODY)
	if part.size.x <= 0.0 or part.size.y <= 0.0:
		return
	part.position -= centre
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(part.position.x, part.position.y),
		Vector2(part.end.x, part.position.y),
		Vector2(part.end.x, part.end.y),
		Vector2(part.position.x, part.end.y),
	]))
