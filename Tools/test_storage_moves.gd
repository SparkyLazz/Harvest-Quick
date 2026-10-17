extends SceneTree

## The storage screen's click rules, driven through the real slots.
##
## Every check goes through a slot's own `pressed` signal rather than calling
## CarriedStack directly, because the rules themselves are already tested by
## their owner -- what is worth testing here is the wiring: that the left grid
## really is the bag and the right grid really is the furniture, and that a
## stack can cross between them without being duplicated or eaten.
##
## Run windowed; the window has to be up for its slots to exist.

var _checks := 0
var _failures := 0


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	var hud: Node = scene.find_child("HUD", true, false)
	var chest := _first(props, "chest")

	player.global_position = props.to_global(props.map_to_local(chest + Vector2i.DOWN))
	player._facing = "up"
	for i in 10:
		await process_frame
	player._try_interact(Vector2.ZERO)
	if player._prop_anim.is_moving(chest):
		await player._prop_anim.finished
	for i in 10:
		await process_frame

	var panel = hud._storage
	var bag: Inventory = hud.inventory
	var store: Inventory = panel._store
	var carry = panel._carry_stack

	# --- the two grids are wired to the right inventories ---------------------
	bag.set_slot(0, "carrot", 7)
	store.set_slot(0, "", 0)
	panel._player_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(carry.item == "carrot" and carry.count == 7,
			"left click on the bag picks up its stack (%s x%d)" % [carry.item, carry.count])
	check(bag.item_at(0) == "", "and the bag slot is emptied")

	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_LEFT)
	check(store.item_at(0) == "carrot" and store.count_at(0) == 7,
			"putting it down lands in the chest, not the bag (%s x%d)"
			% [store.item_at(0), store.count_at(0)])
	check(carry.is_empty(), "and the cursor is empty again")

	# --- right click splits and places one -----------------------------------
	panel._store_slots[0].pressed.emit(0, MOUSE_BUTTON_RIGHT)
	check(carry.count == 4 and store.count_at(0) == 3,
			"right click takes half, rounded up (%d up, %d left)"
			% [carry.count, store.count_at(0)])
	# A slot the starting loadout does not fill. Dropping onto an occupied one
	# tests nothing: the watering can in slot 1 has a count of 1 all by itself,
	# so "one was placed" reads as true whether anything happened or not.
	const FREE := 20
	bag.set_slot(FREE, "", 0)
	panel._player_slots[FREE].pressed.emit(FREE, MOUSE_BUTTON_RIGHT)
	check(bag.item_at(FREE) == "carrot" and bag.count_at(FREE) == 1 and carry.count == 3,
			"and puts down one at a time (%s x%d placed, %d held)"
			% [bag.item_at(FREE), bag.count_at(FREE), carry.count])
	carry.spill_into(bag)

	# --- the item never multiplies or vanishes --------------------------------
	var total := bag.count_of("carrot") + store.count_of("carrot")
	check(total == 7, "seven carrots went in and %d came out" % total)

	# --- shift sends a stack across ------------------------------------------
	bag.set_slot(2, "corn", 5)
	store.set_slot(1, "", 0)
	await _hold_shift(true)
	panel._player_slots[2].pressed.emit(2, MOUSE_BUTTON_LEFT)
	check(bag.item_at(2) == "" and store.count_of("corn") == 5,
			"shift click sends a bag stack to the chest (chest holds %d)"
			% store.count_of("corn"))
	var where := _slot_of(store, "corn")
	panel._store_slots[where].pressed.emit(where, MOUSE_BUTTON_LEFT)
	check(store.count_of("corn") == 0 and bag.count_of("corn") == 5,
			"and sends it back again (bag holds %d)" % bag.count_of("corn"))
	check(carry.is_empty(), "without it ever touching the cursor")
	await _hold_shift(false)

	# --- closing never eats what is on the cursor -----------------------------
	bag.set_slot(3, "wheat", 4)
	panel._player_slots[3].pressed.emit(3, MOUSE_BUTTON_LEFT)
	check(not carry.is_empty(), "a stack is on the cursor")
	hud.close_storage()
	for i in 10:
		await process_frame
	check(carry.is_empty() and bag.count_of("wheat") == 4,
			"closing the window puts it back in the bag (%d wheat)"
			% bag.count_of("wheat"))

	# --- the chest keeps what was left in it ----------------------------------
	store.set_slot(5, "pumpkin", 3)
	# Closing the window shut the lid, and the animator refuses a second run
	# while one is travelling -- so let it land before using the chest again,
	# or the interact is quietly declined and no window ever opens.
	if player._prop_anim.is_moving(chest):
		await player._prop_anim.finished
	player._try_interact(Vector2.ZERO)
	if player._prop_anim.is_moving(chest):
		await player._prop_anim.finished
	for i in 10:
		await process_frame
	check(panel._store != null and panel._store.count_of("pumpkin") == 3,
			"reopening the same chest shows what was left in it")
	check(panel._store_slots[5].item == "pumpkin" and panel._store_slots[5].count == 3,
			"and the slot is drawn with it (%s x%d)"
			% [panel._store_slots[5].item, panel._store_slots[5].count])

	# Something on the cursor and something in each grid, for the frame.
	bag.set_slot(21, "tomato", 6)
	panel._player_slots[21].pressed.emit(21, MOUSE_BUTTON_LEFT)
	for i in 5:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/storage_in_use.png")

	print("\nFAILURES: %d of %d" % [_failures, _checks])
	quit()


func _first(props: TileMapLayer, verb: String) -> Vector2i:
	for cell in props.get_used_cells():
		var data := props.get_cell_tile_data(cell)
		if data != null and str(data.get_custom_data("interact")) == verb:
			return cell
	return Vector2i.ZERO


func _slot_of(inv: Inventory, item: String) -> int:
	for i in inv.size():
		if inv.item_at(i) == item:
			return i
	return 0


## Shift is read with Input.is_key_pressed at click time, so the test has to
## hold the real key rather than pass a flag. The Input singleton takes the
## event on the next frame, so this waits for it -- without that the click goes
## out while the key still reads as up.
func _hold_shift(down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = down
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
