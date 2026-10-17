extends SceneTree

## Opens a wardrobe and a chest for real and saves the frames, so the window's
## shape and placement can be measured off the screen rather than worked out on
## paper. Run this one windowed -- `--headless` draws with the dummy renderer
## and hands back a null frame.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	var hud: Node = scene.find_child("HUD", true, false)

	var wardrobe := _first(props, "wardrobe")
	var chest := _first(props, "chest")
	print("wardrobe cell ", wardrobe, "  chest cell ", chest)

	await _use(player, props, wardrobe)
	_check(hud.is_storage_open(), "the wardrobe opens the window")
	root.get_texture().get_image().save_png("res://Tools/storage_wardrobe.png")

	hud.close_storage()
	_check(not hud.is_storage_open(), "the window closes")
	_check(not hud.is_inventory_open(), "and the player is free to walk again")

	await _use(player, props, chest)
	_check(hud.is_storage_open(), "the chest opens the window too")
	root.get_texture().get_image().save_png("res://Tools/storage_chest.png")

	# The bug this guards: Esc took the window away and left the lid standing
	# open, with nothing on screen to shut it again.
	_check(player._prop_anim.is_open(props, chest), "the lid is open while the window is")
	_press("ui_cancel")
	await process_frame
	await _settle(player, chest)
	_check(not hud.is_storage_open(), "escape closes the window")
	_check(not player._prop_anim.is_open(props, chest), "and the lid shuts with it")

	# Using the chest again shuts the lid, and the window goes with it.
	await _use(player, props, chest)
	_check(hud.is_storage_open(), "the chest opens again")
	player._try_interact(Vector2.ZERO)
	await _settle(player, chest)
	_check(not hud.is_storage_open(), "using it again leaves no window behind")
	_check(not player._prop_anim.is_open(props, chest), "and no open lid either")

	# A wardrobe has nothing to animate, so closing its window must not try.
	await _use(player, props, wardrobe)
	hud.close_storage()
	for i in 20:
		await process_frame
	_check(not hud.is_storage_open(), "the wardrobe window closes cleanly")

	await _use(player, props, wardrobe)
	await _report_halves(hud)
	hud.close_storage()
	for i in 10:
		await process_frame

	# The X, clicked where it actually sits on screen rather than by firing its
	# signal -- a button that is wired up but unreachable would pass that.
	await _use(player, props, chest)
	var x_button: TextureButton = hud._storage._close_button
	_check(x_button != null and x_button.visible, "the window carries a close button")
	_check(hud._storage._window.get_global_rect().has_point(
			x_button.get_global_transform() * (x_button.size * 0.5)),
			"and it sits inside the window")
	await _click(x_button)
	_check(not hud.is_storage_open(), "clicking the X closes the window")
	if player._prop_anim.is_moving(chest):
		await player._prop_anim.finished
	_check(not player._prop_anim.is_open(props, chest), "and the lid shuts with it too")
	print("done")
	quit()


## Clicks a control where it is drawn. The window is scaled, so the point has
## to come from the control's own transform -- a global rect carries a scaled
## position with an unscaled size, and its centre lands somewhere else entirely.
func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_transform() * (control.size * 0.5)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await process_frame
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		Input.parse_input_event(click)
		await process_frame
	for i in 5:
		await process_frame


## Sends a real action press, so the path under test is the one the keyboard
## takes rather than a method call that skips the input handling.
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _first(props: TileMapLayer, verb: String) -> Vector2i:
	for cell in props.get_used_cells():
		var data := props.get_cell_tile_data(cell)
		if data != null and str(data.get_custom_data("interact")) == verb:
			return cell
	return Vector2i.ZERO


func _use(player: Node2D, props: TileMapLayer, cell: Vector2i) -> void:
	player.global_position = props.to_global(props.map_to_local(cell + Vector2i.DOWN))
	player._facing = "up"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 10:
		await process_frame
	player._try_interact(Vector2.ZERO)
	await _settle(player, cell)


## Waits for a lid to finish travelling rather than for a number of frames.
## A frame budget looked generous and was not -- the run was only part way
## through at thirty frames, which reads as the lid never having opened.
func _settle(player: Node2D, cell: Vector2i) -> void:
	if player._prop_anim.is_moving(cell):
		await player._prop_anim.finished
	for i in 5:
		await process_frame


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])


## Reports the two halves' rects. The point of the split is that both reach the
## bottom of the window and share the width evenly, which is a measurement, not
## something to be judged from a screenshot.
func _report_halves(hud: Node) -> void:
	var panel = hud._storage
	var window: Control = panel._window
	var left: Control = panel._left
	var right: Control = panel._right
	# Measured in the window's own space. The halves sit inside a box inside the
	# window, so their local positions say nothing about the window's bottom
	# edge -- but the window is drawn at a whole-number zoom, and a Control's
	# global rect carries a scaled position with an unscaled size, so comparing
	# global numbers reports the gap multiplied by the zoom.
	var inv := window.get_global_transform().affine_inverse()
	var bottom_gap_l := window.size.y - (inv * left.get_global_rect().end).y
	var bottom_gap_r := window.size.y - (inv * right.get_global_rect().end).y
	print("   window %s  halves %s and %s  gap below %s/%s" % [window.size,
			left.size, right.size, bottom_gap_l, bottom_gap_r])
	_check(left.size.x == right.size.x, "the halves share the width (%s vs %s)"
			% [left.size.x, right.size.x])
	_check(left.size.y == right.size.y, "and the same height")
	# Down to the plate's own padding and no further -- reaching the bottom
	# means reaching the inside of the border, not overrunning it.
	# `panel.PAD`, not `StoragePanel.PAD`: naming the class here would make this
	# script depend on StoragePanel -> HUD -> PlayerState at parse time, and a
	# SceneTree script is compiled before the autoloads exist, so it would fail
	# to compile with a confusing "Identifier not found: PlayerState".
	_check(bottom_gap_l == bottom_gap_r and is_equal_approx(bottom_gap_l, panel.PAD),
			"both reach the bottom of the window (%s px to the border)" % bottom_gap_l)
	# The halves must fit the plate, not merely be equal to each other. A grid
	# one column too wide pushes its half past the border instead of scrolling.
	var left_edge := (inv * left.get_global_rect().position).x
	var right_edge := window.size.x - (inv * right.get_global_rect().end).x
	_check(is_equal_approx(left_edge, panel.PAD) and is_equal_approx(right_edge, panel.PAD),
			"the halves sit inside the plate (%s / %s px to the border)"
			% [left_edge, right_edge])
	_check(panel.columns_per_half() >= 1,
			"a half holds %d slot columns" % panel.columns_per_half())
	await _scrolls(left, "the backpack")
	await _scrolls(right, "the chest")


## Does this half actually scroll? A scrollbar can be drawn and do nothing, so
## the test is that the content is taller than the view and that scrolling it
## moves the grid.
func _scrolls(half: Control, what: String) -> void:
	var scroll: ScrollContainer = half.find_children("*", "ScrollContainer", true, false)[0]
	var grid: GridContainer = half.find_children("*", "GridContainer", true, false)[0]
	var bar := scroll.get_v_scroll_bar()
	_check(grid.size.y > scroll.size.y,
			"%s holds more than it shows (%s of grid in %s of view)"
			% [what, grid.size.y, scroll.size.y])
	var before := grid.global_position.y
	scroll.scroll_vertical = int(bar.max_value)
	await process_frame
	await process_frame
	var moved := before - grid.global_position.y
	_check(moved > 0.0, "%s scrolls (%s px of travel)" % [what, moved])
	scroll.scroll_vertical = 0
