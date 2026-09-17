# Prints what the engine actually sees in the project's TileSet.
#
#   godot --headless --path . --script res://Tools/dump_tileset.gd
#
# Reading the .tres by eye is how you end up wiring code to a source id that
# moved. This asks Godot, so what it prints is what SetCellsTerrainConnect will
# be working with: source ids, which texture each one points at, the terrain set
# and its terrains, how many tiles carry each terrain, and which tiles animate.
extends SceneTree

const PATH := "res://Assets/Tilemap/Tilemap.tres"

func _init() -> void:
	var tile_set: TileSet = load(PATH)
	if tile_set == null:
		print("could not load ", PATH)
		quit(1)
		return

	print("tile_size ", tile_set.tile_size, "   sources ", tile_set.get_source_count(),
		"   terrain sets ", tile_set.get_terrain_sets_count())

	for s in range(tile_set.get_terrain_sets_count()):
		var mode := tile_set.get_terrain_set_mode(s)
		var mode_name: String = ["corners+sides", "corners", "sides"][mode]
		print("\nterrain set %d  (%s)" % [s, mode_name])
		for t in range(tile_set.get_terrains_count(s)):
			print("  terrain %d  %-14s" % [t, "\"%s\"" % tile_set.get_terrain_name(s, t)])

	print("")
	for i in range(tile_set.get_source_count()):
		var id := tile_set.get_source_id(i)
		var source := tile_set.get_source(id) as TileSetAtlasSource
		if source == null:
			continue

		var texture_name := "(none)"
		if source.texture != null:
			texture_name = source.texture.resource_path.get_file()

		# Tally tiles per terrain, how many carry no terrain at all, and how many
		# are animated. The per-terrain count is the number that matters: a
		# terrain with no tiles in any source cannot be painted, and the failure
		# looks like "nothing happens" rather than like an error.
		var per_terrain := {}
		var untagged := 0
		var animated := 0
		var lone := {}

		for t in range(source.get_tiles_count()):
			var coords := source.get_tile_id(t)
			if source.get_tile_animation_frames_count(coords) > 1:
				animated += 1

			var data := source.get_tile_data(coords, 0)
			if data == null or data.terrain_set < 0 or data.terrain < 0:
				untagged += 1
				continue

			var key := "%d:%d" % [data.terrain_set, data.terrain]
			per_terrain[key] = per_terrain.get(key, 0) + 1

			# A tile claiming no neighbours is the one a lone cell gets. More
			# than one means the picture is a coin flip; none means a lone cell
			# has no art and Godot picks whatever scores least badly.
			var any := false
			for bit in _bits():
				if data.get_terrain_peering_bit(bit) != -1:
					any = true
					break
			if not any:
				lone[key] = lone.get(key, 0) + 1

		var parts := []
		for key in per_terrain:
			parts.append("set:terrain %s = %d tiles (%d lone)" % [key, per_terrain[key], lone.get(key, 0)])

		print("source %d  %-34s %3d tiles, %d untagged, %d animated" % [
			id, texture_name, source.get_tiles_count(), untagged, animated])
		for p in parts:
			print("            ", p)

	print("
plantable soil candidates:")
	_check_plantable(tile_set)
	quit()

func _bits() -> Array:
	return [
		TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		TileSet.CELL_NEIGHBOR_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	]

# Checked because the code SetCells these directly rather than through terrain
# connect: they are the "ready to plant" soil, and a coord that is not a tile in
# the source draws nothing at all rather than erroring.
func _check_plantable(tile_set: TileSet) -> void:
	var source := tile_set.get_source(0) as TileSetAtlasSource
	for x in range(0, 4):
		var coords := Vector2i(x, 5)
		var exists := source.has_tile(coords)
		var terrain := -1
		if exists:
			var data := source.get_tile_data(coords, 0)
			terrain = data.terrain if data != null else -1
		print("  soil (%d,5)  tile:%s  terrain:%d" % [x, str(exists), terrain])
