extends SceneTree

## Draws the storage panel stylebox at sizes it was never authored at -- wider
## and narrower than the 106x122 art -- and saves the frame, so the nine-slice
## can be measured instead of assumed.

const BOX := "res://Assets/UI/Panel_Storage.tres"


func _initialize() -> void:
	await process_frame
	var style: StyleBoxTexture = load(BOX)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	for spec in [[Vector2(4, 4), Vector2(220, 90)], [Vector2(4, 104), Vector2(64, 150)]]:
		var panel := Panel.new()
		panel.add_theme_stylebox_override("panel", style)
		panel.position = spec[0]
		panel.size = spec[1]
		holder.add_child(panel)
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/panel_stretch.png")
	print("saved panel_stretch.png")
	quit()
