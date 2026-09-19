class_name WorldGenerator
extends Node2D

## Procedural archipelago: one island per forest biome, joined by wooden bridges.
##
## Each island is a noise-shaped blob around its own centre, and the biomes are
## separated by water rather than by a noise contour -- a border the player can
## actually read. Bridges are placed along a spanning tree over the islands, so
## every biome is reachable on every seed.
##
## Ground is painted through Godot terrain sets, so the 47-blob autotiling picks
## every edge tile; nothing here chooses an atlas coordinate for ground by hand.
##
## Soil is the base material and grass sits on top of it, the way the pack's own
## "TILE LAYER EXAMPLE.png" stacks them. Which sheet a material uses depends on
## what its edge means: soil's rim carries a white surf line, so it reads as a
## shoreline; stone uses the hills sheet, whose rim has no surf and reads as a
## drop onto land. See the notes in Tools/BuildTerrains.gd.
##
## Layer order, bottom to top:
##   Water -> Soil -> Cherry/Birch/Pine -> MountainFace -> MountainTop
##        -> Bridges -> WaterPlants -> Decorations

enum Biome { CHERRY, BIRCH, PINE, MOUNTAIN }

## Terrain set indices, in the order Tools/BuildTerrains.gd creates them.
const TERRAIN_SOIL := 0
const TERRAIN_STONE := 1
const TERRAIN_CHERRY := 2
const TERRAIN_BIRCH := 3
const TERRAIN_PINE := 4
const TERRAIN_FARMLAND_WET := 5

const SRC_WATER := 0
const SRC_BRIDGE := 17
const SRC_FARMLAND_WET := 6
## The blob's fully-surrounded tile -- flat soil with no rim on any side.
const FARMLAND_WET_FILL := Vector2i(1, 1)

## Water alternatives, in the order Tools/BuildTerrains.gd creates them.
const WATER_SEA := 0
const WATER_UNDER_LAND := 1

## Bridge atlas cells: a cap at each end and a repeatable middle.
##
## A bridge is one tile wide. The sheet's second row and column look like the
## other half of a two-wide bridge but are really the same bridge shifted half a
## tile -- alignment variants. Placing them as halves draws two parallel bridges
## with a strip of water down the middle.
const BRIDGE_V := {"cap_a": Vector2i(0, 0), "middle": Vector2i(0, 1), "cap_b": Vector2i(0, 2)}
const BRIDGE_H := {"cap_a": Vector2i(2, 0), "middle": Vector2i(3, 0), "cap_b": Vector2i(4, 0)}

## One island per forest biome. The mountain isn't in this list: it is a raised
## region inside the pine island, not an island of its own. An island of stone
## would meet water at its rim, which would force the surf-lined flat sheet and
## read as a rocky islet at sea level rather than a peak.
const ISLAND_BIOMES := [Biome.CHERRY, Biome.BIRCH, Biome.PINE]
const MOUNTAIN_HOST := Biome.PINE

const DECOR_SOURCE := {
	Biome.CHERRY: 10,
	Biome.BIRCH: 11,
	Biome.PINE: 12,
}
const PLANT_SOURCE := {
	Biome.CHERRY: 13,
	Biome.BIRCH: 14,
	Biome.PINE: 15,
}

const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

@export_group("World")
@export var player_path: NodePath = ^"Player"
@export var world_size := Vector2i(128, 128)
@export var world_seed: int = 0
## Regenerate from the inspector by ticking this in a running scene.
@export var regenerate: bool = false:
	set(value):
		regenerate = false
		if is_inside_tree():
			generate()

@export_group("Islands")
## Distance between the centres of two neighbouring islands.
##
## This and the radius have to be tuned against each other: the falloff means
## land stops well short of `island_radius` -- around 0.57 of it at the default
## strength -- so islands sit much further apart than the raw numbers suggest.
## Push them apart and the gap outruns `bridge_max_length` and no crossing can
## be found at all; pull them together and they merge into one landmass.
@export var island_spacing: float = 44.0
## Radius of a single island before noise roughens its coast.
@export var island_radius: float = 32.0
## Water kept clear between neighbouring islands, in tiles. This is what stops
## two islands merging into one landmass with an invisible biome border.
@export var island_gap: float = 5.0
@export_range(0.0, 3.0) var falloff_strength: float = 1.0
@export_range(0.002, 0.06) var elevation_frequency: float = 0.028
## Share of the host island raised into the stone mountain.
@export_range(0.0, 0.6) var mountain_share: float = 0.22
## Biome patches smaller than this are absorbed by their neighbours.
@export var min_biome_region: int = 8

