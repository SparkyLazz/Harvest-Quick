extends SceneTree
## Builds res://Assets/Tilemap/Terrains.tres from the Sprout Lands sheets.
##
## Re-run after changing any source art:
##   godot --headless --path . --script res://Tools/BuildTerrains.gd
##
## Nothing here is hand-measured. The blob table below was decoded from the
## pack's own "Bitmask references 1.png", and decoration sprites are found by
## scanning each sheet for connected opaque regions at build time.

const OUTPUT := "res://Assets/Tilemap/Terrains.tres"
const CELL := 16

## Every ground sheet in the pack repeats one 47-tile blob set: 11 columns x 5
## rows, offset down the sheet by `block_row`. Key is the atlas cell inside that
## block; value is the 3x3 neighbourhood that cell represents, row-major, where
## index 4 is the tile itself:  0 1 2 / 3 4 5 / 6 7 8
const BLOB := {
	Vector2i(0, 0): "000011011",
	Vector2i(1, 0): "000111111",
	Vector2i(2, 0): "000110110",
	Vector2i(3, 0): "000010010",
	Vector2i(4, 0): "000011010",
	Vector2i(5, 0): "000111110",
	Vector2i(6, 0): "000111011",
	Vector2i(7, 0): "000110010",
	Vector2i(8, 0): "000111010",
	Vector2i(9, 0): "110111011",
	Vector2i(0, 1): "011011011",
	Vector2i(1, 1): "111111111",
	Vector2i(2, 1): "110110110",
	Vector2i(3, 1): "010010010",
	Vector2i(4, 1): "011011010",
	Vector2i(5, 1): "111111110",
	Vector2i(6, 1): "111111011",
	Vector2i(7, 1): "110110010",
	Vector2i(8, 1): "111111010",
	Vector2i(9, 1): "011111110",
	Vector2i(0, 2): "011011000",
	Vector2i(1, 2): "111111000",
	Vector2i(2, 2): "110110000",
	Vector2i(3, 2): "010010000",
	Vector2i(4, 2): "010011011",
	Vector2i(5, 2): "110111111",
	Vector2i(6, 2): "011111111",
	Vector2i(7, 2): "010110110",
	Vector2i(8, 2): "010111111",
	Vector2i(9, 2): "010111011",
	Vector2i(10, 2): "010111110",
	Vector2i(0, 3): "000011000",
	Vector2i(1, 3): "000111000",
	Vector2i(2, 3): "000110000",
	Vector2i(3, 3): "000010000",
	Vector2i(4, 3): "010011000",
	Vector2i(5, 3): "110111000",
	Vector2i(6, 3): "011111000",
	Vector2i(7, 3): "010110000",
	Vector2i(8, 3): "010111000",
	Vector2i(9, 3): "011111010",
	Vector2i(10, 3): "110111010",
	Vector2i(4, 4): "010011010",
	Vector2i(5, 4): "110111110",
	Vector2i(6, 4): "011111011",
	Vector2i(7, 4): "010110010",
	Vector2i(8, 4): "010111010",
}

## Mask index -> the Godot peering bit it corresponds to. Index 4 is the tile.
const PEERING := {
	0: TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	1: TileSet.CELL_NEIGHBOR_TOP_SIDE,
	2: TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	3: TileSet.CELL_NEIGHBOR_LEFT_SIDE,
	5: TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
	6: TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	7: TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	8: TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
}

const PU := "res://Assets/Plant update 2/"
const NT := "res://Assets/Tilesets/ground tiles/New tiles/"
const BP := "res://Assets/Tilesets/Building parts/"

