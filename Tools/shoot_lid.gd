extends SceneTree

## The chest stands directly behind the player who opened it, so a frame taken
## where they stand shows the player, not the lid. These two step aside first:
## one with the window up, one after escape has taken it away.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	var hud: Node = scene.find_child("HUD", true, false)
	var chest := Vector2i.ZERO
	for cell in props.get_used_cells():
		var data := props.get_cell_tile_data(cell)
		if data != null and str(data.get_custom_data("interact")) == "chest":
			chest = cell
			break

	player.global_position = props.to_global(props.map_to_local(chest + Vector2i.DOWN))
	player._facing = "up"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 10:
		await process_frame
	player._try_interact(Vector2.ZERO)
	await player._prop_anim.finished
	await _aside(player, props, chest, cam)
	root.get_texture().get_image().save_png("res://Tools/lid_window_up.png")
	print("open: ", player._prop_anim.is_open(props, chest))

	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	if player._prop_anim.is_moving(chest):
		await player._prop_anim.finished
	await _aside(player, props, chest, cam)
	root.get_texture().get_image().save_png("res://Tools/lid_after_esc.png")
	print("open after esc: ", player._prop_anim.is_open(props, chest))
	quit()


func _aside(player: Node2D, props: TileMapLayer, chest: Vector2i, cam: Camera2D) -> void:
	player.global_position = props.to_global(props.map_to_local(chest + Vector2i(0, 3)))
	if cam:
		cam.reset_smoothing()
	for i in 15:
		await process_frame
