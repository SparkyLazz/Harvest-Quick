@tool
extends EditorScript

## Rebuilds the world collision of the currently open scene: the wall shapes in
## the TileSet, then the cells of the invisible "Collision" layer.
##
## Run it with Script > Run (Ctrl+Shift+X) after repainting terrain or after
## changing WorldCollision.WALL_THICKNESS, then save the scene — the baked
## cells go stale otherwise. The TileSet is saved for you.

func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("RebuildCollision: no scene is open.")
		return

	var collision := root.get_node_or_null("Collision") as TileMapLayer
	if collision != null and collision.tile_set != null:
		if WorldCollision.rebuild_tile_shapes(collision.tile_set):
			var err := ResourceSaver.save(collision.tile_set)
			if err != OK:
				push_error("RebuildCollision: could not save the TileSet (%d)." % err)

	var count := WorldCollision.rebuild(root)
	if count >= 0:
		print("Collision rebuilt: %d cells, %.1fpx walls." % [count, WorldCollision.WALL_THICKNESS])
