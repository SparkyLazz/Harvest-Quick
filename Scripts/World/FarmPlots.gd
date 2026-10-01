class_name FarmPlots
extends Node

## The ground, and the grass growing on it.
##
## Every height in the map is two layers: soil, and grass lying on top of it.
## The hoe cuts a hole in the grass and the soil that was always underneath
## shows through. That is the whole mechanism — there is no third layer, no
## overlay, and nothing is drawn that the artist did not paint.
##
## Which means the edges come out right for free. The grass is already
## painted as terrain, so Godot knows how a patch of it should end; erasing a
## cell and handing its neighbours back to the terrain solver produces the
## fringed border in exactly the art the rest of the map is drawn in.
##
## Nothing here assumes one height or one grass. A tile is soil if any soil
## layer has it, grassed if any grass layer has it, and cutting finds the
## topmost grass covering the spot — so a hill drawn in one grass and the
## field below it drawn in another both work, and so would a third height
## added later.
##
## The terrain to reconnect with is read off the tiles already there rather
## than configured, because the map mixes several grasses and the right
## answer is always "whatever the neighbours are".
##
## The layers are written to while the game runs. That is only a cost on
## paper: nothing here saves, so the scene on disk is untouched.
##
## Reached with get_tree().get_first_node_in_group("farm_plots").

## Emitted when the hoe cuts a tile, uncovering soil.
signal cleared(tile: Vector2i)
## Emitted when grass takes a tile back.
signal overgrown(tile: Vector2i)

## The soil of each height, lowest first. Never written to.
##
## Paths rather than the layers themselves: Godot resolves an exported node
## reference back into a node only when it stands alone, and an array of them
## stays an array of paths.
@export var soil_layers: Array[NodePath] = []

## The grass of each height, in the same order. The hoe cuts these.
##
## Index is height, and that is the whole point of keeping two lists rather
## than one pile of layers. Where a raised height overlaps the ground below
## it, only the top one is really there to be seen or dug; asking "is there
## grass anywhere here" would find the buried height's grass and answer for
## a place the player cannot reach.
@export var grass_layers: Array[NodePath] = []

@export_group("Grass")
## The terrain to regrow in when there is no grass left nearby to copy —
## only reached on a tile whose neighbours were all cut too.
@export var terrain_set: int = 0
@export var fallback_terrain: int = 7

## The tile to fall back on when the terrain solver has nothing to offer.
##
## Godot picks a tile by how its neighbours connect and leaves the cell
## *empty* when the terrain has no tile for that arrangement. The Grass 2
## terrains in this tileset have 45 of the 47 a corners-and-sides set needs,
## because Grass_Tile_layers2.png is one column narrower than its siblings
## and that column carried the missing pair. Two arrangements in every 47
## therefore delete grass instead of drawing it, and since cutting a tile
## asks its neighbours to redraw, one such hole spreads into the next.
##
## Rather than let a field quietly eat itself, any cell the solver abandons
## is given plain grass — the wrong tile for those two arrangements, and a
## far smaller wrong than the alternative.
@export var fallback_source: int = 6
@export var fallback_atlas: Vector2i = Vector2i(1, 6)

@export_group("Soil")
## Give each square of hoed soil its own scuffing.
##
## Both soil sheets carry ten loose tiles apiece — plain fill with the specks
## and clods arranged differently — that the map never uses, because terrain
## painting only ever reaches for the one tile meaning "middle of the field".
## Turned on, the hoe picks among them, so a worked row reads as ground
## rather than as one texture stamped over and over.
@export var vary_soil: bool = true

@export_group("Regrowth")
## Days a cut tile stays bare before the grass comes back. Zero turns
## regrowth off entirely.
@export var days_until_regrowth: int = 2

## The eight neighbours a square tile can peer at.
const PEERING_BITS: Array[int] = [
	TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, TileSet.CELL_NEIGHBOR_TOP_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, TileSet.CELL_NEIGHBOR_LEFT_SIDE,
]

var _soil: Array[TileMapLayer] = []
var _grass: Array[TileMapLayer] = []

## How many days each bare tile has gone unplanted.
var _bare_days: Dictionary[Vector2i, int] = {}
## Which grass layer each bare tile was cut out of, so it grows back into the
## same one at the same height rather than onto whatever is topmost now.
var _cut_from: Dictionary[Vector2i, int] = {}
## And in which terrain, remembered before the evidence was erased.
var _cut_terrain: Dictionary[Vector2i, int] = {}

## The loose tiles each sheet has to offer, found the first time it is asked.
var _variants: Dictionary[int, Array] = {}

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("farm_plots")
	_rng.randomize()
	_soil = _resolve(soil_layers)
	_grass = _resolve(grass_layers)
	if _soil.is_empty() or _grass.is_empty():
		push_warning("FarmPlots has no soil or no grass layers; the hoe will do nothing.")
		return
	_listen()

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

## Which height [param tile] belongs to — the highest whose soil is there —
## or -1 where there is no ground at all.
func height_at(tile: Vector2i) -> int:
	for i in range(_soil.size() - 1, -1, -1):
		if _soil[i].get_cell_source_id(tile) != -1:
			return i
	return -1

