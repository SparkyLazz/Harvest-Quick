class_name WorldObjects
extends Node2D

## Everything the player has set down, and the rules about where it may go.
##
## This is the y-sorted layer the player walks in, so a chest north of the
## player draws behind them and one south of them draws in front. That only
## works because every node in here — the player included — puts its origin
## at the bottom edge of the tile it stands on; Godot sorts by that point and
## nothing else.
##
## The tiles are the map's, but which of them are spoken for is not something
## a [TileMapLayer] can answer, so that is kept here in [member _occupied].
## It maps every tile a thing covers to the thing itself, not just the tile
## it was dropped on, so a two-by-two shed blocks four entries and any of the
## four finds it again.
##
## The land is one region and the player chooses what each tile in it is for:
## a crop plot may be planted or built on, and nothing outside the region is
## either. Covering a plot does not cost it — placing never writes to a
## [TileMapLayer], so the plot is still underneath and taking the thing back
## up uncovers it. That is the whole reason recovery is not optional: without
## it, a chest set down on a plot really would be the end of that plot, since
## the player has no way to till new ground.
##
## Reached with get_tree().get_first_node_in_group("world_objects").

## Emitted when something is set down, with the thing and the tile it landed
## on.
signal placed(node: Node2D, at: Vector2i)
## Emitted when something is taken back up, with the tile it left.
signal removed(at: Vector2i)

## Layers whose tiles count as ground. A tile on any one of them is somewhere
## a thing could stand, which is what lets the raised ground be built up out
## of several layers without this needing to know how they relate.
##
## Paths rather than the layers themselves: Godot resolves an exported node
## reference back into a node only when it stands alone, and an array of them
## stays an array of paths, so the conversion has to happen here.
@export var ground_layers: Array[NodePath] = []

## Layers marking the player's own land. Nothing may be planted or placed
## outside it, however good the ground looks.
##
## Left blank, the whole map counts as the player's — which is what a farm
## that is all farm wants, and means the boundary only has to be drawn once
## there is somewhere that is not the farm. The catch worth knowing: painting
## a single tile turns the rule on everywhere at once, so the region is drawn
## whole or not at all.
@export var region_layers: Array[NodePath] = []

## What sits on each spoken-for tile.
var _occupied: Dictionary[Vector2i, Node2D] = {}

var _ground: Array[TileMapLayer] = []
var _region: Array[TileMapLayer] = []

func _ready() -> void:
	add_to_group("world_objects")
	y_sort_enabled = true
	_ground = _resolve(ground_layers)
	_region = _resolve(region_layers)

## The layers [param paths] point at, skipping any that are missing or are
## not layers — a path left dangling by a rename should cost that one layer,
## not every rule that consults the list.
func _resolve(paths: Array[NodePath]) -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	for path in paths:
		if path.is_empty():
			continue
		var layer := get_node_or_null(path) as TileMapLayer
		if layer != null:
			layers.append(layer)
	return layers

## The tile containing [param global_pos].
##
## Any layer would do — they share a grid — so the first ground layer is used
## as the one that answers for all of them. With no layers set there is no
## grid to speak of, and the origin tile is as good an answer as any.
func tile_at(global_pos: Vector2) -> Vector2i:
	var layer := _reference_layer()
	if layer == null:
		return Vector2i.ZERO
	return layer.local_to_map(layer.to_local(global_pos))

## How big one tile is, in pixels. Sixteen, unless the tileset is swapped
## for one that says otherwise — which is why this is asked rather than
## written down in the half-dozen places that need it.
func tile_size() -> Vector2:
	var layer := _reference_layer()
	if layer == null:
		return Vector2(16.0, 16.0)
	return Vector2(layer.tile_set.tile_size)

## Where the middle of [param tile] is, in global space.
func tile_centre(tile: Vector2i) -> Vector2:
	var layer := _reference_layer()
	if layer == null:
		return Vector2.ZERO
	return layer.to_global(layer.map_to_local(tile))

## Where a thing standing on [param tile] puts its origin: the bottom edge,
## so that it sorts against the player correctly.
func tile_foot(tile: Vector2i) -> Vector2:
	var layer := _reference_layer()
	if layer == null:
		return Vector2.ZERO
	return tile_centre(tile) + Vector2(0.0, tile_size().y * 0.5)

