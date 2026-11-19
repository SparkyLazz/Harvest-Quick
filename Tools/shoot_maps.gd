extends SceneTree

## Renders a whole map at once -- the camera pulled back far enough to hold all
## of it, the HUD and the player out of the way -- so a layout can be looked at
## as a layout rather than through the 4x play camera.
##   godot --path . --script Tools/shoot_maps.gd     (needs a window)

const MAPS: Array = [
	["res://Scenes/City.tscn", "shot_map_city.png"],
	["res://Scenes/Dev.tscn", "shot_map_farm.png"],
]

## Which layer's painted extent counts as "the map".
const GROUND := "Soil Layer"
## Tiles are 16px; this is the zoom the whole map is drawn at. 2 keeps the
## pixel art on whole pixels and still fits a 28x16 map in the window.
const ZOOM := 2.0


func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	state.autosave = false
	state.reset()
	state.minutes = 10 * 60

	for entry in MAPS:
		if not ResourceLoader.exists(entry[0]):
			print("skipped %s -- no such scene yet" % entry[0])
			continue
		change_scene_to_file(entry[0])
		for i in 30:
			await process_frame
		var scene := current_scene
		var ground := scene.get_node_or_null(GROUND) as TileMapLayer
		var used := ground.get_used_rect() if ground != null else Rect2i(0, 0, 28, 16)
		var middle := (Vector2(used.position) + Vector2(used.size) * 0.5) * 16.0

		# The player is in the shot otherwise, and the HUD covers a third of it.
		var player: Node2D = scene.find_child("Player", true, false)
		if player:
			player.visible = false
		var hud: CanvasLayer = scene.find_child("HUD", true, false)
		if hud:
			hud.visible = false

		var cam: Camera2D = player.find_child("Camera2D", true, false) if player else null
		if cam:
			# Off its limits and its follow, parked over the middle of the map.
			cam.position_smoothing_enabled = false
			cam.limit_left = -100000
			cam.limit_top = -100000
			cam.limit_right = 100000
			cam.limit_bottom = 100000
			cam.zoom = Vector2.ONE * ZOOM
			cam.global_position = middle
			cam.reset_smoothing()
			cam.force_update_scroll()
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png("res://Tools/%s" % entry[1])
		print("saved %s  (%s, used %s)" % [entry[1], entry[0].get_file(), str(used)])
	quit()
