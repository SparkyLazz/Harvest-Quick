extends SceneTree

## Renders the clock's date plate many ways -- font, layout, alignment, wording
## -- on the real clock in the real scene, one frame each, so a design can be
## picked from pictures rather than descriptions. Every option shows Monday the
## 15th of Summer, the widest date there is. Tools/plate_options.py lays the
## frames out on one labelled sheet. Run windowed:
##   godot --path . --script Tools/shoot_plate_options.gd

const DAY := 43
const FACE := Rect2(24, 58, 47, 18)
const DARK := Color("5a3d3d")
const SOFT := Color("90625d")
## Rows of ink per face, and the size each is drawn at.
const FONTS := {
	"small": {"size": 8, "ink": 5},
	"body": {"size": 10, "ink": 7},
	"title": {"size": 10, "ink": 7},
}
## Each option is lines top to bottom; each line is spans left to right, as
## [font, text, colour]. One span is centred (or set `align`), two are pinned to
## the edges, three go left, middle, right.
const OPTIONS: Array[Dictionary] = [
	{"name": "Small, one line, split", "lines": [[["small", "MO 15", DARK], ["small", "SUM", SOFT]]]},
	{"name": "Small, one line, centred", "lines": [[["small", "MON 15", DARK]]]},
	{"name": "Small, two lines, centred", "lines": [[["small", "MON 15", DARK]], [["small", "SUMMER", SOFT]]]},
	{"name": "Small, two lines, left", "align": "left", "lines": [[["small", "MON 15", DARK]], [["small", "SUMMER", SOFT]]]},
	{"name": "Small, season first", "lines": [[["small", "SUMMER", SOFT]], [["small", "MON 15", DARK]]]},
	{"name": "Body, one line", "lines": [[["body", "MON 15", DARK]]]},
	{"name": "Body, date over season", "lines": [[["body", "MON 15", DARK]], [["small", "SUMMER", SOFT]]]},
	{"name": "Title, one line", "lines": [[["title", "MON 15", DARK]]]},
	{"name": "Title, date over season", "lines": [[["title", "MON 15", DARK]], [["small", "SUMMER", SOFT]]]},
	{"name": "Big number, words under", "lines": [[["title", "15", DARK]], [["small", "MON", SOFT], ["small", "SUM", SOFT]]]},
	{"name": "Season and number", "lines": [[["body", "SUM 15", DARK]]]},
]
const GAP := 3

var _shown: Array[Node] = []


func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/Dev.tscn")
	await _settle()
	var state := root.get_node("PlayerState")
	state.day = DAY
	state.minutes = 12 * 60
	var clock: Control = current_scene.find_child("Clock", true, false)
	clock.refresh(false)
	clock._date.visible = false
	clock._season.visible = false
	for i in OPTIONS.size():
		for node in _shown:
			node.queue_free()
		_shown.clear()
		_lay_out(clock, OPTIONS[i])
		await _settle()
		root.get_texture().get_image().save_png("res://Tools/_plate_option_%02d.png" % i)
	print("done ", OPTIONS.size())
	quit()


## Stacks the lines with GAP between them and centres the stack in the face.
func _lay_out(clock: Control, option: Dictionary) -> void:
	var lines: Array = option["lines"]
	var heights: Array[int] = []
	var total := 0
	for line: Array in lines:
		var tall := 0
		for span: Array in line:
			tall = maxi(tall, FONTS[span[0]]["ink"])
		heights.append(tall)
		total += tall
	total += GAP * (lines.size() - 1)
	var y := FACE.position.y + floorf((FACE.size.y - total) / 2.0)
	for i in lines.size():
		var line: Array = lines[i]
		for j in line.size():
			var span: Array = line[j]
			var font: Dictionary = FONTS[span[0]]
			var align := HORIZONTAL_ALIGNMENT_CENTER
			if line.size() == 1 and option.get("align", "") == "left":
				align = HORIZONTAL_ALIGNMENT_LEFT
			elif line.size() >= 2 and j == 0:
				align = HORIZONTAL_ALIGNMENT_LEFT
			elif line.size() >= 2 and j == line.size() - 1:
				align = HORIZONTAL_ALIGNMENT_RIGHT
			# Shorter faces sit on the same middle as the tallest in the line.
			var drop := floorf((heights[i] - font["ink"]) / 2.0)
			_add(clock, span[0], font["size"], span[1], span[2], align, y + drop)
		y += heights[i] + GAP


func _add(clock: Control, face: String, size: int, text: String, color: Color,
		align: HorizontalAlignment, top: float) -> void:
	# Added before its text and size are set: set the other way round, a
	# centred label lands half its own width too far right.
	var label := Label.new()
	var font: Font = UIFont.small() if face == "small" else (UIFont.body() if face == "body" else UIFont.title())
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	clock.add_child(label)
	label.text = text
	var inset := 3
	# Text ends in its last letter's spacing, so set right it stops short and
	# centred it sits left. One pixel back, either way, except for centred small
	# text, whose one-pixel spacing only splits into halves.
	var shift := 0
	if align == HORIZONTAL_ALIGNMENT_RIGHT or (align == HORIZONTAL_ALIGNMENT_CENTER and face != "small"):
		shift = 1
	label.position = Vector2(FACE.position.x + inset + shift, top)
	label.size = Vector2(FACE.size.x - inset * 2, 12)
	_shown.append(label)


func _settle() -> void:
	for i in 12:
		await process_frame
