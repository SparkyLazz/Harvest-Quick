extends SceneTree

## Saves a frame of the farm with the clock plate up, once in the morning and
## once past midnight when the hour turns red. Run windowed; headless draws
## with the dummy renderer and hands back nothing.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/Dev.tscn")
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/clock_morning.png")
	var state := root.get_node("PlayerState")
	state.day = 40
	state.minutes = 24 * 60 + 30
	state.time_changed.emit(state.minutes)
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/clock_late.png")
	print("done")
	quit()


func _settle() -> void:
	for i in 20:
		await process_frame
