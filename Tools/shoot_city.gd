extends SceneTree

## Renders the town and a conversation in it.
##   godot --path . --script Tools/shoot_city.gd     (needs a window)

func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	state.autosave = false
	state.reset()
	state.minutes = 10 * 60

	if not ResourceLoader.exists("res://Scenes/City.tscn"):
		print("no res://Scenes/City.tscn yet -- nothing to shoot.")
		quit()
		return
	change_scene_to_file("res://Scenes/City.tscn")
	for i in 30:
		await process_frame
	var scene := current_scene
	var player: Node2D = scene.find_child("Player", true, false)
	var cam: Camera2D = player.find_child("Camera2D", true, false)

	# The middle of the square, looking at the town.
	player.global_position = Vector2(16 * 16 + 8, 9 * 16 + 8)
	player._facing = "up"
	if cam:
		cam.reset_smoothing()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_city.png")
	print("saved shot_city.png")

	# A word with the neighbour.
	var who = scene.get_node("TownsfolkNeighbour")
	player.global_position = who.global_position + Vector2(-20, 0)
	player._facing = "right"
	if cam:
		cam.reset_smoothing()
	for i in 20:
		await process_frame
	who.interact(player)
	# Waited in seconds, not frames: the typing runs on real time and a render
	# loop runs frames far faster than 60 a second, so a frame count lands
	# mid-word (TECH_NOTES §9).
	await create_timer(2.0).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_dialogue.png")
	print("saved shot_dialogue.png  (talking=%s)" % root.get_node("Dialogue").is_talking())
	quit()