@export_group("Bridges")
@export var bridge_min_length: int = 3
@export var bridge_max_length: int = 14
## Layouts to try before accepting one with an unreachable island.
@export var generation_attempts: int = 12

@export_group("Detail")
@export_range(0.0, 0.4) var tree_density: float = 0.055
@export_range(0.0, 0.5) var clutter_density: float = 0.16
@export_range(0.0, 0.8) var water_plant_density: float = 0.3
## When on, hoeing cuts a hole in the grass so the grass autotiles its own rim
## around the field, instead of the field simply being laid over unbroken grass.
@export var farmland_cuts_grass: bool = true
@export var pond_radius := 3
## Clear tiles required on every side of the player's spawn.
@export var spawn_clearance := 3

@onready var _water: TileMapLayer = $Water
@onready var _soil: TileMapLayer = $Soil
@onready var _cherry: TileMapLayer = $Cherry
@onready var _birch: TileMapLayer = $Birch
@onready var _pine: TileMapLayer = $Pine
@onready var _tilled_wet: TileMapLayer = $TilledWatered
@onready var _mountain_face: TileMapLayer = $MountainFace
@onready var _mountain_top: TileMapLayer = $MountainTop
@onready var _bridges: TileMapLayer = $Bridges
@onready var _plants: TileMapLayer = $WaterPlants
@onready var _decor: TileMapLayer = $Decorations

var _rng := RandomNumberGenerator.new()
var _land: Dictionary = {}
## Biome per land cell. Cells carved out for ponds are removed from this.
var _biome: Dictionary = {}
## Island index per land cell, so bridges know which shores to join.
var _island: Dictionary = {}
var _pond: Dictionary = {}
var _bridge_cells: Dictionary = {}
## Cells covered by a prop -> the cell its sprite was placed at. Multi-tile props
## like the big trees cover a block, so chopping any of those cells has to clear
## the whole footprint and the one cell that actually holds the tile.
var _occupied: Dictionary = {}
## Cells the player has hoed into farmland, and which of those are watered.
var _farmland: Dictionary = {}
var _watered: Dictionary = {}


func _ready() -> void:
	generate()


## Builds a world, retrying with a shifted seed until every island is reachable.
##
## Crossings need a straight run of water between two coasts, and a rough enough
## coastline can simply not offer one. That is rare but it does happen, and the
## result is a biome the player can never get to -- so rather than ship it, the
## layout is rolled again. Most seeds are accepted first time.
func generate() -> void:
	var base := world_seed if world_seed != 0 else randi()
	for attempt in generation_attempts:
		_build(base + attempt * 7919)
		if _is_connected():
			if attempt > 0:
				print("world %d: took %d retries to connect the islands" % [base, attempt])
			return
	push_warning("world %d: gave up after %d attempts, some islands are unreachable"
		% [base, generation_attempts])


func _build(build_seed: int) -> void:
	_rng.seed = build_seed
	for store in [_land, _biome, _island, _pond, _bridge_cells, _occupied,
			_farmland, _watered]:
		store.clear()
	for layer in [_water, _soil, _cherry, _birch, _pine, _tilled_wet,
			_mountain_face, _mountain_top, _bridges, _plants, _decor]:
		layer.clear()

	_classify()
	_despeckle()
	_prune_fragments()
	_carve_ponds()
	_build_bridges()
	_paint_ground()
	_paint_water()
	_scatter_water_plants()
	_scatter_decorations()
	_place_player()


# --- shape -------------------------------------------------------------------