## One terrain set per material, each holding a single terrain. These sheets
## only carry self-vs-empty edges -- no cross-material transition tiles exist --
## so keeping one terrain per set stops Godot hunting for tiles that aren't there.
##
## Soil and stone are the base ground and the grasses sit on top of them, which
## is the pack's own model -- see "TILE LAYER EXAMPLE.png", where soil underlies
## light grass underlies dark grass.
##
## What a sheet's outer edge *means* decides which one to use, and the art says
## it outright: a plain "_Ground_Tiles" sheet draws a white surf line along its
## rim, so that edge is a shoreline. A "_Hills_Tiles" sheet has no surf line --
## its rim is a drop onto land. Measured on the top-left corner tile, white
## pixels as a share of the outer boundary:
##
##   Soil_Ground_Tiles         0.27   shoreline -> the island's coast
##   Stone_Ground_Tiles        0.27   shoreline -> wrong for an inland peak
##   Stone_Ground_Hills_Tiles  0.00   height    -> the mountain
##   every grass block         0.00   neither   -> always sits on a base
##
## The surf line is not the only thing that separates the two, though. Both
## variants draw a brown rim; the hills one is simply the rim without the surf.
## So "inland" alone is not a reason to reach for hills -- a flat patch of
## ground wants no rim at all, which means no blob of its own.
##
## `block_row` picks the blob block within a sheet. Row 0 is the rimmed block
## the base materials use; row 5 is the clean-edged block the grasses use so
## they feather into whatever is beneath instead of drawing a rim of their own.
const GROUND_SOURCES := [
	{
		"id": 1, "terrain": "Soil", "block_row": 0,
		"path": NT + "Soil_Ground_Tiles.png",
		"color": Color(0.91, 0.81, 0.65), "decor_rows": [5, 6],
	},
	# Stone collides: the mountain is a raised plateau you can't climb, because
	# the pack has no stone stairs and no cave interior to lead anywhere.
	{
		"id": 2, "terrain": "Stone", "block_row": 0, "collision": true,
		"path": NT + "Stone_Ground_Hills_Tiles.png",
		"color": Color(0.76, 0.78, 0.73), "decor_rows": [5, 6],
	},
	{
		"id": 3, "terrain": "Cherry", "block_row": 5,
		"path": PU + "Ground tilesets/Grass_Tile_Layers.png",
		"color": Color(0.82, 0.88, 0.47), "decor_rows": [13, 24],
	},
	{
		"id": 4, "terrain": "Birch", "block_row": 5,
		"path": PU + "Ground tilesets/blue_tint_Grass_Tile_Layers2.png",
		"color": Color(0.68, 0.83, 0.60), "decor_rows": [13, 24],
	},
	{
		"id": 5, "terrain": "Pine", "block_row": 5,
		"path": PU + "Ground tilesets/blue_tint_Grass_Tile_Layers4.png",
		"color": Color(0.51, 0.66, 0.52), "decor_rows": [13, 24],
	},
	# Watered farmland, in the pack's darker soil -- RGB(205,189,155) against
	# (232,207,166) -- rather than the dry sheet under a tint.
	#
	# There is deliberately no *dry* farmland terrain. Hoeing cuts the grass and
	# the soil base already underneath shows through, which is flat and rimless,
	# exactly like the reference. Drawing a soil blob over it instead gives the
	# field the blob's own brown rim, and a flat field ringed in dark brown reads
	# as a pit.
	{
		"id": 6, "terrain": "FarmlandWet", "block_row": 0,
		"path": NT + "Darker_Soil_Ground_Tiles.png",
		"color": Color(0.80, 0.74, 0.61), "decor_rows": [5, 6],
	},
]

## Sheets registered as plain tiles. Decoration sheets get sprite detection;
## the others are laid out on the grid and taken cell by cell.
const PLAIN_SOURCES := [
	{"id": 10, "path": PU + "Cherry Blossom Biom.png", "detect": true},
	{"id": 11, "path": PU + "Birch wood Biom.png", "detect": true},
	{"id": 12, "path": PU + "Pine Tree Biome.png", "detect": true},
	{"id": 13, "path": PU + "Cherry Blossom Biom water plants.png", "detect": true},
	{"id": 14, "path": PU + "Birch wood Biom water plants.png", "detect": true},
	{"id": 15, "path": PU + "Pine Tree Biome water plants.png", "detect": true},
	# Bridges, taken cell by cell. Vertical runs down cols 0-1 (top cap / middle
	# / bottom cap); horizontal runs along rows 0-1 (col 2 cap, col 3 middle,
	# col 4 cap), so a crossing is 2 tiles wide and any length.
	{"id": 17, "path": BP + "Wooden_Bridge.png", "detect": false},
	# Cut steps and cave mouths. Registered but unused: every tile on this sheet
	# has a fully opaque grass background, so dropping one onto a biome paints a
	# mismatched green square. It only makes sense once the mountain is actually
	# raised and the ramp sits on a cliff it belongs to.
	{"id": 16, "path": NT + "Grass_Hill_Tiles_Slopes v.2.png", "detect": false},
]

