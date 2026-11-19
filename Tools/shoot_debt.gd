extends SceneTree

## Renders the three faces of step 3, so they can be looked at rather than
## reasoned about: the collector standing at the gate, his bill, and the bad
## ending.
##   godot --path . --script Tools/shoot_debt.gd     (needs a window)

func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	var debt := root.get_node("Debt")
	var ending := root.get_node("EndingScreen")
	state.autosave = false
	state.reset()

	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 30:
		await process_frame
	var scene := current_scene
	var collector = scene.get_node("Collector")
	var hud = scene.get_node("HUD")
	var player: Node2D = scene.find_child("Player", true, false)

	# Sunday, so he is there.
	while not debt.is_collection_day(state.day):
		state.sleep()
	state.minutes = 10 * 60
	state.time_changed.emit(state.minutes)

	# Stand the player beside him, facing him, so both are in the frame -- above
	# him the two sprites overlap and he is hidden behind the player's head.
	player.global_position = collector.global_position + Vector2(-22, 0)
	player._facing = "right"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_collector.png")
	print("saved shot_collector.png")

	hud.open_debt()
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_debt_bill.png")
	print("saved shot_debt_bill.png")
	hud.close_debt()

	# Three missed weeks, the long way round, so the ending arrives the way it
	# would in play rather than by being switched on.
	for i in 30:
		if debt.lost_farm:
			break
		state.sleep()
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_debt_ending.png")
	print("saved shot_debt_ending.png  (open=%s)" % ending.is_open())
	paused = false
	quit()