## Grows one island per forest biome and raises the mountain inside its host.
func _classify() -> void:
	var elevation := FastNoiseLite.new()
	elevation.seed = _rng.seed
	elevation.frequency = elevation_frequency
	elevation.fractal_octaves = 4

	var centres := _island_centres()
	var heights: Dictionary = {}

	for y in world_size.y:
		for x in world_size.x:
			var cell := Vector2i(x, y)
			var point := Vector2(cell)

			# Nearest island, and how much nearer it is than the runner-up.
			var nearest := -1
			var best := INF
			var second := INF
			for i in centres.size():
				var distance := point.distance_to(centres[i])
				if distance < best:
					second = best
					best = distance
					nearest = i
				elif distance < second:
					second = distance
			# A buffer band along the midline between two islands is never land,
			# which is what guarantees they stay separate bodies.
			if centres.size() > 1 and best + island_gap > second:
				continue

			var height := (elevation.get_noise_2d(x, y) + 1.0) * 0.5
			height -= pow(best / island_radius, 2.0) * falloff_strength
			if height <= 0.18:
				continue

			_land[cell] = true
			_island[cell] = nearest
			_biome[cell] = ISLAND_BIOMES[nearest % ISLAND_BIOMES.size()]
			heights[cell] = height

	_raise_mountain(heights)


## Island centres, laid out in an L so that every pair the spanning tree will
## want to bridge shares either a row or a column.
##
## Spacing them evenly around a circle looks more natural but strands islands:
## a diagonal pair overlaps on only a narrow band of rows, and a bridge has to
## be axis-aligned because the art has no diagonal pieces, so the crossing
## search would often find nothing at any length. Sharing an axis gives it a
## wide band of candidate rows instead.
func _island_centres() -> Array[Vector2]:
	var middle := Vector2(world_size) * 0.5
	var half := island_spacing * 0.5
	var layout: Array[Vector2] = [
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half),
	]
	# Quarter turns vary the arrangement between seeds without breaking the
	# axis alignment; the jitter is kept small for the same reason.
	var turns := _rng.randi_range(0, 3)
	var centres: Array[Vector2] = []
	for offset in layout:
		var point := offset
		for t in turns:
			point = Vector2(-point.y, point.x)
		point += Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-2.0, 2.0))
		centres.append(middle + point)
	return centres


## The highest slice of the host island becomes stone. Taken as a share of that
## island rather than a fixed height, so a low seed still gets a mountain.
func _raise_mountain(heights: Dictionary) -> void:
	var host: Array[float] = []
	for cell: Vector2i in _land:
		if _biome[cell] == MOUNTAIN_HOST:
			host.append(heights[cell])
	if host.is_empty():
		push_warning("no island hosts the mountain")
		return
	var cut := _quantile(host, 1.0 - mountain_share)
	for cell: Vector2i in _land:
		if _biome[cell] == MOUNTAIN_HOST and heights[cell] >= cut:
			_biome[cell] = Biome.MOUNTAIN


## Value below which `fraction` of the samples fall.
func _quantile(samples: Array, fraction: float) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	var index := clampi(int(sorted.size() * fraction), 0, sorted.size() - 1)
	return sorted[index]


## Absorbs biome patches too small to read as anything but a stray tile into
## whichever biome surrounds them most.
func _despeckle() -> void:
	var seen := {}
	for cell: Vector2i in _biome:
		if seen.has(cell):
			continue
		var biome: int = _biome[cell]
		var region: Array[Vector2i] = []
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			region.append(p)
			for d in SIDES:
				var q: Vector2i = p + d
				if not seen.has(q) and _biome.get(q, -1) == biome:
					seen[q] = true
					stack.append(q)
		if region.size() >= min_biome_region:
			continue

		var tally := {}
		for p in region:
			for d in SIDES:
				var other: int = _biome.get(p + d, -1)
				if other == -1 or other == biome:
					continue
				tally[other] = tally.get(other, 0) + 1
		if tally.is_empty():
			continue
		var winner: int = biome
		var best := 0
		for candidate: int in tally:
			if tally[candidate] > best:
				best = tally[candidate]
				winner = candidate
		for p in region:
			_biome[p] = winner