## The grass layers, already followed. For anything that needs to walk the
## map rather than ask about one tile of it.
func grass_layers_resolved() -> Array[TileMapLayer]:
	return _grass

## The soil layers, likewise.
func soil_layers_resolved() -> Array[TileMapLayer]:
	return _soil

## Whether [param tile] has bare ground under it at all.
func is_plot(tile: Vector2i) -> bool:
	return height_at(tile) >= 0

## Whether grass is lying on [param tile], on the height the tile belongs to.
func is_overgrown(tile: Vector2i) -> bool:
	var grass := _grass_at(tile)
	return grass != null and grass.get_cell_source_id(tile) != -1

## The grass belonging to [param tile]'s height, or null.
func _grass_at(tile: Vector2i) -> TileMapLayer:
	var height := height_at(tile)
	if height < 0 or height >= _grass.size():
		return null
	return _grass[height]

## Whether a crop could go in [param tile]: soil, cut clear, on the player's
## land, and with nothing standing on it.
##
## The last two are asked of [WorldObjects] rather than tracked here, because
## a chest covering a tile is the same fact as a chest covering any other
## tile and there is no reason for two places to know it.
func can_plant(tile: Vector2i) -> bool:
	if not is_plot(tile) or is_overgrown(tile):
		return false
	var world := _world()
	if world == null:
		return true
	return world.in_region(tile) and world.at(tile) == null

## Whether the hoe would do anything to [param tile]: soil under it, grass on
## it, and on the player's land.
func can_clear(tile: Vector2i) -> bool:
	if not is_plot(tile) or not is_overgrown(tile):
		return false
	if not reachable(tile):
		return false
	var world := _world()
	return world == null or world.in_region(tile)

## Whether [param tile] is on the same height as whoever is working it.
##
## Answered against the player, because the player is the only thing that
## works tiles; with nobody in the scene every height is reachable, which is
## what a test with no player wants.
func reachable(tile: Vector2i) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return true
	return height_at(tile) == height_at(tile_of(player.global_position))

## Cuts the topmost grass off [param tile], uncovering what is beneath.
## Returns whether there was any to cut, so a hoe swung at bare soil reads as
## a miss rather than a success.
func clear(tile: Vector2i) -> bool:
	if not can_clear(tile):
		return false
	var index := height_at(tile)
	var layer := _grass[index]
	_cut_from[tile] = index
	_cut_terrain[tile] = _terrain_at(layer, tile)
	# Painted as "no terrain" rather than erased. Both leave the cell empty,
	# but only this tells the solver to redraw what is now beside a hole.
	# Erasing by hand and asking the neighbours to reconnect does not: they
	# are repainted as a piece of unbroken field, and meet the bare soil with
	# no edge at all. Measured, not guessed — erasing left four neighbours
	# per hole still claiming the grass ran on into it.
	layer.set_cells_terrain_connect([tile], terrain_set, -1)
	if vary_soil:
		_vary_soil(tile, index)
	_bare_days[tile] = 0
	cleared.emit(tile)
	return true

## Grows grass back over [param tile], into the layer it was cut from.
func overgrow(tile: Vector2i) -> bool:
	if not is_plot(tile) or is_overgrown(tile):
		return false
	var index: int = _cut_from.get(tile, -1)
	if index < 0 or index >= _grass.size():
		return false
	_grow(_grass[index], [tile], _cut_terrain.get(tile, fallback_terrain))
	_forget(tile)
	overgrown.emit(tile)
	return true

## Ages every bare tile by a day and grows over the ones left too long.
##
## Driven by the clock rather than a timer of its own, so the ground's
## patience is measured in the same days the player is counting.
func advance_day() -> void:
	if days_until_regrowth <= 0:
		return
	var due: Array[Vector2i] = []
	for tile in _bare_days:
		# A tile with a crop in it is being used, so the grass stays off.
		# Nothing grows yet, which is why this only asks about the tile.
		_bare_days[tile] += 1
		if _bare_days[tile] >= days_until_regrowth:
			due.append(tile)
	if due.is_empty():
		return
	# Grouped by layer and terrain so each batch is one call the solver can
	# settle as a whole, instead of a tile at a time each fighting the last.
	var batches: Dictionary = {}
	for tile in due:
		var key := "%d:%d" % [_cut_from.get(tile, -1), _cut_terrain.get(tile, fallback_terrain)]
		if not batches.has(key):
			batches[key] = []
		batches[key].append(tile)
	for key in batches:
		var parts := (key as String).split(":")
		var index := int(parts[0])
		if index < 0 or index >= _grass.size():
			continue
		var tiles: Array[Vector2i] = []
		tiles.assign(batches[key])
		_grow(_grass[index], tiles, int(parts[1]))
		for tile in tiles:
			_forget(tile)
			overgrown.emit(tile)

## The terrain the tile at [param tile] is painted in, or the fallback when
## there is nothing there to ask.
func _terrain_at(layer: TileMapLayer, tile: Vector2i) -> int:
	var source_id := layer.get_cell_source_id(tile)
	if source_id == -1:
		return fallback_terrain
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return fallback_terrain
	var data := source.get_tile_data(
		layer.get_cell_atlas_coords(tile), layer.get_cell_alternative_tile(tile))
	if data == null or data.terrain_set != terrain_set or data.terrain < 0:
		return fallback_terrain
	return data.terrain

