extends SceneTree

## Renders the farm under each sky, so the rain can be looked at rather than
## reasoned about: clear, rain, storm, and a storm caught mid-flash.
##   godot --path . --script Tools/shoot_rain.gd     (needs a window)
##
## Headless will not do: the drops are GPUParticles2D, and the dummy renderer
## has no GPU to run them on -- the frames come out empty.

const SHOTS: Array[Dictionary] = [
	{"kind": 0, "file": "shot_sky_clear.png"},
	{"kind": 1, "file": "shot_sky_rain.png"},
	{"kind": 2, "file": "shot_sky_storm.png"},
]


func _initialize() -> void:
	await process_frame
	var weather := root.get_node("Weather")
	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 30:
		await process_frame
	var scene := current_scene
	var rain = scene.get_node("Rain")
	var player: Node2D = scene.find_child("Player", true, false)
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()

	# Mid-afternoon, so the clock's window is on its daylight picture and the
	# three skies are told apart by it as well as by the rain.
	var state := root.get_node("PlayerState")
	state.minutes = 14 * 60
	# Moving the clock by hand skips the signal the HUD listens to, which would
	# leave the first frame still showing the dawn it booted on.
	state.time_changed.emit(state.minutes)

	for shot in SHOTS:
		weather.forced = shot["kind"]
		rain.set_kind(shot["kind"], false)
		# Long enough for the sheets to fill the window from their preprocess,
		# and for the clock's set-and-rise to finish: shot too early, the window
		# is caught mid-swap with the old picture still sinking out of it.
		for i in 120:
			await process_frame
		root.get_texture().get_image().save_png("res://Tools/%s" % shot["file"])
		print("saved ", shot["file"])

	# And a lightning strike, caught at its brightest.
	rain._strike()
	for i in 2:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/shot_sky_flash.png")
	print("saved shot_sky_flash.png")
	quit()