const WATER_PATH := "res://Assets/Tilesets/ground tiles/Water.png"
const WATER_ID := 0

var _log: PackedStringArray = []


func _initialize() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(CELL, CELL)

	# One physics layer, used by water so the player can't wade off the island.
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)

	_build_water(tile_set)
	for cfg in GROUND_SOURCES:
		_build_ground(tile_set, cfg)
	for cfg in PLAIN_SOURCES:
		_build_plain(tile_set, cfg)

	var err := ResourceSaver.save(tile_set, OUTPUT)
	if err != OK:
		printerr("save failed: %d" % err)
		quit(1)
		return

	for line in _log:
		print(line)
	print("terrain sets: %d" % tile_set.get_terrain_sets_count())
	print("saved -> %s" % OUTPUT)
	quit()


func _add_full_tile_collision(data: TileData) -> void:
	var half := float(CELL) / 2.0
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	]))


func _make_source(tile_set: TileSet, path: String, id: int) -> TileSetAtlasSource:
	var tex: Texture2D = load(path)
	if tex == null:
		printerr("missing texture: %s" % path)
		return null
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(CELL, CELL)
	tile_set.add_source(src, id)
	return src


## Water is one tile cycling the sheet's four frames, in two variants.
##
## Alternative 0 carries collision and is the open sea. Alternative 1 is the same
## animation with no collision: the generator lays it under the land, because the
## ground blob tiles have transparent rounded corners and without something
## beneath them those corners show the empty background as black notches.
func _build_water(tile_set: TileSet) -> void:
	var src := _make_source(tile_set, WATER_PATH, WATER_ID)
	if src == null:
		return
	var origin := Vector2i.ZERO
	src.create_tile(origin)
	src.set_tile_animation_columns(origin, 4)
	src.set_tile_animation_frames_count(origin, 4)
	src.set_tile_animation_speed(origin, 2.0)

	_add_full_tile_collision(src.get_tile_data(origin, 0))
	var under_land := src.create_alternative_tile(origin)
	_log.append("water: animated (4 frames); alt 0 = sea w/ collision, alt %d = under land, no collision" % under_land)


