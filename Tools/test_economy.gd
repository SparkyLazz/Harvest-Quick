extends SceneTree

## Step 2, first income: coins, the shipping bin, the seed shop and crop
## seasons. Headless:
##   godot --headless --path . --script Tools/test_economy.gd
##
## HUD, Player, Farm and the panels are reached through instances only -- a
## --script test cannot name classes that touch autoloads (TECH_NOTES, traps).

var _fails := 0


func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1


func _initialize() -> void:
	await process_frame
	var state := root.get_node("PlayerState")

	# --- prices and seasons -------------------------------------------------------
	var priced := true
	for crop: String in CropDB.CROPS:
		var c: Dictionary = CropDB.CROPS[crop]
		priced = priced and c["price"] > c["seed"] and c["seed"] > 0 and not c["seasons"].is_empty() \
				and ItemDB.sell_price(crop) == c["price"] \
				and ItemDB.buy_price(ItemDB.seed_id(crop)) == c["seed"] \
				and ItemDB.sell_price(ItemDB.seed_id(crop)) == c["seed"] / 2
	check(priced, "every crop sells for more than its packet, and packets sell back at half")
	check(ItemDB.sell_price(ItemDB.HOE) == 0 and ItemDB.buy_price(ItemDB.HOE) == 0,
			"tools are neither bought nor sold")
	check(ItemDB.sell_price(ItemDB.WOOD) > 0 and ItemDB.sell_price(ItemDB.ACORN) > 0,
			"wood and tree seeds can be shipped")
	check(CropDB.in_season(3).is_empty(), "nothing grows in Winter")
	# What Tools/econ_sim.py assumes a planted tile earns a day, per season.
	for season in 3:
		var per_day := 0.0
		for crop in CropDB.in_season(season):
			per_day += float(CropDB.CROPS[crop]["price"]) / CropDB.days_to_ripen(crop)
		per_day /= CropDB.in_season(season).size()
		var target: float = [6.0, 9.0, 10.0][season]
		check(absf(per_day - target) <= target * 0.1, "%s crops earn %.1f a tile a day (sim assumes %d)"
				% [Calendar.SEASONS[season], per_day, target])
	check(ItemDB.describe("carrot_seed").contains("Spring") and ItemDB.describe("carrot").contains("24"),
			"tooltips give a seed's season and a crop's price")

	# --- the purse --------------------------------------------------------------------
	check(state.coins == state.START_COINS, "a new game starts with %d coins" % state.START_COINS)
	var heard := []
	state.coins_changed.connect(func(c: int) -> void: heard.append(c))
	check(not state.spend(state.coins + 1) and state.coins == state.START_COINS,
			"spending more than you have takes nothing")
	state.earn(50)
	check(state.coins == state.START_COINS + 50 and heard == [state.START_COINS + 50],
			"earning adds to the purse and says so")
	check(state.spend(50) and state.coins == state.START_COINS, "spending takes it back out")

	# --- the farm's two new props ------------------------------------------------------
	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 6:
		await process_frame
	var scene := current_scene
	var hud = scene.get_node("HUD")
	var player = scene.get_node("Player")
	var farm = scene.get_node("Farm")
	var props := scene.get_node_or_null("Props") as TileMapLayer
	check(props != null, "the farm has a Props layer")
	var bin_cell := _cell_with_verb(props, "ship")
	var sign_cell := _cell_with_verb(props, "shop")
	check(bin_cell != Vector2i(-1, -1) and sign_cell != Vector2i(-1, -1),
			"it holds a shipping bin (%s) and a seed-shop sign (%s)" % [bin_cell, sign_cell])
	check(hud.get_node("Screen/Status").amount_text() == str(state.coins),
			"the purse on the status sign reads %d" % state.coins)

	# --- the shipping bin ------------------------------------------------------------
	await _use(player, props, bin_cell)
	var panel = hud._storage
	check(hud.is_storage_open() and panel.storage_key == state.SHIPPING_KEY,
			"using the bin opens the shipping window")
	var bag: Inventory = hud.inventory
	var bin: Inventory = panel._store
	# Pick the hoe up off the bag and try to put it in the bin.
	panel._player_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(bin.item_at(0) == "" and panel._carry_stack.item == ItemDB.HOE,
			"the bin will not take a tool: the hoe stays on the cursor")
	panel._player_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(bag.item_at(0) == ItemDB.HOE, "and goes back where it was")
	check(bin.add(ItemDB.HOE, 1) == 1, "nor can anything else push one in")
	bag.set_slot(8, "carrot", 5)
	panel._player_slots[8].pressed.emit(8, MOUSE_BUTTON_LEFT)
	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(bin.count_of("carrot") == 5, "five carrots go in")
	check(panel._right_heading.text == "SELLS FOR 120", "and the bin says what they will fetch (%s)"
			% panel._right_heading.text)
	hud.close_storage()
	await _settle_lid(player, props, bin_cell)
	var earned := []
	state.shipped.connect(func(n: int) -> void: earned.append(n))
	var before: int = state.coins
	state.sleep()
	check(state.coins == before + 120 and earned == [120], "overnight they are sold: +120 coins")
	check(bin.count_of("carrot") == 0, "and the bin is empty in the morning")
	await process_frame
	check(hud.get_node("Screen/Status").amount_text() == str(state.coins),
			"and the sign shows the new amount")

	# --- the seed shop ------------------------------------------------------------------
	state.day = 1
	await _use(player, props, sign_cell)
	check(hud.is_storage_open() and panel._shop, "using the sign opens the seed shop")
	var stock: Array = []
	for slot in panel._store_slots:
		if slot.visible and slot.item != "":
			stock.append(slot.item)
	var spring := CropDB.in_season(0).map(func(c: String) -> String: return ItemDB.seed_id(c))
	check(stock == spring, "in Spring it sells Spring seeds (%s)" % [stock])
	check(panel._store_slots[0].price == ItemDB.buy_price(stock[0]), "each with its price")
	var seed: String = stock[0]
	var had: int = bag.count_of(seed)
	var coins_before: int = state.coins
	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(bag.count_of(seed) == had + 1 and state.coins == coins_before - ItemDB.buy_price(seed),
			"a click buys one packet for its price")
	panel._buy(0, 5)
	check(bag.count_of(seed) == had + 6, "a batch buys five")
	state.coins = ItemDB.buy_price(seed) - 1
	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(bag.count_of(seed) == had + 6 and state.coins == ItemDB.buy_price(seed) - 1,
			"with too few coins nothing is bought")
	state.coins = 10000
	var real_bag: Inventory = hud.inventory
	_fill(real_bag, "wood")
	var full_before: int = state.coins
	panel._store_slots[1].pressed.emit(1, MOUSE_BUTTON_LEFT)
	check(state.coins == full_before, "with no room in the bag nothing is bought or charged")
	hud.close_storage()
	state.day = 85
	hud.open_shop()
	var shown: int = panel._store_slots.filter(func(s) -> bool: return s.visible).size()
	check(shown == 0 and panel._right_heading.text == "NOTHING GROWS IN WINTER",
			"in Winter the stall is empty and says why")
	hud.close_storage()

	# --- planting only in season -----------------------------------------------------------
	for i in real_bag.size():
		real_bag.set_slot(i, "", 0)
	real_bag.set_slot(0, "corn_seed", 5)
	hud.selected_slot = 0
	var plot := Vector2i(3, 8)
	farm._on_tilled(plot)
	state.day = 10
	check(not player.can_use_at(plot), "corn is a Summer crop: no planting it in Spring")
	state.day = 40
	check(player.can_use_at(plot), "but in Summer it goes in")

	# --- the season turns -------------------------------------------------------------------
	var spring_plot := Vector2i(4, 8)
	var summer_plot := Vector2i(5, 8)
	farm._on_tilled(spring_plot)
	farm._on_tilled(summer_plot)
	state.day = 28
	farm.plant(spring_plot, "carrot")
	state.sleep()
	check(state.day == 29 and not farm.has_crop(spring_plot) and farm.is_tilled(spring_plot),
			"on the first morning of Summer the Spring carrots are gone, the soil still tilled")
	state.day = 56
	farm.plant(summer_plot, "corn")
	state.sleep()
	check(farm.has_crop(summer_plot), "corn grows in Summer and Fall, so it lives into Fall")
	# Away when the season turns: the farm catches up when it comes back.
	var away_plot := Vector2i(6, 8)
	farm._on_tilled(away_plot)
	state.day = 82
	farm.plant(away_plot, "pumpkin")
	root.remove_child(scene)
	scene.free()
	for i in 4:
		state.sleep()
	check(state.day == 86, "four nights away, it is Winter")
	scene = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	farm = scene.get_node("Farm")
	check(not farm.has_crop(away_plot) and not farm.has_crop(summer_plot),
			"and the farm comes back with its Fall crops dead")

	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


func _cell_with_verb(props: TileMapLayer, verb: String) -> Vector2i:
	if props == null:
		return Vector2i(-1, -1)
	for cell in props.get_used_cells():
		var data := props.get_cell_tile_data(cell)
		if data != null and str(data.get_custom_data("interact")) == verb:
			return cell
	return Vector2i(-1, -1)


## Stands the player on the cell in front of `cell`, facing it, and uses it.
func _use(player: Node2D, props: TileMapLayer, cell: Vector2i) -> void:
	player.global_position = props.to_global(props.map_to_local(cell + Vector2i.DOWN))
	player._facing = "up"
	for i in 3:
		await process_frame
	player._try_interact(Vector2.ZERO)
	await _settle_lid(player, props, cell)


func _settle_lid(player: Node2D, props: TileMapLayer, cell: Vector2i) -> void:
	if player._prop_anim != null and player._prop_anim.is_moving(cell):
		await player._prop_anim.finished
	for i in 3:
		await process_frame


func _fill(inv: Inventory, item: String) -> void:
	for i in inv.size():
		if inv.item_at(i) == "":
			inv.set_slot(i, item, ItemDB.max_stack(item))