## Reduces each island to its single largest body of land.
##
## The noise throws off detached lobes a few tiles offshore. They belong to the
## island by biome but not by geography, so nothing bridges them and the player
## can never reach them -- and they are what made the connectivity check cry
## wolf, since it counted an island as stranded if any cell was unreachable.
func _prune_fragments() -> void:
	var by_island: Dictionary = {}
	for cell: Vector2i in _land:
		var index: int = _island[cell]
		if not by_island.has(index):
			by_island[index] = {}
		by_island[index][cell] = true

	for index: int in by_island:
		var cells: Dictionary = by_island[index]
		var seen := {}
		var largest: Array[Vector2i] = []
		for cell: Vector2i in cells:
			if seen.has(cell):
				continue
			var component: Array[Vector2i] = []
			var stack: Array[Vector2i] = [cell]
			seen[cell] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				component.append(p)
				for d in SIDES:
					var q: Vector2i = p + d
					if cells.has(q) and not seen.has(q):
						seen[q] = true
						stack.append(q)
			if component.size() > largest.size():
				largest = component

		var keep := {}
		for cell in largest:
			keep[cell] = true
		for cell: Vector2i in cells:
			if keep.has(cell):
				continue
			_land.erase(cell)
			_biome.erase(cell)
			_island.erase(cell)


## One pond per forest biome, carved rather than noise-driven so each island is
## guaranteed to get one instead of whichever happens to win the noise.
func _carve_ponds() -> void:
	for biome in ISLAND_BIOMES:
		# Shrink until one fits rather than giving up at the requested size. The
		# pine island gives a fifth of itself to the mountain, so a full-size
		# pond with clearance often has nowhere to sit.
		var radius := pond_radius
		var candidates: Array[Vector2i] = []
		while radius >= 2:
			for cell: Vector2i in _biome:
				if _biome[cell] == biome and _inland_depth(cell, radius + 1):
					candidates.append(cell)
			if not candidates.is_empty():
				break
			radius -= 1
		if candidates.is_empty():
			push_warning("no room for a pond in biome %d" % biome)
			continue

		var centre: Vector2i = candidates[_rng.randi_range(0, candidates.size() - 1)]
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cell := centre + Vector2i(dx, dy)
				# Wobble the rim so the pond doesn't read as a circle.
				var wobble := _rng.randf() * 0.9
				if Vector2(dx, dy).length() > float(radius) - wobble:
					continue
				if not _land.has(cell):
					continue
				_pond[cell] = biome
				_land.erase(cell)
				_biome.erase(cell)
				_island.erase(cell)


## True when every cell within `radius` is land of the same biome -- used to keep
## ponds off the coast, off biome borders and out of the mountain.
func _inland_depth(cell: Vector2i, radius: int) -> bool:
	var biome = _biome.get(cell)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var other := cell + Vector2i(dx, dy)
			if not _land.has(other) or _biome.get(other) != biome:
				return false
	return true


# --- bridges -----------------------------------------------------------------


## Joins the islands along a spanning tree, so every biome is reachable.
##
## Crossings are found before the tree is built, not after: a pair of islands
## may have no straight two-wide gap between facing shores at all, and picking
## edges by centroid distance first would happily choose one of those.
func _build_bridges() -> void:
	var count := ISLAND_BIOMES.size()
	var edges: Array = []
	for a in count:
		for b in range(a + 1, count):
			var crossing := _find_crossing(a, b)
			if not crossing.is_empty():
				edges.append(crossing)
	edges.sort_custom(func(l, r): return l["length"] < r["length"])

	# Kruskal: keep an edge only when it joins two groups not yet connected.
	var group: Array[int] = []
	for i in count:
		group.append(i)
	for edge in edges:
		var ga: int = group[edge["near"]]
		var gb: int = group[edge["far"]]
		if ga == gb:
			continue
		for i in count:
			if group[i] == gb:
				group[i] = ga
		_place_bridge(edge)


