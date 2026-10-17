extends SceneTree

## Draws every pack font at every plausible size, on the panel colour they are
## read against, so the size question can be answered by looking at glyphs
## rather than by arguing about numbers.
##
## Run windowed -- headless draws with the dummy renderer and saves nothing.
## Nothing here touches the content scale: scaling the capture would resample
## every glyph and make all the sizes look equally soft, which is the one thing
## this sheet must not do.

const FONTS := [
	["7x5 body", "res://Assets/Fonts/pixelFont-3-7x5-sproutLands.ttf"],
	["7x7 title", "res://Assets/Fonts/pixelFont-4-7x7-sproutLands.ttf"],
	["8x14 large", "res://Assets/Fonts/pixelFont-7-8x14-sproutLands.ttf"],
]
const SIZES := [5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 21]
const SAMPLE := "PACK 6/45"
const COL := 380
const ROW := 56
const SAMPLE_DX := 108
const PLATE := Color("dcb98a")
const INK := Color("5a3d3d")
const MUTED := Color("90625d")


func _initialize() -> void:
	await process_frame
	root.add_child(Sheet.new())
	for i in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/font_sheet.png")
	for i in FONTS.size():
		for j in SIZES.size():
			print("CELL %s|%d|%d|%d" % [FONTS[i][0], SIZES[j],
					10 + i * COL + SAMPLE_DX, 16 + j * ROW])
	print("done")
	quit()


class Sheet extends Control:
	var _label: FontFile
	var _ready_fonts: Array[FontFile] = []

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Every font is prepared here, never inside _draw. Setting a property on
		# a FontFile throws away its glyph cache, and doing that mid-frame draws
		# the rest of the frame from a cache that is still being rebuilt -- the
		# glyphs come out as solid blocks and the font looks broken when it is
		# not. Two of three fonts in this sheet were libelled that way once.
		for entry in FONTS:
			_ready_fonts.append(_font(entry[1]))
		_label = _ready_fonts[1]

	## Pixel fonts have to be told not to smooth themselves, or every size looks
	## equally soft and the comparison says nothing.
	func _font(path: String) -> FontFile:
		var f: FontFile = load(path)
		f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		return f

	func _draw() -> void:
		# The viewport's rect, not this Control's: a full-rect preset has not
		# resolved to a size yet on the first draw, and an empty plate reads as
		# a failed render.
		draw_rect(get_viewport_rect(), PLATE)
		for i in FONTS.size():
			var font := _ready_fonts[i]
			var x := 10 + i * COL
			draw_string(_label, Vector2(x, 10), FONTS[i][0].to_upper(),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
			for j in SIZES.size():
				var y := 16 + j * ROW
				draw_string(_label, Vector2(x, y + 20), "@ %d" % SIZES[j],
						HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MUTED)
				draw_string(font, Vector2(x + SAMPLE_DX, y + 20), SAMPLE,
						HORIZONTAL_ALIGNMENT_LEFT, -1, SIZES[j], INK)
