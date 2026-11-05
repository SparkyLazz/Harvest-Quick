extends SceneTree

## Saves frames of the farm with the clock up at each part of the day, and a
## strip of frames through one set-and-rise, so the clock's placement and its
## animation can be looked at rather than assumed. Run windowed; headless draws
## with the dummy renderer and hands back nothing.
##   godot --path . --script Tools/shoot_clock.gd

const TIMES := {"dawn": 6 * 60 + 30, "day": 12 * 60 + 50, "dusk": 18 * 60,
		"night": 22 * 60, "late": 25 * 60}
const WINTER := 85

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/Dev.tscn")
	await _settle()
	var state := root.get_node("PlayerState")
	var clock: Node = current_scene.find_child("Clock", true, false)
	# Mo 15 Sum: the widest the plate's line ever gets, so the tightest fit.
	state.day = 43
	for name: String in TIMES:
		state.minutes = TIMES[name]
		clock.refresh(false)
		await _settle()
		root.get_texture().get_image().save_png("res://Tools/clock_%s.png" % name)

	# A winter night, for the cold end of the thermometer.
	state.day = WINTER
	state.minutes = TIMES["night"]
	clock.refresh(false)
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/clock_winter.png")
	state.day = 43

	# One swap, day into dusk, a frame every 0.1s.
	state.minutes = 16 * 60 + 59
	clock.refresh(false)
	await _settle()
	state.minutes = 17 * 60
	clock.refresh(true)
	for i in 12:
		root.get_texture().get_image().save_png("res://Tools/clock_swap_%02d.png" % i)
		await create_timer(0.1).timeout
	print("done")
	quit()


func _settle() -> void:
	for i in 20:
		await process_frame
