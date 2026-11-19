extends SceneTree

## Renders both endings, so the words can be read on the plate rather than in
## the source.
##   godot --path . --script Tools/shoot_endings.gd     (needs a window)

func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	var debt := root.get_node("Debt")
	var law := root.get_node("Lawyer")
	var ending := root.get_node("EndingScreen")
	state.autosave = false

	# The good one first: the bad one leaves the tree paused.
	state.reset()
	state.earn(law.FEE)
	for piece in law.PIECES:
		law._have[piece["id"]] = true
	law.hire()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("res://Tools/shot_ending_won.png")
	print("saved shot_ending_won.png (open=%s)" % ending.is_open())
	paused = false
	ending.visible = false

	state.reset()
	# Three Sundays missed, the long way round.
	for i in 40:
		if debt.lost_farm:
			break
		state.sleep()
	await create_timer(0.4).timeout
	root.get_texture().get_image().save_png("res://Tools/shot_ending_lost.png")
	print("saved shot_ending_lost.png (open=%s)" % ending.is_open())
	paused = false
	quit()