func _build_ground(tile_set: TileSet, cfg: Dictionary) -> void:
	var src := _make_source(tile_set, cfg["path"], cfg["id"])
	if src == null:
		return

	var set_index := tile_set.get_terrain_sets_count()
	tile_set.add_terrain_set()
	tile_set.set_terrain_set_mode(set_index, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	tile_set.add_terrain(set_index)
	tile_set.set_terrain_name(set_index, 0, cfg["terrain"])
	tile_set.set_terrain_color(set_index, 0, cfg["color"])

	var block_row: int = cfg["block_row"]
	var collides: bool = cfg.get("collision", false)
	var painted := 0
	for cell in BLOB:
		var coords := Vector2i(cell.x, cell.y + block_row)
		if not _region_has_pixels(src.texture, coords, Vector2i.ONE):
			continue
		src.create_tile(coords)
		var data := src.get_tile_data(coords, 0)
		data.terrain_set = set_index
		data.terrain = 0
		var mask: String = BLOB[cell]
		for i in PEERING:
			if mask[i] == "1":
				data.set_terrain_peering_bit(PEERING[i], 0)
		if collides:
			_add_full_tile_collision(data)
		painted += 1

	# Plain decorative variants (tufts, moss, flowers) -- no terrain, scattered
	# by the generator on top of the matching ground.
	var decor := 0
	var rows: Array = cfg["decor_rows"]
	var cols := int(src.texture.get_width() / CELL)
	for row in range(rows[0], rows[1] + 1):
		for col in cols:
			var coords := Vector2i(col, row)
			if not _region_has_pixels(src.texture, coords, Vector2i.ONE):
				continue
			src.create_tile(coords)
			decor += 1

	_log.append("%-9s set %d: %d blob tiles, %d decorative" % [cfg["terrain"], set_index, painted, decor])


func _build_plain(tile_set: TileSet, cfg: Dictionary) -> void:
	var src := _make_source(tile_set, cfg["path"], cfg["id"])
	if src == null:
		return
	var path: String = cfg["path"]
	var label := path.get_file().get_basename()

	if not cfg["detect"]:
		var made := 0
		var cols := int(src.texture.get_width() / CELL)
		var rows := int(src.texture.get_height() / CELL)
		for row in rows:
			for col in cols:
				if _region_has_pixels(src.texture, Vector2i(col, row), Vector2i.ONE):
					src.create_tile(Vector2i(col, row))
					made += 1
		_log.append("%-28s %d tiles" % [label, made])
		return

	var sprites := _detect_sprites(src.texture)
	var made := 0
	for rect in sprites:
		# create_tile rejects a region overlapping one already taken, which is
		# how a stray detection gets dropped rather than corrupting the source.
		if not src.has_room_for_tile(rect.position, rect.size, 1, Vector2i.ZERO, 1):
			continue
		src.create_tile(rect.position, rect.size)
		var data := src.get_tile_data(rect.position, 0)
		# Sort tall props by their base so the player can walk behind them.
		data.y_sort_origin = int(rect.size.y * CELL / 2.0)
		made += 1
	_log.append("%-28s %d sprites (from %d regions)" % [label, made, sprites.size()])


## Connected opaque regions, snapped out to whole tiles. Sprites the pack draws
## with a white keyline are inventory icons rather than things you place, so
## they're dropped.
func _detect_sprites(tex: Texture2D) -> Array[Rect2i]:
	var img := tex.get_image()
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var out: Array[Rect2i] = []

	for y in h:
		for x in w:
			var key := y * w + x
			if seen.has(key) or img.get_pixel(x, y).a <= 0.06:
				continue
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[key] = true
			var lo := Vector2i(x, y)
			var hi := Vector2i(x, y)
			var pixels: Array[Vector2i] = []
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				pixels.append(p)
				lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
				hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var n := p + Vector2i(dx, dy)
						if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
							continue
						var nkey := n.y * w + n.x
						if seen.has(nkey) or img.get_pixel(n.x, n.y).a <= 0.06:
							continue
						seen[nkey] = true
						stack.append(n)
			if pixels.size() < 20:
				continue
			if _is_item_icon(img, pixels):
				continue
			var tl := Vector2i(lo.x / CELL, lo.y / CELL)
			var br := Vector2i(hi.x / CELL, hi.y / CELL)
			out.append(Rect2i(tl, br - tl + Vector2i.ONE))

	return _merge_overlaps(out)

## The pack marks item-drop icons with a white keyline all the way round, so
## they're dropped rather than scattered as scenery.
##
## The measurement is bimodal and there is nothing near the cut: item icons
## score exactly 1.0 across every sheet, real props score 0.0, and the lily pads
## top out at 0.58 -- their white is a waterline highlight along one edge, not an
## outline. An earlier cut of 0.5 was what wrongly ate the lily pads.
func _is_item_icon(img: Image, pixels: Array[Vector2i]) -> bool:
	const STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var edge := 0
	var white := 0
	for p in pixels:
		var boundary := false
		for d in STEPS:
			var n := p + d
			if n.x < 0 or n.y < 0 or n.x >= img.get_width() or n.y >= img.get_height():
				boundary = true
				break
			if img.get_pixel(n.x, n.y).a <= 0.06:
				boundary = true
				break
		if not boundary:
			continue
		edge += 1
		var c := img.get_pixel(p.x, p.y)
		if c.r > 0.88 and c.g > 0.88 and c.b > 0.82:
			white += 1
	return edge > 0 and float(white) / float(edge) >= 0.9


func _merge_overlaps(rects: Array[Rect2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for r in rects:
		var merged := false
		for i in out.size():
			if out[i].intersects(r):
				out[i] = out[i].merge(r)
				merged = true
				break
		if not merged:
			out.append(r)
	return out


func _region_has_pixels(tex: Texture2D, coords: Vector2i, size: Vector2i) -> bool:
	var img := tex.get_image()
	var origin := coords * CELL
	for y in range(origin.y, mini(origin.y + size.y * CELL, img.get_height())):
		for x in range(origin.x, mini(origin.x + size.x * CELL, img.get_width())):
			if img.get_pixel(x, y).a > 0.06:
				return true
	return false
