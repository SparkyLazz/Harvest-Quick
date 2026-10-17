extends SceneTree

## The cursor is the interaction indicator: it must point at things that can be
## used and stay a plain paw everywhere else.
##   godot --headless --path . --script Tools/test_cursor.gd

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
	var cursor := root.get_node_or_null("/root/MouseCursor")
	check(cursor != null, "MouseCursor autoload is up")
	if cursor == null:
		done(); return

	check(cursor.shape() == cursor.Shape.IDLE, "it starts as the arrow")
	check(cursor.ART[cursor.Shape.IDLE].resource_path.ends_with("Cursor_Arrow.png"),
			"idle is the arrow icon")
	check(cursor.ART[cursor.Shape.POINT].resource_path.ends_with("Cursor_Paw.png"),
			"something usable gets the catpaw")

	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 8:
		await process_frame
	var props := current_scene.get_node("Props") as TileMapLayer

	# With no scene mouse to drive, the hover test is checked at the cell level
	# by asking what the layer holds where the pointer would be.
	var dresser := Vector2i(11, 4)
	var bare := Vector2i(10, 5)
	check(str(props.get_cell_tile_data(dresser).get_custom_data("interact")) != "",
			"a dresser cell reports a verb")
	check(props.get_cell_tile_data(bare) == null
			or str(props.get_cell_tile_data(bare).get_custom_data("interact")) == "",
			"a bare floor cell reports none")

	# Carrying wins over whatever is underneath.
	cursor.set_carrying(true)
	await process_frame
	check(cursor.shape() == cursor.Shape.GRAB, "carrying shows the closed paw")
	cursor.set_carrying(false)
	await process_frame
	check(cursor.shape() != cursor.Shape.GRAB, "putting it down releases the paw")

	# All three paws must exist and be blown up, or the cursor is invisible.
	check(cursor.ART.size() == 3, "three paws are loaded")
	var scaled: Texture2D = cursor._scaled[cursor.Shape.POINT]
	check(scaled != null and scaled.get_width() == 16 * cursor.ZOOM,
			"they are scaled to %dpx" % (16 * cursor.ZOOM))

	# Nothing to hover in a scene with no Props layer: must not crash.
	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 6:
		await process_frame
	check(not cursor.hovering_usable(), "outdoors, with no Props layer, it stays idle")

	done()
