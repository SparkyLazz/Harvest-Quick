extends SceneTree

## Bugs found in the November 2026 code review, each pinned by a check so it
## cannot quietly come back. Headless:
##   godot --headless --path . --script Tools/test_regressions.gd
##
## Classes that touch autoloads (HUD, the panels, Player) are only reached
## through instances here -- see TECH_NOTES "Traps already found".

var _fails := 0


func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1


func _initialize() -> void:
	await process_frame
	var cursor := root.get_node("MouseCursor")
	var fade := root.get_node("SceneTransition")

	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 4:
		await process_frame
	var hud = current_scene.get_node("HUD")
	var bag: Inventory = hud.inventory

	# --- a hotbar slot that empties and refills in one frame keeps its icon ---
	# Crafting spends the produce first and adds the seeds after, so the seeds
	# can land in the very slot the produce just left, inside the same frame.
	# The hotbar used to queue the old icon for freeing and then hand the new
	# item to that same doomed node, so the slot went blank at the end of the
	# frame while it still held three seeds.
	bag.set_slot(4, "tomato", 2)
	check(RecipeDB.make(_recipe_for("tomato"), bag), "two tomatoes thresh into seeds")
	check(bag.item_at(4) == "tomato_seed" and bag.count_at(4) == 3,
			"the seeds land in the slot the tomatoes left (%s x%d)" % [bag.item_at(4), bag.count_at(4)])
	for i in 3:
		await process_frame
	# The slot's contents are an InventorySlot laid over the plate, reached
	# untyped: naming that class here would break this script's compile.
	var slot: Control = hud._slots.get_child(4)
	var content = slot.get_node_or_null("Item")
	check(content != null and not content.is_queued_for_deletion() and content.visible
			and content.item == "tomato_seed",
			"and the hotbar still draws the seeds in that slot")
	check(content != null and content.count == 3,
			"with their count of 3 (%s)" % (content.count if content else "nothing"))
	bag.set_slot(4, "", 0)
	for i in 2:
		await process_frame
	content = slot.get_node_or_null("Item")
	check(content == null or content.item == "", "an emptied slot draws nothing")

	# --- closing a chest with a full bag never destroys the carried stack ----
	var key := "regression:0,0"
	hud.open_storage(key)
	await process_frame
	var storage = hud._storage
	var store: Inventory = storage._store
	_fill(bag, "wood")
	store.set_slot(0, "pumpkin", 5)
	storage._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(storage._carry_stack.item == "pumpkin", "a chest stack is on the cursor")
	await process_frame
	await process_frame
	check(cursor.shape() == cursor.Shape.GRAB, "and the cursor shows the closed paw while carrying it")
	hud.close_storage()
	var pumpkins: int = bag.count_of("pumpkin") + store.count_of("pumpkin")
	check(pumpkins == 5, "closing with a full bag puts it back in the chest (%d of 5 kept)" % pumpkins)
	await process_frame
	await process_frame
	check(cursor.shape() != cursor.Shape.GRAB, "and the paw opens again once the cursor is empty")

	# --- crafting with a stack on the cursor cannot push it out of the bag ----
	# The stack on the cursor came out of a bag slot. Crafting could fill that
	# slot behind its back, and closing then had nowhere to put it.
	var panel = hud._panel
	bag.set_slot(4, "wood", 99)
	_fill(bag, "wood")
	bag.set_slot(10, "tomato", 3)
	var wood_before: int = bag.count_of("wood")
	panel.open()
	panel._on_slot_pressed(20, MOUSE_BUTTON_LEFT)
	check(panel._carry_stack.item == "wood", "a bag stack is on the cursor")
	panel._show_tab(panel.TAB_CRAFTING)
	panel._select_recipe(_recipe_index(panel._recipes, "tomato"))
	panel._on_craft_pressed()
	panel.close()
	check(bag.count_of("wood") == wood_before,
			"crafting and closing keeps every log (%d of %d)" % [bag.count_of("wood"), wood_before])
	check(bag.count_of("tomato") + bag.count_of("tomato_seed") > 0, "and nothing else vanished either")

	# --- the profile rail does not rebuild its hearts every frame --------------
	panel.open()
	await process_frame
	var heart: TextureRect = panel._hearts.get_child(0)
	var drawn := heart.texture
	await process_frame
	await process_frame
	check(heart.texture == drawn, "an unchanged heart keeps its texture between frames")
	panel.close()

	# --- binding a panel twice does not wire its cursor twice ----------------
	hud.slot_items = hud.slot_items
	check(panel._carry_stack.changed.get_connections().size() == 1,
			"rebinding the profile screen leaves one cursor hook (%d)"
			% panel._carry_stack.changed.get_connections().size())

	# --- plain data rules ---------------------------------------------------------
	var inv := Inventory.new(2)
	inv.set_slot(0, "carrot", -3)
	check(inv.item_at(0) == "" and inv.count_at(0) == 0, "a negative count empties the slot")
	var carrot := ItemDB.info("carrot")
	check(carrot.is_read_only() and carrot == ItemDB.info("carrot"),
			"item info is shared and read-only, so no caller can corrupt it")
	check(ItemDB.info("no_such_item").is_empty(), "an unknown id is still empty")

	# --- a failed scene change hands the game back ----------------------------
	await fade.go_to("res://Scenes/NoSuchScene.tscn")
	check(not fade.is_busy() and not paused, "a scene that fails to load leaves the game running")

	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


func _recipe_for(crop: String) -> Dictionary:
	for recipe in RecipeDB.all():
		if recipe["costs"].has(crop):
			return recipe
	return {}


func _recipe_index(recipes: Array, crop: String) -> int:
	for i in recipes.size():
		if recipes[i]["costs"].has(crop):
			return i
	return 0


## Fills every empty slot with full stacks of `item`.
func _fill(inv: Inventory, item: String) -> void:
	for i in inv.size():
		if inv.item_at(i) == "":
			inv.set_slot(i, item, ItemDB.max_stack(item))
