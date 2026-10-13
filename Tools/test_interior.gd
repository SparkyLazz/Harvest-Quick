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
	var wardrobes: Array[Vector2i] = []
	var beds: Array[Vector2i] = []
	var rugs := 0
	for c in props.get_used_cells():
		var d := props.get_cell_tile_data(c)
		match str(d.get_custom_data("interact")):
			"wardrobe": wardrobes.append(c)
			"bed": beds.append(c)
		if d.get_collision_polygons_count(0) == 0:
			rugs += 1
	check(wardrobes.size() == 8, "the 8 dressers read as wardrobes (got %d)" % wardrobes.size())
	check(beds.size() == 2, "the bed's 2 cells read as a bed (got %d)" % beds.size())
	check(rugs > 0, "%d props stay walk-over (rugs, pictures)" % rugs)

	# --- each wardrobe is its own container ----------------------------------
	var state := root.get_node_or_null("/root/PlayerState")
	check(state != null, "PlayerState autoload is up")
	if state == null:
		print("")
		print("FAILURES: ", _fails)
		quit(1)
		return
	scene.scene_file_path = "res://Scenes/PlayerHouse.tscn"
	var k1: String = state.storage_key(scene, wardrobes[0])
	var k2: String = state.storage_key(scene, wardrobes[1])
	check(k1 != k2, "two wardrobes get different keys (%s vs %s)" % [k1, k2])
	var a: Inventory = state.storage_for(k1)
	var b: Inventory = state.storage_for(k2)
	a.set_slot(0, "wheat", 5)
	check(b.item_at(0) == "", "filling one wardrobe does not fill the other")
	check(state.storage_for(k1) == a, "asking again returns the same wardrobe")
	check(a.size() == 27, "a wardrobe holds 27 slots")

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

	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)
