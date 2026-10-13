extends SceneTree

## Walks the player into the house door and back out again, checking the fade,
## the scene swap and both spawn points.
##   godot --headless --path . --script Tools/test_door.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func settle(frames: int = 4) -> void:
	for i in frames:
		await physics_frame

func _initialize() -> void:
	await process_frame
	var trans := root.get_node_or_null("/root/SceneTransition")
	check(trans != null, "SceneTransition autoload is registered")
	if trans == null:
		quit(1)
		return

	change_scene_to_file("res://Scenes/Dev.tscn")
	await settle(6)
	check(current_scene != null and current_scene.scene_file_path.ends_with("Dev.tscn"),
			"Dev.tscn is the starting scene")

	var door := current_scene.get_node_or_null("Door")
	check(door != null, "Dev.tscn has a Door node")
	check(door != null and door.target_scene.ends_with("PlayerHouse.tscn"),
			"door points at the interior")

	var player: Node2D = current_scene.find_child("Player", true, false)
	check(player != null, "Dev.tscn has a Player")

	# Walk into the doorway.
	player.global_position = Vector2(168, 114)
	await settle(8)
	check(trans._busy, "touching the door starts a transition")

	# Let the fade out, swap and fade in all run.
	for i in 90:
		await process_frame
		if not trans._busy:
			break
	check(not trans._busy, "transition finishes")
	check(current_scene != null and current_scene.scene_file_path.ends_with("PlayerHouse.tscn"),
			"we are inside the house")

	var inside: Node2D = current_scene.find_child("Player", true, false)
	var mark: Node2D = current_scene.find_child("FrontDoor", true, false)
	check(inside != null and mark != null and inside.global_position == mark.global_position,
			"player stands on the FrontDoor marker")
	check(trans._shade.modulate.a == 0.0, "screen has faded back in")
	check(not paused, "tree is running again")

	# The exit door must not fire while we are standing on the spawn point.
	await settle(10)
	check(current_scene.scene_file_path.ends_with("PlayerHouse.tscn"),
			"spawning indoors does not bounce us straight back")

	# Now walk out.
	inside.global_position = Vector2(144, 175)
	await settle(8)
	for i in 90:
		await process_frame
		if not trans._busy:
			break
	check(current_scene != null and current_scene.scene_file_path.ends_with("Dev.tscn"),
			"walking into the exit returns us outside")
	var back: Node2D = current_scene.find_child("Player", true, false)
	var out_mark: Node2D = current_scene.find_child("HouseDoor", true, false)
	check(back != null and out_mark != null and back.global_position == out_mark.global_position,
			"player stands on the HouseDoor marker")
	await settle(10)
	check(current_scene.scene_file_path.ends_with("Dev.tscn"),
			"arriving outside does not bounce us back in")

	# --- carried state -------------------------------------------------------
	var state := root.get_node_or_null("/root/PlayerState")
	check(state != null, "PlayerState autoload is registered")

	var hud = current_scene.find_child("HUD", true, false)
	check(hud != null and hud.inventory == state.inventory,
			"the HUD borrows PlayerState's bag rather than making one")

	# Spend stamina and take an item, then go through the door and back.
	var p2: Node2D = current_scene.find_child("Player", true, false)
	p2.stamina = 42.0
	state.put_stamina(42.0)
	hud.inventory.set_slot(5, "wheat", 7)
	var bag_before: Inventory = hud.inventory

	p2.global_position = Vector2(168, 114)
	await settle(8)
	for i in 90:
		await process_frame
		if not trans._busy:
			break
	check(current_scene.scene_file_path.ends_with("PlayerHouse.tscn"), "indoors again")

	var hud2 = current_scene.find_child("HUD", true, false)
	var p3: Node2D = current_scene.find_child("Player", true, false)
	check(hud2 != null and hud2.inventory == bag_before, "same bag object indoors")
	check(hud2 != null and hud2.inventory.item_at(5) == "wheat"
			and hud2.inventory.count_at(5) == 7, "the 7 wheat survived the door")
	check(p3 != null and is_equal_approx(p3.stamina, 42.0),
			"stamina stayed at 42 instead of refilling")

	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)
