extends SceneTree

## Opens a wardrobe through the HUD and moves things in and out of it.
##   godot --headless --path . --script Tools/test_storage_ui.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func done() -> void:
	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 8:
		await process_frame

	var scene := current_scene
	var hud = scene.find_child("HUD", true, false)
	var player = scene.find_child("Player", true, false)
	var state = root.get_node_or_null("/root/PlayerState")
	check(hud != null and player != null and state != null, "house scene is up")
	if hud == null:
		done(); return

	check(hud.has_method("open_storage"), "HUD can open a wardrobe")
	check(not hud.is_storage_open(), "nothing is open to begin with")

	# Stand below a dresser, facing it, and use.
	var props := scene.get_node("Props") as TileMapLayer
	var dresser := Vector2i(11, 4)
	check(str(props.get_cell_tile_data(dresser).get_custom_data("interact")) == "wardrobe",
			"the cell below is a wardrobe")
	player.global_position = props.to_global(props.map_to_local(dresser + Vector2i.DOWN))
	player.start_facing = "up"
	player._facing = "up"
	check(player.facing_cell() == dresser, "the player is facing it")

	hud.inventory.set_slot(0, "wheat", 12)
	player._try_interact(Vector2.ZERO)
	await process_frame
	check(hud.is_storage_open(), "using it opens the wardrobe")
	check(hud.is_inventory_open(), "and that counts as a menu, so walking stops")

	var panel = hud.get_node_or_null("StoragePanel")
	check(panel != null and panel.bag == hud.inventory, "left side is the player bag")
	var key: String = state.storage_key(scene, dresser)
	check(panel != null and panel.store == state.storage_for(key),
			"right side is this wardrobe's own contents")

	# Shift-click the wheat across, then close.
	panel._carry.quick_move(panel.bag, 0, panel.store)
	check(panel.store.count_of("wheat") == 12, "shift click sent 12 wheat across")
	check(panel.bag.count_of("wheat") == 0, "and took them out of the bag")

	panel._carry.left_click(panel.store, 0)
	check(not panel._carry.is_empty(), "a stack can be picked up again")
	panel.close()
	check(not hud.is_storage_open(), "closing hides it")
	check(panel.bag.count_of("wheat") == 12, "closing returns the carried stack to the bag")

	# A different dresser is a different container.
	hud.open_storage("WARDROBE", state.storage_for(state.storage_key(scene, Vector2i(13, 4))))
	await process_frame
	check(panel.store.count_of("wheat") == 0, "the next wardrobe along is empty")
	panel.close()

	# --- the bed -------------------------------------------------------------
	var bed := Vector2i(4, 4)
	check(str(props.get_cell_tile_data(bed).get_custom_data("interact")) == "bed",
			"the bed cell reads as a bed")
	player.global_position = props.to_global(props.map_to_local(bed + Vector2i.DOWN))
	player._facing = "up"
	check(player.facing_cell() == bed, "the player is facing the bed")
	state.max_stamina = 100.0
	state.put_stamina(9.0)
	var day_before: int = state.day
	player._try_interact(Vector2.ZERO)
	for i in 120:
		await process_frame
		if state.day != day_before:
			break
	check(state.day == day_before + 1, "using the bed sleeps a night through")
	check(is_equal_approx(state.stamina, 100.0), "and wakes you up rested")
	for i in 90:
		await process_frame
		if not paused:
			break
	check(not paused, "the tree is running again after waking")

	# --- the prompt sign -----------------------------------------------------
	# Found by script path rather than by class: naming InteractPrompt here would
	# pull Player, and so the PlayerState autoload, into this script's compile,
	# which happens before autoloads exist.
	var prompt: Node2D = null
	for c in player.get_children():
		var sc: Variant = c.get_script()
		if sc != null and str(sc.resource_path).ends_with("InteractPrompt.gd"):
			prompt = c as Node2D
	check(prompt != null, "the player carries a prompt sign")
	if prompt == null:
		done(); return

	# facing a dresser: it offers exactly what the key would do
	player.global_position = props.to_global(props.map_to_local(dresser + Vector2i.DOWN))
	player._facing = "up"
	check(player.interaction_ahead() == "wardrobe", "facing a wardrobe offers 'wardrobe'")
	for i in 20:
		await process_frame
	check(prompt.modulate.a > 0.5, "the sign fades in")
	check(prompt.global_position.y < player.global_position.y,
			"and sits above the furniture, not under it")

	# turn away: nothing to offer, and the sign goes
	player._facing = "left"
	check(player.interaction_ahead() == "", "facing empty floor offers nothing")
	for i in 20:
		await process_frame
	check(prompt.modulate.a < 0.5, "the sign fades out again")

	# a menu covers the screen: the sign must not promise anything
	player._facing = "up"
	hud.open_storage("WARDROBE", state.storage_for(state.storage_key(scene, dresser)))
	await process_frame
	check(player.interaction_ahead() == "",
			"with the wardrobe open the sign goes quiet")
	hud._storage.close()

	# the bed offers its own verb, read off the tile
	player.global_position = props.to_global(props.map_to_local(bed + Vector2i.DOWN))
	player._facing = "up"
	check(player.interaction_ahead() == "bed", "facing the bed offers 'bed'")
	for i in 20:
		await process_frame
	check(prompt.modulate.a > 0.5, "and the sign shows for it too")

	done()
