extends SceneTree

## Checks the axe: the item, the swing, chopping a tree down to nothing,
## breaking decorations and growing grass back over hoed soil -- and that all of
## it is still that way after the map is unloaded and loaded again.
##   godot --headless --path . --script Tools/test_axe.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads are attached to the root after the main loop starts.
	await process_frame
	var scene: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var player = scene.get_node("Player")
	var hud := scene.get_node("HUD")
	var farm = scene.get_node("Farm")
	var grass := scene.get_node("Grass Layer") as TileMapLayer
	var soil := scene.get_node("Soil Layer") as TileMapLayer
	var bag: Inventory = hud.inventory

	# --- the item ------------------------------------------------------------
	var axe := ItemDB.info(ItemDB.AXE)
	check(axe.get("kind") == "tool" and axe.get("max_stack") == 1, "the axe is a single tool")
	check(axe.get("sheet") == ItemDB.EMOJI, "its icon comes off the same sheet as the hoe's")
	var wood := ItemDB.info(ItemDB.WOOD)
	check(wood.get("kind") == "material" and ItemDB.kind_label(ItemDB.WOOD) == "Material",
			"wood is a stackable material")
	check(bag.item_at(2) == ItemDB.AXE, "the starting hotbar holds the axe in slot 3")

	# --- the swing -----------------------------------------------------------
	var frames: SpriteFrames = player.sprite.sprite_frames
	for dir in ["down", "up", "left", "right"]:
		var anim := "axe_%s" % dir
		check(frames.has_animation(anim) and frames.get_frame_count(anim) == 8,
				"%s has its 8 frames" % anim)

	# --- trees ---------------------------------------------------------------
	var trees := get_nodes_in_group(&"choppable")
	check(trees.size() == 5, "5 trees on the island (got %d)" % trees.size())
	var on_grass := 0
	var cells := {}
	var tree_layer := scene.get_node("Trees") as TileMapLayer
	var painted := 0
	for t in trees:
		if t.get_parent() == tree_layer:
			painted += 1
	check(painted == trees.size(), "every tree was painted on the Trees layer")
	for t in trees:
		var c: Vector2i = t.cell_on(grass)
		cells[c] = true
		if grass.get_cell_tile_data(c) != null:
			on_grass += 1
	check(on_grass == trees.size(), "every tree stands on grass")
	check(cells.size() == trees.size(), "no two trees share a cell")

	# --- hoe, then axe: the grass comes back ---------------------------------
	player.set_physics_process(false)
	var spot := Vector2i(6, 9)
	_face(player, spot, "up")
	var grass_before := grass.get_cell_atlas_coords(spot)
	var grass_src := grass.get_cell_source_id(spot)
	var soil_before := soil.get_cell_atlas_coords(spot)
	hud.selected_slot = 2
	check(not player.can_use_at(spot), "the axe reads red on untouched grass")
	player._land_hoe_hit()
	check(grass.get_cell_tile_data(spot) == null and farm.is_tilled(spot), "hoe clears the grass")
	check(player.tilled_soil_tiles.has(soil.get_cell_atlas_coords(spot)), "hoe stamps tilled soil")
	check(player._can_axe(spot), "the axe can work the hoed cell")
	farm.water(spot)
	player._land_axe_hit()
	check(grass.get_cell_source_id(spot) == grass_src, "the grass grows back on its own layer")
	check(grass.get_cell_atlas_coords(spot) == grass_before,
			"with the same tile as before (%s, was %s)" % [grass.get_cell_atlas_coords(spot), grass_before])
	check(soil.get_cell_atlas_coords(spot) == soil_before, "the soil underneath is put back")
	check(not farm.is_tilled(spot) and not farm.is_wet(spot), "and the farm forgets the plot")
	check(not player._can_axe(spot), "an untouched cell gives the axe nothing to do")

	# A planted plot is left alone.
	player._land_hoe_hit()
	farm.plant(spot, "carrot")
	check(not player._can_axe(spot), "the axe won't dig up a crop")

	# --- decorations break: flowers, mushrooms, fences -----------------------
	var decor := scene.get_node("Decorations") as TileMapLayer
	var breakable := 0
	for c in decor.get_used_cells():
		if decor.get_cell_tile_data(c).get_custom_data("breakable"):
			breakable += 1
	check(breakable == decor.get_used_cells().size() and breakable > 0,
			"all %d decorations are marked breakable" % breakable)

	var flower := Vector2i(6, 2)
	_face(player, flower, "up")
	check(player.can_use_at(flower), "the cursor reads green on a flower")
	var wood_start := bag.count_of(ItemDB.WOOD)
	var grass_under := grass.get_cell_atlas_coords(flower)
	check(grass.get_cell_tile_data(flower) != null and not player._can_hoe(flower),
			"the hoe can't dig grass with a flower on it")
	player._land_hoe_hit()
	check(grass.get_cell_tile_data(flower) != null and not farm.is_tilled(flower),
			"and a swing there digs nothing")
	check(not player._can_hoe(Vector2i(9, 5)), "nor under the house")
	player._land_axe_hit()
	check(decor.get_cell_tile_data(flower) == null, "the axe breaks a flower")
	check(player._can_hoe(flower), "and then the grass can be hoed")
	check(grass.get_cell_atlas_coords(flower) == grass_under, "and leaves the grass under it alone")
	check(bag.count_of(ItemDB.WOOD) == wood_start, "a flower drops no wood")

	var mushroom := Vector2i(2, 7)
	_face(player, mushroom, "left")
	player._land_axe_hit()
	check(decor.get_cell_tile_data(mushroom) == null, "the axe breaks a mushroom")

	var post := Vector2i(10, 14)
	check(decor.get_cell_tile_data(post).get_collision_polygons_count(0) > 0, "a fence blocks")
	_face(player, post, "down")
	player._land_axe_hit()
	check(not player._can_hoe(post + Vector2i.LEFT), "the hoe can't dig under a fence")
	check(decor.get_cell_tile_data(post) == null, "the axe breaks a fence piece")
	check(bag.count_of(ItemDB.WOOD) == wood_start + 1, "which gives 1 wood")
	check(decor.get_cell_atlas_coords(post + Vector2i.LEFT) == Vector2i(3, 3)
			and decor.get_cell_atlas_coords(post + Vector2i.RIGHT) == Vector2i(1, 3),
			"the fence on either side re-fits into end posts (%s, %s)"
			% [decor.get_cell_atlas_coords(post + Vector2i.LEFT), decor.get_cell_atlas_coords(post + Vector2i.RIGHT)])
	check(not player._can_axe(post), "and the gap gives the axe nothing more")

	# --- a full swing through the real input path ----------------------------
	var tree = trees[0]
	var tree_cell: Vector2i = tree.cell_on(grass)
	_face(player, tree_cell, "up")
	check(player.facing_cell() == tree_cell, "standing below the tree faces its cell")
	check(player.tree_at(tree_cell) == tree, "and finds the tree there")
	check(not player._can_hoe(tree_cell), "the hoe can't dig where a tree stands")
	check(player.can_use_at(tree_cell), "the cursor reads green on a tree with the axe out")
	var stamina: float = player.stamina
	player.set_physics_process(true)
	check(player._start_action("axe", Vector2.ZERO), "the swing starts")
	check(player.sprite.animation == &"axe_up", "and plays the upward chop")
	await _until(func() -> bool: return player._action.is_empty(), 3.0)
	check(is_equal_approx(player.stamina, stamina - player.axe_cost), "a chop that lands costs stamina")
	check(tree._hits == 1, "and lands one hit")
	player.set_physics_process(false)

	# --- felling it: wood, then a stump, then nothing -------------------------
	var wood_before := bag.count_of(ItemDB.WOOD)
	player._land_axe_hit()                     # hit 2: shakes
	check(bag.count_of(ItemDB.WOOD) == wood_before, "a shake gives no wood")
	player._land_axe_hit()                     # hit 3: falls
	check(bag.count_of(ItemDB.WOOD) == wood_before + tree.wood, "felling gives %d wood" % tree.wood)
	check(not tree.can_chop() and not player.can_use_at(tree_cell), "no chopping mid-fall")
	await _until(func() -> bool: return tree.is_stump(), 3.0)
	check(tree.is_stump() and tree.can_chop(), "the fall ends on a stump that can be chopped")
	check(not player._can_hoe(tree_cell), "nor where its stump is")
	player._land_axe_hit()
	check(bag.count_of(ItemDB.WOOD) == wood_before + tree.wood + tree.stump_wood,
			"the stump gives %d more" % tree.stump_wood)
	check(player.tree_at(tree_cell) == null, "leaving the cell clear")
	var tree_id: int = tree.get_instance_id()
	await _until(func() -> bool: return not is_instance_id_valid(tree_id), 1.0)
	check(not is_instance_id_valid(tree_id), "and is gone")
	check(tree_layer.get_cell_source_id(tree_cell) == -1, "its tile is erased from the layer too")
	check(player._can_hoe(tree_cell), "and the cleared ground can be hoed")

	# Leave one tree half-chopped and fell another to a stump before leaving.
	var bruised = trees[1]
	var bruised_cell: Vector2i = bruised.cell_on(grass)
	_face(player, bruised_cell, "up")
	player._land_axe_hit()
	var felled = trees[2]
	var felled_cell: Vector2i = felled.cell_on(grass)
	_face(player, felled_cell, "up")
	for i in felled.hits_to_fell:
		player._land_axe_hit()
	var soil_stamp := soil.get_cell_atlas_coords(spot)
	var fence_left := decor.get_cell_atlas_coords(post + Vector2i.LEFT)
	var wood_kept := bag.count_of(ItemDB.WOOD)

	# --- walk away and come back: the map is as it was left -----------------
	root.remove_child(scene)
	scene.free()
	await process_frame
	scene = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	grass = scene.get_node("Grass Layer") as TileMapLayer
	soil = scene.get_node("Soil Layer") as TileMapLayer
	decor = scene.get_node("Decorations") as TileMapLayer
	tree_layer = scene.get_node("Trees") as TileMapLayer
	farm = scene.get_node("Farm")
	player = scene.get_node("Player")
	check(grass.get_cell_tile_data(spot) == null, "hoed ground is still bare")
	check(soil.get_cell_atlas_coords(spot) == soil_stamp, "with the same soil tile")
	check(farm.is_tilled(spot) and farm.has_crop(spot), "and the carrot is still planted in it")
	check(decor.get_cell_tile_data(flower) == null and decor.get_cell_tile_data(mushroom) == null,
			"broken flowers and mushrooms stay broken")
	check(decor.get_cell_tile_data(post) == null and
			decor.get_cell_atlas_coords(post + Vector2i.LEFT) == fence_left,
			"the fence keeps its gap and its re-fitted ends")
	check(tree_layer.get_cell_source_id(tree_cell) == -1 and player.tree_at(tree_cell) == null,
			"the cleared tree does not grow back")
	var again = player.tree_at(bruised_cell)
	check(again != null and again._hits == 1, "the half-chopped tree remembers its hit")
	var stump = player.tree_at(felled_cell)
	check(stump != null and stump.is_stump(), "the felled tree comes back as a stump")
	check(get_nodes_in_group(&"choppable").size() == 4, "4 trees left on the island")
	check(scene.get_node("HUD").inventory.count_of(ItemDB.WOOD) == wood_kept, "the wood is still in the bag")
	player.set_physics_process(false)
	_face(player, spot, "up")
	check(not player._can_axe(spot), "the replanted plot still guards its crop from the axe")

	# --- icons: the slot and the pop-out wear different art ------------------
	check(wood["sheet"] == ItemDB.EMOJI and wood["drop_sheet"] == ItemDB.DROP_SHEET,
			"wood sits in its slot as the emoji log and pops out as the outlined one")
	var acorn := ItemDB.info(ItemDB.ACORN)
	check(acorn["sheet"] == ItemDB.DROP_SHEET_PLAIN and acorn["drop_sheet"] == ItemDB.DROP_SHEET
			and acorn["region"] == acorn["drop_region"], "seeds use the halo-less copy of their sprite in a slot")
	var carrot := ItemDB.info("carrot")
	check(carrot["drop_sheet"] == carrot["sheet"], "crops pop out as their usual icon")

	# --- every kind of tree, and what each one drops --------------------------
	var kinds := {"oak": ItemDB.ACORN, "birch": ItemDB.BIRCH_POD,
			"cherry": ItemDB.CHERRY_PIT, "pine": ItemDB.PINECONE}
	var painted_kinds := {}
	for t in get_nodes_in_group(&"choppable"):
		painted_kinds[t.species] = true
	check(painted_kinds.size() >= 3, "the island grows a mix of kinds (%s)" % [painted_kinds.keys()])
	var x := 0
	for kind: String in kinds:
		var path := "res://Scenes/Tree.tscn" if kind == "oak" else "res://Scenes/Tree_%s.tscn" % kind.capitalize()
		var sapling = load(path).instantiate()
		sapling.position = Vector2(-400 - x * 32, -400)
		x += 1
		scene.add_child(sapling)
		await process_frame
		check(sapling.species == kind, "%s grows from its own scene" % kind)
		var anims: PackedStringArray = sapling._sprite.sprite_frames.get_animation_names()
		check(anims.has("idle") and (anims.has("fall") or anims.has("stump")), "%s has its frames" % kind)
		sapling.seed_chance = 1.0
		var got: Array = []
		for i in sapling.hits_to_fell:
			got.append_array(sapling.chop())
		var items := got.map(func(d: Dictionary) -> String: return d["item"])
		check(items.has(ItemDB.WOOD) and items.has(kinds[kind]),
				"a felled %s gives wood and its %s" % [kind, ItemDB.display_name(kinds[kind])])
		var sapling_id: int = sapling.get_instance_id()
		await _until(func() -> bool: return instance_from_id(sapling_id).is_stump(), 3.0)
		check(sapling.is_stump() and sapling.can_chop(), "%s ends on a stump" % kind)
		sapling.free()

	# --- tree seeds: plant, grow, keep growing across visits -----------------
	check(ItemDB.info(ItemDB.ACORN)["kind"] == "tree_seed" and ItemDB.kind_label(ItemDB.ACORN) == "Tree Seed"
			and not ItemDB.is_seed(ItemDB.ACORN), "tree seeds are their own kind, not crop seeds")
	check(ItemDB.info(ItemDB.PINECONE)["tree"] == "pine", "a pinecone grows a pine")
	bag = scene.get_node("HUD").inventory
	hud = scene.get_node("HUD")
	bag.set_slot(8, ItemDB.ACORN, 3)
	hud.selected_slot = 8
	check(not player.can_plant_tree(spot, ItemDB.ACORN), "no planting a tree in tilled soil")
	check(not player.can_plant_tree(post + Vector2i.LEFT, ItemDB.ACORN), "nor under a fence")
	check(not player.can_plant_tree(felled_cell, ItemDB.ACORN), "nor on a stump")
	var plot := Vector2i(14, 8)
	check(player.can_plant_tree(plot, ItemDB.ACORN), "open grass takes a seed")
	_face(player, plot, "up")
	check(player.can_use_at(plot), "and the cursor says so")
	check(player._try_plant_tree(ItemDB.ACORN, Vector2.ZERO), "planting the acorn")
	await process_frame
	await process_frame
	var oak = player.tree_at(plot)
	check(oak != null and oak.species == "oak" and oak.is_young() and oak.stage() == 0,
			"a planted seed comes up as stage 0 of an oak")
	check(bag.count_of(ItemDB.ACORN) == 2, "and uses up the acorn")
	check(oak.get_node("Trunk").disabled, "a young tree doesn't block the way")
	check(not player._can_hoe(plot) and not player.can_plant_tree(plot, ItemDB.ACORN),
			"nor can the cell be hoed or planted again")
	# Trees grow overnight, a stage a night.
	for i in oak.YOUNG_STAGES:
		root.get_node("PlayerState").sleep()
	await process_frame
	check(not oak.is_young() and not oak.get_node("Trunk").disabled, "it grows into a full tree that blocks")
	_face(player, plot, "up")
	var wood_now := bag.count_of(ItemDB.WOOD)
	for i in oak.hits_to_fell:
		player._land_axe_hit()
	check(bag.count_of(ItemDB.WOOD) == wood_now + oak.wood, "and gives wood like any other")

	# A sapling the axe pulls up comes back as its seed.
	var sprout_cell := Vector2i(14, 10)
	_face(player, sprout_cell, "up")
	player._try_plant_tree(ItemDB.ACORN, Vector2.ZERO)
	await process_frame
	await process_frame
	var acorns := bag.count_of(ItemDB.ACORN)
	player._land_axe_hit()
	check(bag.count_of(ItemDB.ACORN) == acorns + 1, "the axe pulls up a sapling, seed and all")
	await process_frame
	await process_frame
	check(player.tree_at(sprout_cell) == null, "leaving the grass open")

	# Growth is kept across a visit, and nights away count.
	bag.set_slot(8, ItemDB.BIRCH_POD, 1)
	var grove := Vector2i(12, 9)
	_face(player, grove, "up")
	player._try_plant_tree(ItemDB.BIRCH_POD, Vector2.ZERO)
	await process_frame
	await process_frame
	root.get_node("PlayerState").sleep()
	root.get_node("PlayerState").day += 2
	root.remove_child(scene)
	scene.free()
	await process_frame
	scene = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	player = scene.get_node("Player")
	var birch = player.tree_at(grove)
	check(birch != null and birch.species == "birch", "the planted birch is still there after a visit")
	check(birch != null and birch.stage() == 3, "at stage 1 plus two nights slept (got %s)"
			% (birch.stage() if birch else "none"))
	check(player.tree_at(plot) != null and player.tree_at(plot).is_stump(),
			"and the grown oak's stump is where it was felled")

	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


## Stands the player one tile back from `target` along `facing`.
func _face(player, target: Vector2i, facing: String) -> void:
	var step: Vector2i = player.FACING_DIRS[facing]
	player._facing = facing
	player.global_position = player.cell_center(target - step) + Vector2(0, 4)


func _until(done: Callable, timeout: float) -> void:
	var left := timeout
	while not done.call() and left > 0.0:
		await process_frame
		left -= 1.0 / 60.0
