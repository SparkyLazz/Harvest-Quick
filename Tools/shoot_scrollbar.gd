extends SceneTree

## Draws the scrollbar's pieces at heights they will really be stretched to,
## at 1:1, so the slicing can be read off the pixels. A nine-slice that is a
## row short does not fail loudly -- it tiles one row of the rounded cap down
## the middle of the bar, which is the sort of thing that is only ever noticed
## once it ships.

const HEIGHTS := [21, 40, 90, 160]


func _initialize() -> void:
	await process_frame
	root.add_child(Strip.new())
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/scrollbar_stretch.png")
	print("done")
	quit()


class Strip extends Control:
	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		draw_rect(get_viewport_rect(), Color("4c4c4c"))
		# The margins as they were -- one number for both ends -- beside the
		# measured ones, so the difference is visible rather than argued about.
		var parts := [
			["grabber was", UISkin.scroll_part(Rect2(11, 0, 11, 21), 4, 5, 5)],
			["grabber now", UISkin.scroll_part(Rect2(11, 0, 11, 21), 4, 4, 6)],
			["track was", UISkin.scroll_part(Rect2(33, 0, 11, 40), 5, 3, 3)],
			["track now", UISkin.scroll_part(Rect2(33, 0, 11, 40), 5, 4, 2)],
		]
		var x := 20
		for entry in parts:
			for h: int in HEIGHTS:
				draw_style_box(entry[1], Rect2(x, 20, 11, h))
				x += 30
			x += 20
