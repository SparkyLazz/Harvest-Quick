class_name WorldCollision
extends RefCounted

## Derives the world's blocking cells from the terrain layers and bakes them
## into the invisible "Collision" TileMapLayer.
##
## Collision is kept off the painted terrain tiles on purpose. "Sea Layer" is a
## solid rectangle of one water tile that runs underneath the land, so giving
## that tile a shape in the TileSet would solidify the whole map. Instead the
## TileSet carries an art-free source (17) holding 16 collision variants, and
## this pass paints the variant matching each cell's walls.
##
## Walls are thin strips on the boundary between the two regions rather than
## full tiles, so the player can walk right up to the cliff edge and the
## shoreline instead of stopping a tile short.

## The art-free source in Terrains.tres holding the collision variants.
const COLLISION_SOURCE := 17
## Source id of the staircase tiles inside "Height 1", which must stay open.
const STAIR_SOURCE := 16

## Which side of a cell a wall sits on. The variant's atlas coordinate is the
## mask itself, laid out as a 4x4 grid: Vector2i(mask % 4, mask / 4).
const WALL_NORTH := 1
const WALL_SOUTH := 2
const WALL_WEST := 4
const WALL_EAST := 8

const SIDES: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const SIDE_BITS: Array[int] = [WALL_NORTH, WALL_SOUTH, WALL_WEST, WALL_EAST]

## How deep a wall reaches into its cell, in pixels. The player covers about
## 1.7px per physics frame at run speed, so this has plenty of margin against
## tunnelling; raise it if movement ever gets much faster.
const WALL_THICKNESS := 4.0
const TILE_HALF := 8.0

const N8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


## The wall strips for one mask, in tile-local coordinates.
static func wall_polygons(mask: int, thickness: float = WALL_THICKNESS) -> Array[PackedVector2Array]:
	var h := TILE_HALF
	var t := thickness
	var polys: Array[PackedVector2Array] = []
	if mask & WALL_NORTH:
		polys.append(PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, -h + t), Vector2(-h, -h + t)]))
	if mask & WALL_SOUTH:
		polys.append(PackedVector2Array([Vector2(-h, h - t), Vector2(h, h - t), Vector2(h, h), Vector2(-h, h)]))
	if mask & WALL_WEST:
		polys.append(PackedVector2Array([Vector2(-h, -h), Vector2(-h + t, -h), Vector2(-h + t, h), Vector2(-h, h)]))
	if mask & WALL_EAST:
		polys.append(PackedVector2Array([Vector2(h - t, -h), Vector2(h, -h), Vector2(h, h), Vector2(h - t, h)]))
	return polys


## Rewrites the 16 collision variants in the TileSet. Call this after changing
## WALL_THICKNESS, then save the TileSet resource.
static func rebuild_tile_shapes(tile_set: TileSet, thickness: float = WALL_THICKNESS) -> bool:
	var source := tile_set.get_source(COLLISION_SOURCE) as TileSetAtlasSource
	if source == null:
		push_error("WorldCollision: source %d is not an atlas source." % COLLISION_SOURCE)
		return false
	for mask in 16:
		var data := source.get_tile_data(Vector2i(mask % 4, mask / 4), 0)
		var polys := wall_polygons(mask, thickness)
		data.set_collision_polygons_count(0, polys.size())
		for i in polys.size():
			data.set_collision_polygon_points(0, i, polys[i])
	return true


## Maps each blocking cell to its wall mask, given the two terrain layers.
## Cells that need no wall are left out.
static func compute_walls(height_0: TileMapLayer, height_1: TileMapLayer) -> Dictionary:
	var land := {}
	for cell in height_0.get_used_cells():
		land[cell] = true

	var plateau := {}
	var stairs := {}
	for cell in height_1.get_used_cells():
		plateau[cell] = true
		if height_1.get_cell_source_id(cell) == STAIR_SOURCE:
			stairs[cell] = true

	var walls := {}

	# Shoreline. The blocking cell is water, so its wall sits on the sides that
	# face land — right on the land/water boundary.
	for cell in land:
		for offset in N8:
			var side: Vector2i = cell + offset
			if land.has(side):
				continue
			var mask := 0
			for i in SIDES.size():
				if land.has(side + SIDES[i]):
					mask |= SIDE_BITS[i]
			if mask != 0:
				walls[side] = int(walls.get(side, 0)) | mask

	# Cliff. The blocking cell is walkable plateau, so its wall sits on the
	# sides that face off the plateau, letting the player stand on the edge
	# tile. The staircase and its mouth are left open.
	var open := {}
	for cell in stairs:
		open[cell] = true
		for offset in N8:
			open[cell + offset] = true

	for cell in plateau:
		if open.has(cell):
			continue
		var mask := 0
		for i in SIDES.size():
			if not plateau.has(cell + SIDES[i]):
				mask |= SIDE_BITS[i]
		if mask != 0:
			walls[cell] = int(walls.get(cell, 0)) | mask

	return walls


## Repaints the "Collision" layer under `root`. Returns the cell count, or -1
## if the expected layers are missing.
static func rebuild(root: Node) -> int:
	var height_0 := root.get_node_or_null("Height 0") as TileMapLayer
	var height_1 := root.get_node_or_null("Height 1") as TileMapLayer
	var collision := root.get_node_or_null("Collision") as TileMapLayer
	if height_0 == null or height_1 == null or collision == null:
		push_error("WorldCollision: expected 'Height 0', 'Height 1' and 'Collision' layers.")
		return -1

	collision.clear()
	var walls := compute_walls(height_0, height_1)
	for cell in walls:
		var mask: int = walls[cell]
		collision.set_cell(cell, COLLISION_SOURCE, Vector2i(mask % 4, mask / 4))
	return collision.get_used_cells().size()
