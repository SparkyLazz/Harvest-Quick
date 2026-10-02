@tool
class_name NatureScatter
extends Node

## Sows the map with trees, bushes, flowers and lily pads.
##
## Runs once when the farm loads and puts everything in by hand, from a seed,
## so the same seed gives the same wood every time. Nothing is written into
## the scene file: a thousand decorations authored by hand would be a
## thousand nodes to load, re-read and merge every time the map changed, and
## the only thing they would say that this does not is which particular tile
## each one landed on.
##
## Generation happens before the player can see it and before [WorldObjects]
## takes its inventory of the map, so a scattered tree is a tile the player
## cannot build on and a thing the axe can be swung at — the same as a tree
## placed by hand. That is the whole reason decorations are [Placed] at all.
##
## It never sows the tile the player starts on, nor the ring around it. A
## farm that opens with the player wedged between two boulders is a bad
## first second.

## Emitted once everything is down, with how many things were sown.
signal sown(count: int)

@export_group("Wiring")
## Where sown things are parented. The y-sorted world layer.
@export var objects_path: NodePath = NodePath("../Objects")

## Which node to borrow the map's layer lists from.
##
## Borrowed rather than repeated, so there is one answer to "which layers are
## grass" and the generator cannot drift from the rules. Read as exported
## paths rather than through the node's own resolved lists, because in the
## editor that node has not run and its lists are still empty.
@export var farm_plots_path: NodePath = NodePath("../FarmPlots")

@export_group("Editor")
## Sow the map now, so a seed can be looked at before it is settled on.
## Previews are not owned by the scene and so are never saved into it.
@export_tool_button("Generate preview", "Reload") var _generate := _editor_generate

## Take a preview back off.
@export_tool_button("Clear preview", "Remove") var _clear := _editor_clear

## A new seed, and sow it. For rolling through layouts until one looks right.
@export_tool_button("Roll new seed", "RandomNumberGenerator") var _roll := _editor_roll

## The seed. Change it for a different wood; keep it and the farm is the same
## every time. Zero asks for a new one each run.
@export var random_seed: int = 20260930

## Turn the whole thing off without unwiring it.
@export var enabled: bool = true

@export_group("Kinds")
## Everything that can be sown. Each says what ground it wants and how often
## it should turn up.
@export var kinds: Array[NatureKind] = []

@export_group("Density")
## Share of eligible grass that gets something on it, from nothing to all.
@export_range(0.0, 1.0) var grass_density: float = 0.1
## Share of eligible water.
@export_range(0.0, 1.0) var water_density: float = 0.04
## Share of eligible shoreline.
@export_range(0.0, 1.0) var shore_density: float = 0.12

@export_group("Clearings")
## Tiles around the player's starting spot left bare.
@export var clear_radius: int = 5

## How far out to sea anything may be sown, in tiles from the nearest land.
## The outer bound of the band; [member water_margin] is the inner one.
##
## The sea is thirteen thousand tiles and nearly all of it is open water.
## Without this, reeds and lily pads spread evenly across the whole ocean —
## which is both wrong to look at and most of the work: the first run put
## four hundred and forty of them out of sight of the island.
@export var water_reach: int = 3

## How close to land a floating kind may come, in tiles.
##
## The sea tile against the shore is not open water. The shoreline is drawn
## across it — the pale lip of sand the land ends in — so a rock sown there
## sits on the beach rather than in the sea, and a lily pad laps over dry
## ground. A tile of clear water in between is what tells the eye the thing
## is floating.
@export var water_margin: int = 1

## How much of the map to leave open regardless, so the farm has somewhere to
## be. Nothing is sown on a tile whose neighbours are already crowded.
@export var max_neighbours: int = 2

## Tiles of clearance to leave along the edge of a height, for kinds that do
## not name a margin of their own.
##
## The lip of a hill is one tile drawn as two things: grass across the top
## and the cliff face falling away below it. A tree standing on that tile has
## its trunk in the rock, and a tree on the tile *above* a lip it is two
## tiles tall is no better. One tile of clearance means everything sown on a
## height stands on ground that is all there, with the drop beside it rather
## than under it.
##
## Measured in heights, not in grass: the tile under a lip has grass on it
## too, but it is the field below and the cliff is what is drawn between them.
@export var edge_margin: int = 1

