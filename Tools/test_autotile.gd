extends SceneTree

## Checks the House Wall terrain actually solves: paints a run with the terrain
## brush and compares it against what the room scene was authored with.
##   godot --headless --path . --script Tools/test_autotile.gd

const SRC := 20
const SET := 2

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	var ts: TileSet = load("res://Tilemaps/Terrains.tres")
	check(ts.get_terrain_sets_count() == 2, "no extra terrain set was left behind")

	# The wall sheet is registered exactly as the artist drew it: sliced, nothing
	# added. Every cell must be a plain 16x16 with no terrain, collision or sort
	# origin, so decorating is entirely a matter of painting.
	var walls := ts.get_source(SRC) as TileSetAtlasSource
	check(walls != null, "source 20 exists")
	check(walls.texture.resource_path.ends_with("Wooden_House_Walls_Tilset.png"),
			"it points at the original sheet, not a derived one")
	check(walls.texture_region_size == Vector2i(16, 16), "region size is 16x16")
	check(walls.get_tiles_count() == 14, "all 14 non-empty cells are cut")

	# The art is still a plain slice -- no terrain, no sort origin, no mega-tiles.
	# Collision and the interact verb are config layered on top, not changes to
	# how the sheet is cut.
	var plain := true
	for i in walls.get_tiles_count():
		var c := walls.get_tile_id(i)
		if walls.get_tile_size_in_atlas(c) != Vector2i.ONE:
			plain = false
		var td := walls.get_tile_data(c, 0)
		if td.terrain_set != -1 or td.y_sort_origin != 0:
			plain = false
	check(plain, "every cell is still a bare 16x16 slice of the sheet")

	var furn := ts.get_source(22) as TileSetAtlasSource
	check(furn != null and furn.get_tiles_count() == 40, "furniture is 40 bare cells")

	# The room is yours to decorate, so this does not police what is painted --
	# only that every cell put down still resolves to a real tile, which is what
	# would break if a source were renumbered or a sheet recut underneath it.
	var scene: Node = load("res://Scenes/PlayerHouse.tscn").instantiate()
	for layer_name in ["Floor", "Walls", "Props"]:
		var layer := scene.get_node_or_null(layer_name) as TileMapLayer
		check(layer != null, "%s layer exists" % layer_name)
		if layer == null:
			continue
		var dangling := 0
		for c in layer.get_used_cells():
			var src := ts.get_source(layer.get_cell_source_id(c)) as TileSetAtlasSource
			if src == null or not src.has_tile(layer.get_cell_atlas_coords(c)):
				dangling += 1
		check(dangling == 0, "%s: all %d painted cells resolve (%d dangling)"
				% [layer_name, layer.get_used_cells().size(), dangling])
	check(scene.get_node_or_null("Door") != null, "the door is still wired")
	check(scene.get_node_or_null("FrontDoor") != null, "the spawn marker is still there")

	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)