## Whether [param tile] is part of the player's own land.
##
## A region with no tiles on it means the whole map is theirs, so the
## boundary is something the farm grows into rather than something it cannot
## open without. Note that this asks whether anything is painted, not whether
## a layer was assigned: a layer sitting there blank is a farm whose edge has
## not been drawn yet, which is not the same as a farm with no edge.
func in_region(tile: Vector2i) -> bool:
	if not _region_painted():
		return true
	return _any_layer_has(_region, tile)

## Whether the region has been drawn at all.
##
## Asked rather than remembered, because [method TileMapLayer.get_used_rect]
## is already kept up to date by the layer and a flag cached here would go
## stale the moment anything painted the region while the game ran.
func _region_painted() -> bool:
	for layer in _region:
		if layer.get_used_rect().has_area():
			return true
	return false

## Whether [param placeable] may be set down with its corner on [param
## origin].
func can_place(placeable: PlaceableData, origin: Vector2i) -> bool:
	if placeable == null or placeable.scene == null:
		return false
	var plots := get_tree().get_first_node_in_group("farm_plots")
	for tile in placeable.tiles_from(origin):
		if not _tile_allows(placeable.surface, tile):
			return false
		if _occupied.has(tile):
			return false
		# Same rule as the hoe: a thing is set down on the ground the player
		# is standing on, not on the clifftop a step away from their head.
		if plots != null and not plots.reachable(tile):
			return false
	return true

## Sets [param placeable] down with its corner on [param origin], or returns
## null if it may not go there. The caller is the one that takes it out of
## the satchel — this does not reach into the inventory, so the same call
## works for loading a saved farm, where nothing was carried in the first
## place.
func place(placeable: PlaceableData, origin: Vector2i) -> Node2D:
	if not can_place(placeable, origin):
		return null
	var node := placeable.scene.instantiate() as Node2D
	if node == null:
		return null
	node.global_position = tile_foot(origin) - Vector2(0.0, placeable.sort_lift)
	add_child(node)
	# Filed under every tile it covers, so aiming at any part of a wide thing
	# finds the whole of it.
	for tile in placeable.tiles_from(origin):
		_occupied[tile] = node
	if node.has_method("placed_as"):
		node.placed_as(placeable, origin)
	placed.emit(node, origin)
	return node

## What stands on [param tile], or null.
func at(tile: Vector2i) -> Node2D:
	return _occupied.get(tile)

## Takes whatever is on [param tile] back out of the world, freeing every
## tile it covered. Returns what was there, already removed from the tree but
## not yet freed, so the caller can read what it was before letting it go.
func remove(tile: Vector2i) -> Node2D:
	var node: Node2D = _occupied.get(tile)
	if node == null:
		return null
	# Found by value rather than by recomputing the footprint: the thing may
	# have been placed by something that knew a different footprint, and the
	# tiles it actually holds are the ones that must be let go.
	for held in _occupied.keys():
		if _occupied[held] == node:
			_occupied.erase(held)
	remove_child(node)
	removed.emit(tile)
	return node

## Whether [param tile] is the kind of ground [param surface] asks for.
func _tile_allows(surface: PlaceableData.Surface, tile: Vector2i) -> bool:
	if not in_region(tile):
		return false
	match surface:
		PlaceableData.Surface.GROUND:
			return _any_layer_has(_ground, tile)
		PlaceableData.Surface.FARM:
			# Bare soil: ground the hoe has been over. Asked of [FarmPlots],
			# which owns what is grass and what is not, rather than kept
			# here as a layer — there is no such thing as a farm layer any
			# more, only ground with the grass off it.
			var plots := get_tree().get_first_node_in_group("farm_plots")
			if plots == null:
				return false
			return plots.is_plot(tile) and not plots.is_overgrown(tile)
		PlaceableData.Surface.WATER:
			return not _any_layer_has(_ground, tile)
	return false

func _any_layer_has(layers: Array[TileMapLayer], tile: Vector2i) -> bool:
	for layer in layers:
		if layer != null and layer.get_cell_source_id(tile) != -1:
			return true
	return false

func _reference_layer() -> TileMapLayer:
	for layer in _ground:
		if layer != null and layer.tile_set != null:
			return layer
	return null