const DECOR := preload("res://Scenes/World/Decoration.tscn")
const SWAYING := preload("res://Scenes/World/SwayingDecoration.tscn")

var _rng := RandomNumberGenerator.new()
var _grass: Array[TileMapLayer] = []
var _soil: Array[TileMapLayer] = []
var _sea: TileMapLayer

func _ready() -> void:
	# In the editor nothing is sown until a button asks for it: a generator
	# that ran on every scene load would fill the dock with scenery the
	# moment the file was opened.
	if Engine.is_editor_hint() or not enabled:
		return
	# After the whole tree is up, so the layers and the player are findable
	# and WorldObjects has not yet taken its inventory.
	await get_tree().process_frame
	sow()

func _editor_generate() -> void:
	sow()
	print("NatureScatter: seed %d" % random_seed)

func _editor_clear() -> void:
	clear()

func _editor_roll() -> void:
	random_seed = randi() % 100000000
	sow()
	print("NatureScatter: seed %d" % random_seed)

## Takes every sown thing back off the map.
func clear() -> void:
	var target := _objects()
	if target == null:
		return
	for child in target.get_children():
		if child is Decoration:
			target.remove_child(child)
			child.queue_free()

## Puts everything down. Safe to call again — it clears what it sowed first,
## which is what makes the seed and the densities worth rolling.
##
## Everything it needs about the map it works out itself: which layers are
## grass, where a tile sits in the world, how big a tile is. It cannot ask
## [WorldObjects] or [FarmPlots] for any of it, because in the editor neither
## has run and both still hold empty lists — and seeing a seed before the
## game is started is the whole point of the buttons.
func sow() -> void:
	var target := _objects()
	if target == null or kinds.is_empty():
		return
	_resolve_layers()
	if _grass.is_empty():
		push_warning("NatureScatter found no grass layers; nothing to sow.")
		return
	clear()
	_rng.seed = random_seed if random_seed != 0 else randi()

	var land := _land_tiles()
	var keep_clear := _around_player()
	var count := 0
	var taken: Dictionary[Vector2i, bool] = {}

	for ground in [NatureKind.On.WATER, NatureKind.On.SHORE, NatureKind.On.GRASS]:
		var choices := _kinds_for(ground)
		if choices.is_empty():
			continue
		var density := _density_for(ground)
		for tile in _tiles_for(ground, land):
			if keep_clear.has(tile) or taken.has(tile):
				continue
			if _rng.randf() > density:
				continue
			if _crowding(tile, taken) > max_neighbours:
				continue
			var kind := _pick(choices)
			if kind != null and _sow_one(kind, tile, target, land, taken):
				count += 1

	var world := get_tree().get_first_node_in_group("world_objects") as WorldObjects
	if world != null:
		world.adopt_scenery()
	sown.emit(count)

