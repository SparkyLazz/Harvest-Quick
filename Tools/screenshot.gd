# Renders the game and saves PNGs of it.
#
#   godot --path . --script res://Tools/screenshot.gd
#
# Needs a real window, so no --headless. Output goes to user:// which on Windows
# is %APPDATA%/Godot/app_userdata/Harvest-Quick/shots/.
#
# The synthetic terrain test that used to live here is gone with the generated
# tileset it existed to check. Assets/Tilemap/Tilemap.tres is hand-authored now,
# so its peering bits were placed deliberately rather than derived by a script
# that could invert one without noticing. What is left worth checking is the
# thing this file still does: that the layer stack the code paints reads as a
# world — sea, island, grass, and soil where the grass has been taken off.
extends SceneTree

const SHOT_DIR := "user://shots/"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	# One frame before anything: in _init the tree's root window is not up yet,
	# so nothing may be added to it.
	await process_frame
	await _game()
	quit()

func _game() -> void:
	var scene: PackedScene = load("res://Scenes/main.tscn")
	var main := scene.instantiate()
	root.add_child(main)

	# The scene ships with the HUD hidden while the tileset is being worked on.
	# Turned on only for the capture, so the screenshot shows the readout without
	# the scene file being changed to suit the tool.
	var hud := main.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = true

	await _grab("game_start.png", 8)

	# The whole map in one frame. The close view cannot show whether the island
	# is an island: it fills the screen either way. Zoom 1 on a 1152 wide window
	# covers all 640px of a 40 tile map with room to spare, so this is the shot
	# that says whether the sea surrounds the land and where the shore falls.
	var camera := main.get_node_or_null("Player/Camera2D") as Camera2D
	if camera != null:
		var zoom := camera.zoom
		var limits := [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

		camera.position_smoothing_enabled = false
		camera.zoom = Vector2(0.62, 0.62)
		camera.limit_left = -2000
		camera.limit_top = -2000
		camera.limit_right = 2000
		camera.limit_bottom = 2000
		await _grab("world_overview.png", 6)

		# Put it all back. The first version restored only the position and left
		# the zoom wound out, so every shot after this one was taken through a
		# camera the game does not use — which is the one thing a screenshot tool
		# must never do.
		camera.zoom = zoom
		camera.limit_left = limits[0]
		camera.limit_top = limits[1]
		camera.limit_right = limits[2]
		camera.limit_bottom = limits[3]
		await process_frame

	# Hoe the faced tile, sow it, step on. Tilling and planting the same tile
	# back to back rather than tilling a patch and planting it afterwards,
	# because planting is refused on wild ground.
	#
	# Four tiles is the day's budget: three effort for the hoe and one for the
	# seed is four, against eighteen.
	for i in range(4):
		await _tap("till")
		await _tap("plant_1")
		await _walk("move_left" if i % 2 == 0 else "move_down")

	await _grab("game_tilled.png", 4)

	for i in range(3):
		await _tap("advance_day")

	await _grab("game_grown.png", 6)
	main.queue_free()
	await process_frame

# One press, held a few frames and released. IsActionJustPressed is true for
# exactly one frame after the press, so the waits are not padding.
func _tap(action: String) -> void:
	Input.action_press(action)
	for i in range(4):
		await process_frame
	Input.action_release(action)
	for i in range(4):
		await process_frame

# A step, rather than a press. Movement is read with IsActionPressed and gated on
# the step tween having finished, so a short tap is swallowed whole by
# StepDuration — which is why an earlier pass of this script tilled two tiles in
# a heap instead of six in a line.
func _walk(action: String) -> void:
	Input.action_press(action)
	for i in range(14):
		await process_frame
	Input.action_release(action)
	for i in range(10):
		await process_frame

func _grab(name: String, settle: int) -> void:
	for i in range(settle):
		await process_frame

	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(ProjectSettings.globalize_path(SHOT_DIR + name))
	print("shot ", name, "  ", image.get_width(), "x", image.get_height(), "  err ", err)
