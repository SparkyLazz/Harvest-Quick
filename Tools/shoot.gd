extends SceneTree

## Runs the house for real and saves a couple of frames, so the chest's
## placement and its lid can be looked at rather than assumed.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	var cell := Vector2i(12, 3)

	# Stand below the chest, looking at it.
	player.global_position = props.to_global(props.map_to_local(cell + Vector2i.DOWN))
	player._facing = "up"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_closed.png")
	print("saved closed")

	if player._try_interact(Vector2.ZERO):
		await player._prop_anim.finished
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_open.png")
	print("saved open")
	quit()