## Paints [param tiles] as terrain and puts back anything the solver dropped.
##
## The solver may redraw tiles beyond the ones it was handed, so what counts
## as dropped is worked out over those neighbours too. [param hole] is the
## tile that was just cut, if any — the one cell that is meant to come out,
## and so must not be put back.
func _grow(layer: TileMapLayer, tiles: Array[Vector2i], terrain: int,
		hole: Vector2i = Vector2i.MAX) -> void:
	if tiles.is_empty():
		return
	var watched: Dictionary[Vector2i, bool] = {}
	for tile in tiles:
		for near in _around(tile):
			if near != hole and layer.get_cell_source_id(near) != -1:
				watched[near] = true
	# ignore_empty_terrains is false on purpose. Left at its default of true,
	# the solver treats an empty neighbour as "no opinion" and happily draws
	# a middle-of-the-field tile next to the hole the hoe just made — grass
	# with no edge, butting flat against bare soil. False makes empty mean
	# "not grass", which is what a hole is, and the fringed border follows.
	layer.set_cells_terrain_connect(tiles, terrain_set, terrain, false)
	for tile in tiles:
		watched[tile] = true
	for tile in watched:
		if tile != hole and layer.get_cell_source_id(tile) == -1:
			layer.set_cell(tile, fallback_source, fallback_atlas)

## Swaps the soil uncovered at [param tile] for another of the same sheet's
## loose tiles.
##
## Only a middle-of-the-field tile is ever swapped. An edge or a corner is
## carrying the shape of the field's boundary and would be ruined by a
## replacement chosen for its specks, whereas a full-centre tile carries
## nothing but its own texture, so any of them will do. That one test also
## keeps this away from sheets like the hill slopes, whose tiles belong to no
## terrain and so are never centres.
func _vary_soil(tile: Vector2i, height: int) -> void:
	if height < 0 or height >= _soil.size():
		return
	var layer := _soil[height]
	var source_id := layer.get_cell_source_id(tile)
	if source_id == -1:
		return
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return
	var here := source.get_tile_data(
		layer.get_cell_atlas_coords(tile), layer.get_cell_alternative_tile(tile))
	if here == null or not _is_field_centre(here):
		return
	var choices: Array = _loose_tiles(source_id, source)
	if choices.is_empty():
		return
	layer.set_cell(tile, source_id, choices[_rng.randi_range(0, choices.size() - 1)])

## The tiles of [param source] belonging to no terrain — the loose decoration
## a terrain paint would never reach for.
func _loose_tiles(source_id: int, source: TileSetAtlasSource) -> Array:
	if _variants.has(source_id):
		return _variants[source_id]
	var loose: Array[Vector2i] = []
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		if data != null and data.terrain < 0:
			loose.append(coords)
	_variants[source_id] = loose
	return loose

## Whether [param data] is the tile a terrain uses for the middle of an
## unbroken area: its own terrain on all eight sides.
func _is_field_centre(data: TileData) -> bool:
	# Asked first, and not only for speed: a tile belonging to no terrain has
	# no valid peering bits to read, and reading them anyway is an error.
	if data.terrain < 0:
		return false
	for bit in PEERING_BITS:
		if data.get_terrain_peering_bit(bit) != data.terrain:
			return false
	return true

## The eight tiles touching [param tile].
func _around(tile: Vector2i) -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				near.append(tile + Vector2i(dx, dy))
	return near

func _forget(tile: Vector2i) -> void:
	_bare_days.erase(tile)
	_cut_from.erase(tile)
	_cut_terrain.erase(tile)

## Hooks up to the swing and to the clock, tolerating either being absent —
## the farm scene has both, but a test scene with only ground in it should
## still load.
func _listen() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("tool_used"):
		player.tool_used.connect(_on_tool_used)
	var clock := get_tree().get_first_node_in_group("day_night")
	if clock != null and clock.has_signal("day_passed"):
		clock.day_passed.connect(func(_day: int) -> void: advance_day())

## The hoe, and only the hoe, cuts grass. Anything else swung at the ground
## is somebody else's business.
##
## The swing has to land on the height the player is standing on. Reach is
## measured in pixels and the map is drawn in flat tiles, so a tile one step
## north of someone at the foot of a cliff is within arm's length on screen
## while being the top of the cliff in the world — and without this, the hoe
## happily cut the plateau's grass from the ground below it.
func _on_tool_used(action: StringName, at: Vector2) -> void:
	if action != &"hoe" or _grass.is_empty():
		return
	clear(tile_of(at))

## The tile containing [param global_pos]. Any layer would do, since they all
## share a grid.
func tile_of(global_pos: Vector2) -> Vector2i:
	var layer := _grass[0]
	return layer.local_to_map(layer.to_local(global_pos))

func _world() -> WorldObjects:
	return get_tree().get_first_node_in_group("world_objects") as WorldObjects
