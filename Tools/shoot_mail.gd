extends SceneTree

## Renders the post: the mailbox waving with something in it, and the window
## open on Mom's first letter.
##   godot --path . --script Tools/shoot_mail.gd     (needs a window)

func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	state.autosave = false
	state.reset()

	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 30:
		await process_frame
	var scene := current_scene
	var mailbox = scene.get_node("Mailbox")
	var hud = scene.get_node("HUD")
	var player: Node2D = scene.find_child("Player", true, false)

	# Far enough into the year for Mom to have written a few times -- paying the
	# collector on the way, or three missed Sundays end the game before the
	# post is worth looking at.
	var debt := root.get_node("Debt")
	while state.day < 29:
		if debt.is_collection_day(state.day):
			state.earn(debt.minimum())
			debt.pay(debt.minimum())
		state.sleep()
	state.minutes = 10 * 60
	state.time_changed.emit(state.minutes)

	player.global_position = mailbox.global_position + Vector2(0, 18)
	player._facing = "up"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 40:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_mailbox.png")
	print("saved shot_mailbox.png")

	hud.open_mail()
	for i in 20:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_mail_panel.png")
	print("saved shot_mail_panel.png  (letters=%d)" % root.get_node("Mail").letters.size())

	# One of Mom's, so the red line that says what she cost is in a frame too.
	hud._mail.show_letter("mom-w2")
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_mail_mom.png")
	print("saved shot_mail_mom.png")
	quit()