## Puts one [param kind] on [param tile]. Returns whether it went down.
func _sow_one(kind: NatureKind, tile: Vector2i, target: Node,
		land: Dictionary[Vector2i, bool], taken: Dictionary[Vector2i, bool]) -> bool:
	var span := Vector2i(maxi(kind.footprint.x, 1), maxi(kind.footprint.y, 1))
	# Off the edges first: it is a cheaper question than the ones below and
	# on a map this shaped it is the one that turns most tiles down.
	if kind.on == NatureKind.On.GRASS and not _inland(tile, span, kind.edge_margin):
		return false
	# Every tile it covers has to be free *and* the right ground. Checking
	# only the one it was seeded on is how trees came to stand in the sea: a
	# two-by-two seeded on the last grass tile of a shore grows its other
	# three squares out over the water.
	for x in span.x:
		for y in span.y:
			var cell := tile + Vector2i(x, y)
			if taken.has(cell) or _occupied(cell):
				return false
			if not _ground_suits(kind.on, cell, land):
				return false

	var node: Decoration
	if kind.moves():
		node = SWAYING.instantiate() as Decoration
	else:
		node = DECOR.instantiate() as Decoration
	if node == null:
		return false

	node.solid = kind.solid
	node.broken_by = kind.broken_by
	node.hits = kind.hits
	node.drops = kind.drops
	node.drop_counts = kind.drop_counts
	node.origin = tile
	# The map files it under every one of these, so a wide thing is found by
	# a swing at any part of it rather than only at its top-left corner.
	node.footprint = span
	target.add_child(node)
	# Across the middle of the footprint and on the bottom edge of its lowest
	# row, so a wide thing stands on the ground it occupies.
	node.global_position = (_tile_foot(tile + Vector2i(0, span.y - 1))
		+ Vector2(float(span.x - 1) * 8.0, 0.0))

	var swaying := node as SwayingDecoration
	if swaying != null:
		swaying.show_strip(kind.sheet, kind.region, kind.frames, kind.fps, _rng)
	else:
		node.show_art(kind.sheet, kind.region)

	for x in span.x:
		for y in span.y:
			taken[tile + Vector2i(x, y)] = true
	return true

## Whether [param tile] is the ground [param ground] asks for.
func _ground_suits(ground: NatureKind.On, tile: Vector2i,
		land: Dictionary[Vector2i, bool]) -> bool:
	if ground == NatureKind.On.WATER:
		return _open_water(tile, land)
	if ground == NatureKind.On.SHORE:
		return _shallows(tile, land)
	return _has_grass(tile)

