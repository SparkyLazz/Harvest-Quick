# Builds Assets/Tilemap/Terrains.tres from the Sprout Lands ground sheets.
#
#   godot --headless --path . --script res://Tools/build_tileset.gd
#
# Generated rather than hand-authored, and that is the point. A terrain set is
# 47 tiles each carrying eight peering bits, and every one of those bits has to
# agree with what the artist actually drew. Typing 376 booleans into a .tres by
# eye is a guarantee of a dozen quietly wrong cells; reading them out of the
# sheet's own alpha channel cannot disagree with the sheet.
#
# Re-run it whenever a ground sheet changes. The output is a build artifact that
# happens to be committed, the same way the harness's numbers are.
#
# Which sheets can carry a terrain is decided by the art, not by preference.
# Tools/probe_ground.gd prints the connectivity of every cell, and it says:
#
#   Grass.png         has transparent edges on rows 0-4 -> can autotile over a
#                     darker base, so the farm's border gets a drawn edge.
#   Tilled_Dirt.png   same, and this is where autotiling actually earns its
#                     keep: the player hoes whichever tiles they like, so soil
#                     is the one region in this game with an irregular shape.
#   Darker_Grass_v2   is opaque in nearly every cell. It is a flat layer set,
#                     not a terrain, so it is the base fill and nothing else.
extends SceneTree

const CELL := 16
const TILE_SIZE := Vector2i(CELL, CELL)
const OUT_PATH := "res://Assets/Tilemap/Terrains.tres"

const SPRITES := "res://Assets/Sprout Lands - Sprites - premium pack/"

# Source ids are written into GameConfig, so they are fixed here rather than
# left to allocation order.
const SRC_WILD := 0
const SRC_OWNED := 1
const SRC_SOIL := 2
const SRC_ROCK := 3
const SRC_WOOD := 4
const SRC_FENCE := 5

# Terrain sets, one per autotiled region. Two rather than one, because grass and
# soil connect to themselves and not to each other: a tilled tile at the edge of
# the field must not try to blend into the grass beyond it.
const TS_GRASS := 0
const TS_SOIL := 1

# Least of a cell that has to be drawn before it may join a terrain.
#
# It exists because of a bug the first generated tileset shipped with. Both
# ground sheets carry a few decorative specks — three or four per cent of a cell,
# a pebble or a tuft — and a speck probes exactly like a legitimate lone tile:
# nothing drawn in any of the eight directions. Godot scores candidates and
# breaks ties at random, so a single tilled tile came out as a proper round patch
# one time and as a three-pixel dot the next. Same press, same state, different
# picture.
#
# Twelve per cent separates them cleanly on both sheets. The specks are at 1 to
# 4, and the smallest tile anyone actually drew to stand alone is at 20.
const MIN_COVERAGE := 0.12

# Godot's eight neighbours for a square tile, paired with where each one is
# probed in the artwork. The probe reads one pixel inside the cell, so the
# terrain's own outline counts as drawn — which is correct, because an outline is
# only drawn where the terrain stops.
const PEERING := [
	[TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER, 0, 0],
	[TileSet.CELL_NEIGHBOR_TOP_SIDE, 1, 0],
	[TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER, 2, 0],
	[TileSet.CELL_NEIGHBOR_LEFT_SIDE, 0, 1],
	[TileSet.CELL_NEIGHBOR_RIGHT_SIDE, 2, 1],
	[TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER, 0, 2],
	[TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, 1, 2],
	[TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER, 2, 2],
]

