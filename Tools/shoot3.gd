extends SceneTree

## Draws, over a real frame, which cell the chest occupies and which cell its
## hitbox is -- the floor you stand on to use it.

class Marks extends Node2D:
	var layer: TileMapLayer
	var chest: Vector2i
	func _draw() -> void:
		var tile := Vector2(16, 16)
		var at := func(c: Vector2i) -> Vector2:
			return layer.map_to_local(c) - tile * 0.5
		# chest cell in red, the hitbox below it in green
		draw_rect(Rect2(at.call(chest), tile), Color(1, 0.2, 0.2, 0.35))
		draw_rect(Rect2(at.call(chest), tile), Color(1, 0.2, 0.2), false, 1.0)
		var front := chest + Vector2i(0, 1)
		draw_rect(Rect2(at.call(front), tile), Color(0.3, 1, 0.3, 0.35))
		draw_rect(Rect2(at.call(front), tile), Color(0.3, 1, 0.3), false, 1.0)

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: CharacterBody2D = scene.find_child("Player", true, false)
	var chest := Vector2i(8, 6)
	props.set_cell(chest, 23, Vector2i(1, 0), 0)

	var marks := Marks.new()
	marks.layer = props
	marks.chest = chest
	marks.z_index = 100
	scene.add_child(marks)

	# Stand the player on the hitbox cell and confirm it reaches.
	player.global_position = props.to_global(props.map_to_local(chest + Vector2i(0, 1)))
	player._facing = "down"
	var cam: Camera2D = player.find_child("Camera2D", true, false)
	if cam:
		cam.reset_smoothing()
	for i in 30:
		await process_frame
	print("standing on the green cell, facing down -> reaches '",
			player.interaction_ahead(), "'")
	root.get_texture().get_image().save_png("res://Tools/hitbox.png")
	print("saved")
	quit()