## The tiles of each kind of ground.
func _tiles_for(ground: NatureKind.On, land: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match ground:
		NatureKind.On.GRASS:
			for layer in _grass:
				out.append_array(layer.get_used_cells())
		NatureKind.On.SHORE:
			if _sea != null:
				for cell in _sea.get_used_cells():
					if _shallows(cell, land):
						out.append(cell)
		NatureKind.On.WATER:
			if _sea != null:
				for cell in _sea.get_used_cells():
					if _open_water(cell, land):
						out.append(cell)
	return out

## Whether the ground at [param tile], and the [param margin] of tiles around
## the [param span] it covers, is all one height.
##
## A margin of -1 means the kind did not ask for one, so the scatter's own
## [member edge_margin] answers. Even at zero this is worth asking: it is
## what keeps a two-by-two tree from standing with half of itself on the hill
## and half on the field below.
func _inland(tile: Vector2i, span: Vector2i, margin: int) -> bool:
	var reach := maxi(margin if margin >= 0 else edge_margin, 0)
	var height := _height_at(tile)
	if height < 0:
		return false
	for x in range(-reach, span.x + reach):
		for y in range(-reach, span.y + reach):
			if _height_at(tile + Vector2i(x, y)) != height:
				return false
	return true

## Which height's grass is topmost on [param tile], or -1 where there is no
## grass at all. Topmost, because where a raised height overlaps the field
## below it only the top one is really there.
func _height_at(tile: Vector2i) -> int:
	for i in range(_grass.size() - 1, -1, -1):
		if _grass[i].get_cell_source_id(tile) != -1:
			return i
	return -1

func _has_grass(tile: Vector2i) -> bool:
	return _height_at(tile) >= 0

## Every tile with ground on it, as a set. Built once and asked many times —
## the alternative is a layer lookup per sea tile per neighbour, which runs
## to a third of a million of them.
func _land_tiles() -> Dictionary[Vector2i, bool]:
	var land: Dictionary[Vector2i, bool] = {}
	for layer in _soil:
		for cell in layer.get_used_cells():
			land[cell] = true
	return land

## Whether [param tile] is the shallows: sea, with land beside it.
##
## The water side of the line, not the grass side. Reeds and bulrushes are
## drawn standing in a puddle of their own and a rock meant for the shore is
## drawn wet, so both belong on the tile the shoreline runs across — the one
## that is half pale sand and half water. Sown a tile inland instead, a reed
## brings its puddle with it and stands in a pond in the middle of a field.
func _shallows(tile: Vector2i, land: Dictionary[Vector2i, bool]) -> bool:
	return not land.has(tile) and _near_land(tile, land, 1)

## Whether [param tile] is sea something may float on: far enough out that
## the shoreline is not drawn across it, near enough in to be worth drawing.
func _open_water(tile: Vector2i, land: Dictionary[Vector2i, bool]) -> bool:
	if land.has(tile):
		return false
	if water_margin > 0 and _near_land(tile, land, water_margin):
		return false
	return _near_land(tile, land, water_reach)

## Whether [param tile] has land within [param reach] tiles.
func _near_land(tile: Vector2i, land: Dictionary[Vector2i, bool], reach: int) -> bool:
	for dx in range(-reach, reach + 1):
		for dy in range(-reach, reach + 1):
			if land.has(tile + Vector2i(dx, dy)):
				return true
	return false

## How many of the eight tiles around [param tile] already have something.
func _crowding(tile: Vector2i, taken: Dictionary[Vector2i, bool]) -> int:
	var n := 0
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if taken.has(tile + Vector2i(dx, dy)):
				n += 1
	return n

## Whether something already stands on [param tile]. In the editor the map
## has taken no inventory, so there is nothing to ask and nothing is there.
func _occupied(tile: Vector2i) -> bool:
	var world := get_tree().get_first_node_in_group("world_objects") as WorldObjects
	return world != null and world.at(tile) != null

## The tiles to leave bare around wherever the player begins.
func _around_player() -> Dictionary[Vector2i, bool]:
	var bare: Dictionary[Vector2i, bool] = {}
	if clear_radius <= 0:
		return bare
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		var target := _objects()
		if target != null:
			player = target.get_node_or_null("Player") as Node2D
	if player == null:
		return bare
	var here := _tile_at(player.global_position)
	for dx in range(-clear_radius, clear_radius + 1):
		for dy in range(-clear_radius, clear_radius + 1):
			bare[here + Vector2i(dx, dy)] = true
	return bare

func _kinds_for(ground: NatureKind.On) -> Array[NatureKind]:
	var out: Array[NatureKind] = []
	for kind in kinds:
		if kind != null and kind.on == ground and kind.weight > 0.0:
			out.append(kind)
	return out

func _density_for(ground: NatureKind.On) -> float:
	if ground == NatureKind.On.WATER:
		return water_density
	if ground == NatureKind.On.SHORE:
		return shore_density
	return grass_density

## One kind, by weight.
func _pick(choices: Array[NatureKind]) -> NatureKind:
	var total := 0.0
	for kind in choices:
		total += kind.weight
	if total <= 0.0:
		return null
	var roll := _rng.randf() * total
	for kind in choices:
		roll -= kind.weight
		if roll <= 0.0:
			return kind
	return choices.back()

func _objects() -> Node2D:
	return get_node_or_null(objects_path) as Node2D

## Follows the map's own layer lists, read off [FarmPlots] as exported paths
## so they answer before that node has run.
func _resolve_layers() -> void:
	_grass.clear()
	_soil.clear()
	_sea = null
	var plots := get_node_or_null(farm_plots_path)
	if plots == null:
		return
	for path in plots.grass_layers:
		var layer := plots.get_node_or_null(path) as TileMapLayer
		if layer != null:
			_grass.append(layer)
	for path in plots.soil_layers:
		var layer := plots.get_node_or_null(path) as TileMapLayer
		if layer != null:
			_soil.append(layer)
	var target := _objects()
	if target != null:
		_sea = target.get_node_or_null("../Sea Layer") as TileMapLayer

func _tile_at(global_pos: Vector2) -> Vector2i:
	if _grass.is_empty():
		return Vector2i.ZERO
	var layer := _grass[0]
	return layer.local_to_map(layer.to_local(global_pos))

## The bottom edge of [param tile], where a thing standing on it belongs.
func _tile_foot(tile: Vector2i) -> Vector2:
	if _grass.is_empty():
		return Vector2.ZERO
	var layer := _grass[0]
	var half := float(layer.tile_set.tile_size.y) * 0.5
	return layer.to_global(layer.map_to_local(tile)) + Vector2(0.0, half)
