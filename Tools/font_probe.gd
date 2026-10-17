extends SceneTree

## Is the body font actually illegible, or is the specimen sheet lying?
## Draws it three ways -- straight load, through UIFont, and as a Label -- so
## the difference is in the picture rather than in a theory.

func _initialize() -> void:
	await process_frame
	root.add_child(Probe.new())
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/font_probe.png")
	print("done")
	quit()


class Probe extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var label := Label.new()
		label.add_theme_font_override("font", UIFont.body())
		label.add_theme_font_size_override("font_size", UIFont.SIZE)
		label.add_theme_color_override("font_color", Color("5a3d3d"))
		label.text = "LABEL: PACK 6/45"
		label.position = Vector2(20, 90)
		add_child(label)

	func _draw() -> void:
		draw_rect(get_viewport_rect(), Color("dcb98a"))
		var raw: FontFile = load("res://Assets/Fonts/pixelFont-3-7x5-sproutLands.ttf")
		draw_string(raw, Vector2(20, 30), "RAW LOAD: PACK 6/45",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("5a3d3d"))
		draw_string(UIFont.body(), Vector2(20, 60), "UIFONT: PACK 6/45",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("5a3d3d"))