## Shortest straight water gap with island `a` on one side and `b` on the other.
## Returns {} when the pair has no usable crossing.
##
## Only cells sitting directly against one of the two islands are worth
## extending from, and that test is cheap, so it runs first -- it rejects almost
## the whole map before any span is walked.
func _find_crossing(a: int, b: int) -> Dictionary:
	var best := {}
	for horizontal in [true, false]:
		var step := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
		for y in world_size.y:
			for x in world_size.x:
				var start := Vector2i(x, y)
				var near: int = _island.get(start - step, -1)
				if near != a and near != b:
					continue

				for length in range(1, bridge_max_length + 1):
					var cell := start + step * (length - 1)
					if not _inside(cell) or _land.has(cell):
						break
					if length < bridge_min_length:
						continue
					var far: int = _island.get(start + step * length, -1)
					if (near != a or far != b) and (near != b or far != a):
						continue
					if best.is_empty() or length < best["length"]:
						best = {
							"near": near, "far": far, "start": start,
							"length": length, "horizontal": horizontal,
						}
					break
	return best


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < world_size.x and cell.y < world_size.y


func _place_bridge(edge: Dictionary) -> void:
	var horizontal: bool = edge["horizontal"]
	var length: int = edge["length"]
	var start: Vector2i = edge["start"]
	var step := Vector2i(1, 0) if horizontal else Vector2i(0, 1)
	var parts: Dictionary = BRIDGE_H if horizontal else BRIDGE_V

	# The span runs end to end over water, and a cap is laid on the shore tile at
	# each end so the posts sit on land instead of floating a tile short of it.
	var total := length + 2
	for i in total:
		var key := "middle"
		if i == 0:
			key = "cap_a"
		elif i == total - 1:
			key = "cap_b"
		var cell := start + step * (i - 1)
		_bridges.set_cell(cell, SRC_BRIDGE, parts[key])
		_bridge_cells[cell] = true


## Walks land and bridges from one island to confirm the tree really joined
## everything. A pair with no straight crossing can leave a biome stranded, and
## generate() rolls a new layout when that happens.
func _is_connected() -> bool:
	if _land.is_empty():
		return false
	var start: Vector2i = _land.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		for d in SIDES:
			var next: Vector2i = cell + d
			if seen.has(next):
				continue
			if not _land.has(next) and not _bridge_cells.has(next):
				continue
			seen[next] = true
			stack.append(next)

	for cell: Vector2i in _land:
		if not seen.has(cell):
			return false
	return true


# --- painting ----------------------------------------------------------------


func _paint_ground() -> void:
	# Soil is the island itself. Its surf-lined blob edge becomes both the
	# coastline and the pond shore, and it stays visible as a beach wherever the
	# grass above is inset.
	var all_land: Array[Vector2i] = []
	for cell: Vector2i in _land:
		all_land.append(cell)
	_soil.set_cells_terrain_connect(all_land, TERRAIN_SOIL, 0)

	_paint_grass()

	# The mountain is drawn twice: the face sits on its real footprint and
	# carries the collision, the top is the same shape shifted up by the layer's
	# own offset. What shows between them is the cliff.
	_paint_biome(_mountain_face, Biome.MOUNTAIN, TERRAIN_STONE, false)
	_paint_biome(_mountain_top, Biome.MOUNTAIN, TERRAIN_STONE, false)


## Grass on top of the soil, inset by a cell so the beach shows at the water's
## edge instead of grass running straight into the sea.
func _paint_grass() -> void:
	_paint_biome(_cherry, Biome.CHERRY, TERRAIN_CHERRY, true)
	_paint_biome(_birch, Biome.BIRCH, TERRAIN_BIRCH, true)
	_paint_biome(_pine, Biome.PINE, TERRAIN_PINE, true)


func _paint_biome(layer: TileMapLayer, biome: int, terrain_set: int, inset: bool) -> void:
	layer.clear()
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _biome:
		if _biome[cell] != biome:
			continue
		if inset and not _has_all_neighbours(cell):
			continue
		if farmland_cuts_grass and _farmland.has(cell):
			continue
		cells.append(cell)
	if not cells.is_empty():
		layer.set_cells_terrain_connect(cells, terrain_set, 0)