func _init() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = TILE_SIZE

	# Both sets match corners and sides. That is what a 47-tile blob sheet is
	# drawn for: a tile knows about its four neighbours and about the four
	# diagonals, which is the only way an inner corner can be told from an edge.
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(TS_GRASS, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(TS_GRASS)
	tile_set.set_terrain_name(TS_GRASS, 0, "Owned grass")
	tile_set.set_terrain_color(TS_GRASS, 0, Color(0.45, 0.78, 0.35))

	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(TS_SOIL, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(TS_SOIL)
	tile_set.set_terrain_name(TS_SOIL, 0, "Tilled soil")
	tile_set.set_terrain_color(TS_SOIL, 0, Color(0.85, 0.7, 0.45))

	var report := []

	# The wild base. Only the cells that are wholly opaque: this layer is painted
	# under everything else and a hole in it would show the window background,
	# which is the bug that once made wild ground read as "not part of the map".
	report.append(_add_plain(tile_set, SRC_WILD,
		SPRITES + "Tilesets/ground tiles/New tiles/Darker_Grass_Tiles_v2.png", true))

	# The two terrains.
	report.append(_add_terrain(tile_set, SRC_OWNED,
		SPRITES + "Tilesets/ground tiles/Old tiles/Grass.png", TS_GRASS))
	report.append(_add_terrain(tile_set, SRC_SOIL,
		SPRITES + "Tilesets/ground tiles/Old tiles/Tilled_Dirt.png", TS_SOIL))

	# Objects. No terrain: a rock does not blend into the rock beside it, it is
	# one thing standing on one tile. Every drawn cell is kept so GameConfig can
	# pick by atlas coordinate, which is how Debris will choose a bigger rock for
	# more work remaining in 4.2.
	report.append(_add_plain(tile_set, SRC_ROCK,
		SPRITES + "Objects/Mushrooms, Flowers, Stones.png", false))
	report.append(_add_plain(tile_set, SRC_WOOD,
		SPRITES + "Objects/Trees, stumps and bushes.png", false))
	report.append(_add_plain(tile_set, SRC_FENCE,
		SPRITES + "Tilesets/Building parts/Fences.png", false))

	var err := ResourceSaver.save(tile_set, OUT_PATH)
	if err != OK:
		print("FAILED to save ", OUT_PATH, " err ", err)
		quit(1)
		return

	print("\nwrote ", OUT_PATH)
	for line in report:
		print("  ", line)
	quit()

# A source whose tiles carry no terrain. `solid_only` keeps just the cells with
# no transparency, which is what a base fill needs.
func _add_plain(tile_set: TileSet, id: int, path: String, solid_only: bool) -> String:
	var image := Image.load_from_file(path)
	if image == null:
		return "MISSING " + path.get_file()

	var source := TileSetAtlasSource.new()
	source.texture = load(path)
	source.texture_region_size = TILE_SIZE
	tile_set.add_source(source, id)

	var kept := 0
	for c in range(image.get_width() / CELL):
		for r in range(image.get_height() / CELL):
			var cover := _coverage(image, c, r)
			if cover == 0.0:
				continue
			if solid_only and cover < 1.0:
				continue

			source.create_tile(Vector2i(c, r))
			kept += 1

	return "src %d  %-34s %3d tiles%s" % [id, path.get_file(), kept,
		"  (solid only)" if solid_only else ""]

# A source whose tiles carry peering bits read out of the artwork.
func _add_terrain(tile_set: TileSet, id: int, path: String, terrain_set: int) -> String:
	var image := Image.load_from_file(path)
	if image == null:
		return "MISSING " + path.get_file()

	var source := TileSetAtlasSource.new()
	source.texture = load(path)
	source.texture_region_size = TILE_SIZE
	tile_set.add_source(source, id)

	var kept := 0
	var centres := 0
	var specks := 0
	for c in range(image.get_width() / CELL):
		for r in range(image.get_height() / CELL):
			# A cell whose middle is not drawn is not a tile of this terrain. It
			# is either empty sheet or the hole a blob layout leaves to show off
			# its inner corners.
			if not _solid(image, c * CELL + CELL / 2, r * CELL + CELL / 2):
				continue

			if _coverage(image, c, r) < MIN_COVERAGE:
				specks += 1
				continue

			var coords := Vector2i(c, r)
			source.create_tile(coords)
			var data := source.get_tile_data(coords, 0)
			data.terrain_set = terrain_set
			data.terrain = 0

			for bit in PEERING:
				if _probe(image, c, r, bit[1], bit[2]):
					data.set_terrain_peering_bit(bit[0], 0)

			kept += 1
			if _fully_surrounded(image, c, r):
				centres += 1

	var lone := _count_lone(source)
	return "src %d  %-34s %3d tiles, %d surrounded, %d lone, %d specks dropped, set %d" % [
		id, path.get_file(), kept, centres, lone, specks, terrain_set]

# How many tiles claim no neighbours at all. Reported because it is the number
# that was wrong: four candidates for a lone tile, three of them specks, meant
# the same action drew a different picture each time. One is the answer, and if
# this ever prints zero then a lone tilled tile has no art and Godot will be
# picking whichever wrong tile scores least badly.
func _count_lone(source: TileSetAtlasSource) -> int:
	var lone := 0
	for i in range(source.get_tiles_count()):
		var coords := source.get_tile_id(i)
		var data := source.get_tile_data(coords, 0)
		var any := false
		for bit in PEERING:
			if data.get_terrain_peering_bit(bit[0]) != -1:
				any = true
				break
		if not any:
			lone += 1
	return lone

# Probes one of the nine positions in a cell: 0 = one pixel in, 1 = midpoint,
# 2 = one pixel from the far edge.
func _probe(image: Image, c: int, r: int, sx: int, sy: int) -> bool:
	var at := [1, CELL / 2, CELL - 2]
	return _solid(image, c * CELL + at[sx], r * CELL + at[sy])

func _fully_surrounded(image: Image, c: int, r: int) -> bool:
	for bit in PEERING:
		if not _probe(image, c, r, bit[1], bit[2]):
			return false
	return true

func _coverage(image: Image, c: int, r: int) -> float:
	var opaque := 0
	for y in range(CELL):
		for x in range(CELL):
			if _solid(image, c * CELL + x, r * CELL + y):
				opaque += 1
	return float(opaque) / float(CELL * CELL)

func _solid(image: Image, x: int, y: int) -> bool:
	return image.get_pixel(x, y).a > 0.03
