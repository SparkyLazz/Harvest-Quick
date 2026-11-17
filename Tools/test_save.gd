extends SceneTree

## The save game: what PlayerState writes every morning and reads back when the
## game starts. Uses a save file of its own and never the player's:
##   godot --headless --path . --script Tools/test_save.gd
##
## HUD and Farm are reached through instances only -- a --script test cannot
## name classes that touch autoloads (TECH_NOTES, traps).

const PATH := "user://test_save.dat"
const FARM := "res://Scenes/Dev.tscn"

var _fails := 0
var state: Node


func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1


func _initialize() -> void:
	await process_frame
	state = root.get_node("PlayerState")
	check(not state.autosave, "run with --script, the game neither loads nor autosaves the real save")
	state.save_path = PATH
	state.delete_save()

	# --- a day's worth of changes, on the farm --------------------------------
	await _open(FARM)
	var hud = current_scene.get_node("HUD")
	var farm = current_scene.get_node("Farm")
	state.day = 12
	state.coins = 345
	hud.inventory.set_slot(10, "tomato", 7)
	state.storage_for("PlayerHouse:9,7").set_slot(3, "wood", 40)
	state.storage_for(state.SHIPPING_KEY).set_slot(0, "carrot", 2)
	var plot := Vector2i(4, 10)
	farm._on_tilled(plot)
	farm.plant(plot, "carrot")
	farm.water(plot)
	check(state.save_game(), "the game saves")
	check(FileAccess.file_exists(PATH) and not FileAccess.file_exists(PATH + ".tmp"),
			"to its file, with no half-written .tmp left behind")
	check(state.save_game(), "and saves again over its own file")

	# --- forget it all, then read it back -----------------------------------------
	_close()
	state.reset()
	check(state.coins == state.START_COINS and state.day == 1 and state.inventory == null,
			"a reset forgets everything in memory")
	check(state.load_game(), "the save loads")
	check(state.day == 12 and state.coins == 345, "day and coins come back")
	check(state.inventory != null and state.inventory.item_at(10) == "tomato"
			and state.inventory.count_at(10) == 7, "the bag comes back")
	check(state.storage_for("PlayerHouse:9,7").count_of("wood") == 40, "a chest's contents come back")
	var bin: Inventory = state.storage_for(state.SHIPPING_KEY)
	check(bin.count_of("carrot") == 2 and bin.add(ItemDB.HOE, 1) == 1,
			"the shipping bin comes back, still refusing tools")
	await _open(FARM)
	farm = current_scene.get_node("Farm")
	check(farm.has_crop(plot) and farm.is_wet(plot) and farm.is_tilled(plot),
			"the farm comes back planted and watered")

	# --- a save taken with the farm on screen has its latest -----------------------
	var fresh := Vector2i(5, 10)
	farm._on_tilled(fresh)
	farm.plant(fresh, "turnip")
	state.save_game()
	_close()
	state.reset()
	state.load_game()
	await _open(FARM)
	check(current_scene.get_node("Farm").has_crop(fresh),
			"including what was planted that very minute")

	# --- every morning saves itself --------------------------------------------------
	var night: int = state.day
	state.autosave = true
	state.sleep()
	state.autosave = false
	_close()
	state.reset()
	check(state.load_game() and state.day == night + 1, "sleeping saves the morning (day %d)" % state.day)

	# --- starting the game on a save: black at once, then up beside the bed --------
	# _ready does this when the game is launched normally; under --script it is
	# switched off, so the same two steps are taken here by hand.
	await _open(FARM)
	var fade := root.get_node("SceneTransition")
	check(state.load_game(), "the morning's save loads at start")
	state._wake_in_bed()
	check(fade._shade.visible and is_equal_approx(fade._shade.modulate.a, 1.0),
			"the screen is black before the first frame of the farm can show")
	await fade.arrived
	var house := current_scene
	var bed := house.find_child("Bed", true, false) as Node2D if house else null
	var player := house.find_child("Player", true, false) as Node2D if house else null
	check(house != null and house.scene_file_path == state.HOUSE_SCENE and bed != null
			and player != null and player.global_position == bed.global_position,
			"and the player wakes in the house, beside the bed")
	check(is_equal_approx(fade._shade.modulate.a, 0.0), "with the screen faded back in")

	# --- a save that is not one is refused, and nothing changes ------------------------
	var keep: int = state.coins
	_write_raw(func(f: FileAccess) -> void: f.store_string("not a save at all"))
	check(not state.load_game() and state.coins == keep, "a damaged file is refused")
	_write_raw(func(f: FileAccess) -> void: f.store_var({"version": 999, "day": 3}))
	check(not state.load_game() and state.coins == keep, "so is a save from another version")

	# --- a new game -------------------------------------------------------------------
	state.save_game()
	await _open(FARM)
	state.new_game()
	await root.get_node("SceneTransition").arrived
	check(not FileAccess.file_exists(PATH), "a new game forgets the save")
	check(state.day == 1 and state.coins == state.START_COINS, "and starts on day one with %d coins"
			% state.START_COINS)
	check(current_scene.scene_file_path == FARM, "on the farm")
	await process_frame
	farm = current_scene.get_node("Farm")
	check(not farm.has_crop(plot) and not farm.has_crop(fresh),
			"with none of the old farm carried into it")

	state.delete_save()
	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


func _open(path: String) -> void:
	change_scene_to_file(path)
	for i in 6:
		await process_frame


## Takes the scene away, the way a scene change does, so it writes its records.
func _close() -> void:
	var scene := current_scene
	if scene != null:
		root.remove_child(scene)
		scene.free()


func _write_raw(write: Callable) -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	write.call(file)
	file.close()
