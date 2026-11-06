extends SceneTree

## Checks the house's collision, its furniture verbs and the state behind them.
##   godot --headless --path . --script Tools/test_interior.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads are attached to the root after the main loop starts, so nothing
	# under /root exists yet on the very first call.
	await process_frame
	var scene: Node = load("res://Scenes/PlayerHouse.tscn").instantiate()
	var floor_l := scene.get_node("Floor") as TileMapLayer
	var walls := scene.get_node("Walls") as TileMapLayer
	var props := scene.get_node("Props") as TileMapLayer

	# --- collision now comes off the tiles, not hand-placed boxes ------------
	var open_floor := 0
	for c in floor_l.get_used_cells():
		if floor_l.get_cell_tile_data(c).get_collision_polygons_count(0) == 0:
			open_floor += 1
	check(open_floor == floor_l.get_used_cells().size(),
			"all %d floor cells are walkable" % open_floor)

	var solid := 0
	for c in walls.get_used_cells():
		if walls.get_cell_tile_data(c).get_collision_polygons_count(0) > 0:
			solid += 1
	check(solid == walls.get_used_cells().size(),
			"all %d wall cells block" % walls.get_used_cells().size())

	# Hitboxes follow the art, not the cell: several wall pieces are a thin post.
	var narrow := 0
	for c in walls.get_used_cells():
		var poly := walls.get_cell_tile_data(c).get_collision_polygon_points(0, 0)
		if poly[1].x - poly[0].x < 16.0:
			narrow += 1
	check(narrow > 0, "%d wall cells use a hitbox narrower than their cell" % narrow)

	# --- furniture carries its own verb --------------------------------------
	# Found by verb rather than by cell, so moving the furniture around the
	# room does not break the test (the old one expected 8 dressers that the
	# redesigned house no longer has).
	var containers: Array[Vector2i] = []
	var beds: Array[Vector2i] = []
	var rugs := 0
	for c in props.get_used_cells():
		var d := props.get_cell_tile_data(c)
		match str(d.get_custom_data("interact")):
			"chest", "wardrobe": containers.append(c)
			"bed": beds.append(c)
		if d.get_collision_polygons_count(0) == 0:
			rugs += 1
	check(containers.size() >= 2, "the house has %d storage props" % containers.size())
	check(beds.size() == 2, "the bed's 2 cells read as a bed (got %d)" % beds.size())
	check(rugs > 0, "%d props stay walk-over (rugs, pictures)" % rugs)
	# The house paints no dresser at the moment, but the tileset still tags
	# one: paint it somewhere and make sure the verb comes with it.
	var dresser := _tile_with_verb(props.tile_set, "wardrobe")
	check(dresser.size() == 2, "the tileset carries a tile tagged as a wardrobe")
	if dresser.size() == 2:
		var spot := Vector2i(-40, -40)
		props.set_cell(spot, dresser[0], dresser[1])
		check(str(props.get_cell_tile_data(spot).get_custom_data("interact")) == "wardrobe",
				"a painted dresser reads as a wardrobe")
		props.erase_cell(spot)

	# --- each wardrobe is its own container ----------------------------------
	var state := root.get_node_or_null("/root/PlayerState")
	check(state != null, "PlayerState autoload is up")
	if state == null:
		print("")
		print("FAILURES: ", _fails)
		quit(1)
		return
	scene.scene_file_path = "res://Scenes/PlayerHouse.tscn"
	var k1: String = state.storage_key(scene, containers[0])
	var k2: String = state.storage_key(scene, containers[1])
	check(k1 != k2, "two containers get different keys (%s vs %s)" % [k1, k2])
	var a: Inventory = state.storage_for(k1)
	var b: Inventory = state.storage_for(k2)
	a.set_slot(0, "wheat", 5)
	check(b.item_at(0) == "", "filling one container does not fill the other")
	check(state.storage_for(k1) == a, "asking again returns the same container")
	check(a.size() == 27, "a container holds 27 slots")

	# --- sleeping ------------------------------------------------------------
	state.max_stamina = 100.0
	state.put_stamina(12.0)
	var before: int = state.day
	state.sleep()
	check(state.day == before + 1, "sleeping moves the day on")
	check(is_equal_approx(state.stamina, 100.0), "sleeping refills stamina")

	# --- the shared cursor rules --------------------------------------------
	var bag := Inventory.new(9)
	var box := Inventory.new(27)
	var cursor := CarriedStack.new()

	bag.set_slot(0, "wheat", 10)
	cursor.left_click(bag, 0)
	check(cursor.item == "wheat" and cursor.count == 10, "left click lifts the whole stack")
	check(bag.item_at(0) == "", "and empties the slot")

	cursor.left_click(box, 4)
	check(box.item_at(4) == "wheat" and box.count_at(4) == 10, "it drops into the wardrobe")
	check(cursor.is_empty(), "cursor is empty after dropping")

	cursor.right_click(box, 4)
	check(cursor.count == 5 and box.count_at(4) == 5, "right click splits the stack in half")
	cursor.right_click(box, 5)
	check(box.count_at(5) == 1 and cursor.count == 4, "right click puts down one at a time")
	cursor.spill_into(bag)
	check(cursor.is_empty() and bag.count_of("wheat") == 4, "closing returns the cursor to the bag")

	# swap: cursor holds one thing, slot holds another
	bag.set_slot(1, "hoe", 1)
	cursor.left_click(bag, 1)
	box.set_slot(0, "carrot", 3)
	cursor.left_click(box, 0)
	check(box.item_at(0) == "hoe" and cursor.item == "carrot" and cursor.count == 3,
			"left click swaps when both are full")

	cursor.set_to("", 0)
	var stashed := box.count_at(4)
	check(cursor.quick_move(box, 4, bag), "shift click moves a stack across")
	check(box.item_at(4) == "" and bag.count_of("wheat") == 4 + stashed,
			"and the whole stack arrives")

	# A stack with nowhere to go stays on the cursor instead of vanishing.
	var full := Inventory.new(1)
	full.set_slot(0, "wood", 99)
	cursor.set_to("carrot", 3)
	check(cursor.spill_into(full) == 3 and cursor.item == "carrot" and cursor.count == 3,
			"spilling into a full bag keeps the stack on the cursor")
	check(cursor.spill_into(box) == 0 and cursor.is_empty(), "and the next container takes it")

	scene.free()
	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)


## The first [source id, atlas coords] in `tiles` whose "interact" is `verb`.
func _tile_with_verb(tiles: TileSet, verb: String) -> Array:
	for i in tiles.get_source_count():
		var id := tiles.get_source_id(i)
		var source := tiles.get_source(id) as TileSetAtlasSource
		if source == null:
			continue
		for t in source.get_tiles_count():
			var coords := source.get_tile_id(t)
			var data := source.get_tile_data(coords, 0)
			if data != null and str(data.get_custom_data("interact")) == verb:
				return [id, coords]
	return []
