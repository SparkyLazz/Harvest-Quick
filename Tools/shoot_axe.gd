extends SceneTree

## Runs the farm for real and saves frames of the axe at work, so the trees,
## decorations and the chop pose can be looked at rather than assumed.
##   godot --path . --script Tools/shoot_axe.gd -- <out dir>

var _out := "res://Tools"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	await process_frame
	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var grass := scene.get_node("Grass Layer") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	var hud := scene.get_node("HUD")
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	hud.selected_slot = 2

	# Wide view of the island: every tree, flower and the fence.
	cam.zoom = Vector2(2, 2)
	player.global_position = Vector2(208, 136)
	await _settle(cam)
	_save("axe_island")

	# Close up beside the sunflower and the fence.
	cam.zoom = Vector2(4, 4)
	player.global_position = Vector2(248, 56)
	await _settle(cam)
	_save("axe_sunflower")
	player.global_position = Vector2(168, 216)
	player._facing = "down"
	await _settle(cam)
	_save("axe_fence")

	# Mid-chop below a tree, on the impact frame.
	# Untyped: naming ChoppableTree would compile it before the autoloads exist.
	var tree = player.tree_at(Vector2i(3, 3))
	var cell: Vector2i = tree.cell_on(grass)
	player._facing = "up"
	player.global_position = player.cell_center(cell + Vector2i.DOWN) + Vector2(0, 4)
	await _settle(cam)
	player._start_action("axe", Vector2.ZERO)
	while player.sprite.frame < player.axe_impact_frame:
		await process_frame
	_save("axe_chop")
	# Fell it and catch the fall halfway, then the stump.
	player._land_axe_hit()
	player._land_axe_hit()
	while player._action != "" or tree.get_child(1).frame < 6:
		await process_frame
	_save("axe_falling")
	while not tree.is_stump():
		await process_frame
	for i in 10:
		await process_frame
	_save("axe_stump")
	quit()


func _settle(cam: Camera2D) -> void:
	cam.reset_smoothing()
	for i in 30:
		await process_frame


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("saved ", name)