func _has_all_neighbours(cell: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not _land.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Water covers the whole map, land included. The ground blob tiles have
## transparent rounded corners, so anywhere without water beneath them shows the
## empty background as black notches along the coast.
##
## Under land and under bridges it uses the collision-free variant; open sea and
## ponds keep alternative 0, which collides and is what holds the player in.
func _paint_water() -> void:
	for y in world_size.y:
		for x in world_size.x:
			var cell := Vector2i(x, y)
			var walkable := _land.has(cell) or _bridge_cells.has(cell)
			var variant := WATER_UNDER_LAND if walkable else WATER_SEA
			_water.set_cell(cell, SRC_WATER, Vector2i.ZERO, variant)


# --- scatter -----------------------------------------------------------------


func _scatter_water_plants() -> void:
	for cell: Vector2i in _pond:
		if _rng.randf() > water_plant_density:
			continue
		var biome: int = _pond[cell]
		var source_id: int = PLANT_SOURCE[biome]
		var tiles := _tiles_of_size(source_id, Vector2i.ONE)
		if tiles.is_empty():
			continue
		_plants.set_cell(cell, source_id, tiles[_rng.randi_range(0, tiles.size() - 1)])


func _scatter_decorations() -> void:
	# Trees first, so the bigger props claim their space before clutter fills in.
	for cell in _shuffled_land():
		if not _biome.has(cell) or _biome[cell] == Biome.MOUNTAIN:
			continue
		if _rng.randf() > tree_density:
			continue
		var source_id: int = DECOR_SOURCE[_biome[cell]]
		var trees := _tiles_larger_than(source_id, Vector2i.ONE)
		if trees.is_empty():
			continue
		var coords: Vector2i = trees[_rng.randi_range(0, trees.size() - 1)]
		_try_place(cell, source_id, coords)

	for cell in _shuffled_land():
		if not _biome.has(cell) or _occupied.has(cell):
			continue
		if _rng.randf() > clutter_density:
			continue
		var biome: int = _biome[cell]
		if biome == Biome.MOUNTAIN:
			continue
		var source_id: int = DECOR_SOURCE[biome]
		var small := _tiles_of_size(source_id, Vector2i.ONE)
		if small.is_empty():
			continue
		_try_place(cell, source_id, small[_rng.randi_range(0, small.size() - 1)])


## Places a prop only if every cell it covers is free land of the same biome,
## and marks that footprint so later props don't overlap it.
func _try_place(cell: Vector2i, source_id: int, coords: Vector2i) -> void:
	var source := _decor.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return
	var size := source.get_tile_size_in_atlas(coords)
	var biome: int = _biome[cell]
	for dy in size.y:
		for dx in size.x:
			var covered := cell + Vector2i(dx, dy)
			if _occupied.has(covered) or _biome.get(covered, -1) != biome:
				return
	for dy in size.y:
		for dx in size.x:
			_occupied[cell + Vector2i(dx, dy)] = cell
	_decor.set_cell(cell, source_id, coords)


## Drops the player on open ground near the middle of their island.
func _place_player() -> void:
	var player := get_node_or_null(player_path) as Node2D
	if player == null:
		return
	var middle := world_size / 2
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for cell: Vector2i in _land:
		if _occupied.has(cell) or _biome.get(cell) == Biome.MOUNTAIN:
			continue
		# Needs open ground around it -- the cell nearest the centre is often the
		# lip of a pond, which drops the player against a wall on their first
		# step. Only water counts as blocking; decorations don't collide.
		if not _water_free(cell, spawn_clearance):
			continue
		var distance := Vector2(cell).distance_squared_to(Vector2(middle))
		if distance < best_distance:
			best_distance = distance
			best = cell
	if best == Vector2i(-1, -1):
		push_warning("no spawn with %d tiles of clearance" % spawn_clearance)
		best = _land.keys()[0] if not _land.is_empty() else middle
	player.position = _soil.map_to_local(best)


func _water_free(cell: Vector2i, radius: int) -> bool:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not _land.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Fisher-Yates against this generator's own stream. Array.shuffle() draws from
## the global RNG, which left the same world_seed producing a different scatter
## of decorations on every run -- and, through them, a different spawn.
func _shuffled_land() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _land:
		cells.append(cell)
	for i in range(cells.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := cells[i]
		cells[i] = cells[j]
		cells[j] = swap
	return cells


func _tiles_of_size(source_id: int, size: Vector2i) -> Array[Vector2i]:
	return _collect_tiles(source_id, func(s: Vector2i): return s == size)


func _tiles_larger_than(source_id: int, size: Vector2i) -> Array[Vector2i]:
	return _collect_tiles(source_id, func(s: Vector2i): return s.x > size.x or s.y > size.y)


func _collect_tiles(source_id: int, predicate: Callable) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var source := _decor.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return out
	for i in source.get_tiles_count():
		var coords := source.get_tile_id(i)
		if predicate.call(source.get_tile_size_in_atlas(coords)):
			out.append(coords)
	return out


# --- interaction -------------------------------------------------------------
#
# The world owns the tile data, so the queries and edits the player's tools need
# live here. TileCursor handles aiming and input and calls into this.


## The cell under a point in global space.
func cell_at(point: Vector2) -> Vector2i:
	return _soil.local_to_map(_soil.to_local(point))


## The centre of a cell, in global space.
func cell_centre(cell: Vector2i) -> Vector2:
	return _soil.to_global(_soil.map_to_local(cell))


func is_land(cell: Vector2i) -> bool:
	return _land.has(cell)


func is_farmland(cell: Vector2i) -> bool:
	return _farmland.has(cell)


func is_watered(cell: Vector2i) -> bool:
	return _watered.has(cell)


func biome_at(cell: Vector2i) -> int:
	return _biome.get(cell, -1)


## The cell holding the sprite of whatever prop covers `cell`, or (-1, -1).
func prop_at(cell: Vector2i) -> Vector2i:
	return _occupied.get(cell, Vector2i(-1, -1))


## Hoeing needs open forest floor: land, a grass biome rather than the mountain,
## clear of props and bridges, and not already farmland.
func can_till(cell: Vector2i) -> bool:
	if not _land.has(cell) or _farmland.has(cell):
		return false
	if _occupied.has(cell) or _bridge_cells.has(cell):
		return false
	return ISLAND_BIOMES.has(_biome.get(cell, -1))


func till(cell: Vector2i) -> bool:
	if not can_till(cell):
		return false
	_farmland[cell] = true
	_repaint_farmland()
	return true


func can_chop(cell: Vector2i) -> bool:
	return _occupied.has(cell)


## Clears the whole footprint rather than the cell that was hit: a big tree
## covers a 3x3 block but only one of those cells carries its tile.
func chop(cell: Vector2i) -> bool:
	if not can_chop(cell):
		return false
	var origin: Vector2i = _occupied[cell]
	var covered: Array[Vector2i] = []
	for other: Vector2i in _occupied:
		if _occupied[other] == origin:
			covered.append(other)
	for other in covered:
		_occupied.erase(other)
	_decor.erase_cell(origin)
	return true


func can_water(cell: Vector2i) -> bool:
	return _farmland.has(cell) and not _watered.has(cell)


func water(cell: Vector2i) -> bool:
	if not can_water(cell):
		return false
	_watered[cell] = true
	_repaint_farmland()
	return true


## Repaints the whole field rather than the one changed cell, so the blob
## autotiling reworks its neighbours too -- otherwise a newly hoed tile sits as
## a hard square inside a rounded patch.
##
## A dry field draws nothing of its own: hoeing removes the grass and the soil
## base already beneath shows through, flat and rimless. Only watering draws, in
## the pack's darker soil.
##
## Watered cells are filled with the blob's interior tile rather than autotiled.
## Autotiling gives the wet patch a rim of its own, and neither rim suits it:
## the plain sheet's carries a white surf line, and the hills sheet's is the
## brown band that made a flat field read as a pit. A per-tile square is also
## how a watered tile normally reads in a farming game.
func _repaint_farmland() -> void:
	_tilled_wet.clear()
	if farmland_cuts_grass:
		# The grass rim moves whenever the field grows, so it has to be redrawn.
		_paint_grass()

	for cell: Vector2i in _watered:
		_tilled_wet.set_cell(cell, SRC_FARMLAND_WET, FARMLAND_WET_FILL)


## Size of one tile in pixels.
func tile_size() -> Vector2i:
	return _soil.tile_set.tile_size
