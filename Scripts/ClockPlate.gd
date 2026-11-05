class_name ClockPlate
extends Control

## The clock in the top-left corner, built from the UI pack's weather frame the
## way Stardew's is: a window showing the time of day as a picture, a dial with
## day above and night below and an arrow sweeping down it, a thermometer for
## how warm the season is, and a hanging plate for the date. There is no
## written time: the arrow on the dial is the time.
##
## The window plays a little set-and-rise whenever the part of the day changes:
## the old picture dips and sinks out of the bottom, the new one bounces up in
## its place, and the backdrop behind them cross-fades from one colour to the
## next. The arrow springs into each new step, and the picture breathes up and
## down a pixel while nothing else is going on.
##
## Every piece comes from Assets/UI/Clock.png (Tools/cut_clock.py lays it out)
## except the pictures, which are the pack's big weather icons. All positions
## below are in the atlas's source pixels; the whole clock is scaled up whole,
## like the bars, so the pixel art and the pixel font stay on their grid.

const ATLAS := preload("res://Assets/UI/Clock.png")
const ICONS := preload("res://Assets/UI/Weather/Weather_Icons_Big.png")

const FRAME_REGION := Rect2(0, 0, 98, 99)
const DIAL_REGION := Rect2(100, 0, 22, 34)
## An empty tube, drawn behind the fill so whatever it doesn't reach reads as
## glass. The frame's thermometer only has holes where liquid shows.
const TUBE_REGION := Rect2(124, 0, 8, 28)
## Five arrow cells across, steepest-up first, each with its tail on ARROW_TAIL.
const ARROW_ORIGIN := Vector2(100, 40)
const ARROW_CELL := 24
const ARROW_TAIL := Vector2(4, 12)
const ARROW_FRAMES := 5
## Nine thermometer fills across, hottest first, each standing on its bulb.
const FILL_ORIGIN := Vector2(0, 104)
const FILL_SIZE := Vector2(8, 28)
const FILL_LEVELS := 9

## Where things sit on the frame.
const WINDOW := Rect2(10, 10, 34, 34)
const DIAL_AT := Vector2(53, 10)
## The tip of the knob on the frame's divider; every arrow frame pivots here.
const PIVOT_AT := Vector2(57, 26)
const FILL_AT := Vector2(7, 61)
const DATE_FACE := Rect2(24, 58, 47, 18)
## Two centred lines, the season over the date, kept this far in from the
## face's sides. The rows were set by rendering and measuring the ink: 2 empty
## above the season, 3 between the lines and 3 below the date.
const TEXT_INSET := 3
## Centred text still counts its last letter's one-pixel spacing as part of its
## width, which sets it a pixel left of the middle; this takes it back.
const TEXT_NUDGE := 1
const SEASON_TOP := 2
const DATE_TOP := 10
## A label box tall enough for one line of the small face.
const LINE := 8
const SIZE := Vector2(98, 99)

## The big icon sheet is a grid of 48px cells, and each picture fills the 34px
## square in the middle of its cell -- the size of the window.
const ICON_CELL := 48
const ICON_INSET := 7
## Rows on the icon sheet: pictures without their backdrop, and bare backdrops.
const PICTURE_ROW := 3
const BACKDROP_ROW := 6

## The parts of the day, latest start last. `icon` is the picture's column on the
## sheet, `sky` the column of the backdrop it sits on (green day, orange dusk,
## blue night).
const PHASES: Array[Dictionary] = [
	{"name": "dawn", "from": 6 * 60, "icon": 6, "sky": 4},
	{"name": "day", "from": 8 * 60, "icon": 0, "sky": 0},
	{"name": "dusk", "from": 17 * 60, "icon": 4, "sky": 4},
	{"name": "night", "from": 20 * 60, "icon": 8, "sky": 7},
	{"name": "late", "from": 24 * 60, "icon": 9, "sky": 7},
]

## How warm each season runs, as a thermometer level: 0 is the hottest fill.
const SEASON_HEAT: Array[int] = [3, 1, 4, 7]

const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")

## Seconds between the picture's one-pixel breaths.
const BREATH := 0.8
## How long the set-and-rise takes, start to finish.
const SWAP_TIME := 0.9

## Gap from the screen's top and left edges, in screen pixels.
var margin := 10
## Whole-number zoom, set by the HUD to match its own.
var ui_scale := 2: set = set_ui_scale

var _window: Control
var _sky_back: TextureRect
var _sky: TextureRect
var _picture: TextureRect
var _leaving: TextureRect
var _arrow: TextureRect
var _fill: TextureRect
var _date: Label
var _season: Label

var _phase := -1
var _arrow_frame := -1
var _heat := -1
var _breath := 0.0
var _swap: Tween


## Which entry of PHASES the clock is in at `minutes`.
static func phase_at(minutes: int) -> int:
	var found := 0
	for i in PHASES.size():
		if minutes >= PHASES[i]["from"]:
			found = i
	return found


## Which arrow frame points at `minutes`. The day half of the dial (6:00 to
## 18:00) is swept by the top half of the arrow's travel and the night (18:00
## to 2:00) by the bottom, so the arrow is level at 18:00 and each frame takes
## the stretch of time nearest its own angle.
static func arrow_frame_at(minutes: int) -> int:
	var dusk := 18 * 60
	var sweep: float
	if minutes < dusk:
		sweep = remap(minutes, Calendar.DAY_START, dusk, 0.0, 0.5)
	else:
		sweep = remap(minutes, dusk, Calendar.PASS_OUT, 0.5, 1.0)
	return clampi(roundi(sweep * (ARROW_FRAMES - 1)), 0, ARROW_FRAMES - 1)


## The thermometer level, 0 hottest: the season's own warmth, a notch warmer in
## the afternoon and a notch cooler once it is dark.
static func heat_at(day: int, minutes: int) -> int:
	var level := SEASON_HEAT[Calendar.season_index(day)]
	if minutes >= 12 * 60 and minutes < 17 * 60:
		level -= 1
	elif minutes >= 20 * 60:
		level += 1
	return clampi(level, 0, FILL_LEVELS - 1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = SIZE

	# The window comes first so the frame's rim draws over the pictures' edges,
	# and it clips so a picture sinking out of it is cut off at the sill.
	_window = Control.new()
	_window.position = WINDOW.position
	_window.size = WINDOW.size
	_window.clip_contents = true
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_window)
	_sky_back = _rect(_window, ICONS, Rect2(), Vector2.ZERO)
	_sky = _rect(_window, ICONS, Rect2(), Vector2.ZERO)
	_leaving = _rect(_window, ICONS, Rect2(), Vector2.ZERO)
	_picture = _rect(_window, ICONS, Rect2(), Vector2.ZERO)

	# The dial sits behind the frame: the knob on the divider overlaps it. So
	# does the thermometer's liquid, which the frame's glass and rungs cover.
	_rect(self, ATLAS, DIAL_REGION, DIAL_AT)
	_rect(self, ATLAS, TUBE_REGION, FILL_AT)
	_fill = _rect(self, ATLAS, Rect2(), FILL_AT)
	# Springs from its bulb, so a change of level squashes up out of it.
	_fill.pivot_offset = Vector2(FILL_SIZE.x * 0.5, FILL_SIZE.y)
	_rect(self, ATLAS, FRAME_REGION, Vector2.ZERO)
	_arrow = _rect(self, ATLAS, Rect2(), PIVOT_AT - ARROW_TAIL)
	_arrow.pivot_offset = ARROW_TAIL

	# Both lines in the pack's 5px face, which leaves the plate room to breathe:
	# the 7px faces filled it edge to edge. The season sits on top in the softer
	# brown, like a heading, and the date under it in the dark one.
	var width := DATE_FACE.size.x - TEXT_INSET * 2
	_season = _label(UIFont.small(), MUTED_COLOR,
			Rect2(DATE_FACE.position + Vector2(TEXT_INSET + TEXT_NUDGE, SEASON_TOP), Vector2(width, LINE)))
	_date = _label(UIFont.small(), TEXT_COLOR,
			Rect2(DATE_FACE.position + Vector2(TEXT_INSET + TEXT_NUDGE, DATE_TOP), Vector2(width, LINE)))

	PlayerState.time_changed.connect(_on_clock)
	PlayerState.day_changed.connect(_on_clock)
	refresh(false)
	_place()


func _process(delta: float) -> void:
	# A one-pixel breath, stepped rather than tweened so it stays on the grid.
	# Held while a swap is moving the picture, so the two don't fight.
	if _swap != null and _swap.is_running():
		return
	_breath += delta
	if _breath >= BREATH:
		_breath -= BREATH
		_picture.position.y = -1.0 if _picture.position.y == 0.0 else 0.0


## Rereads the clock. With `animate` off everything simply jumps to the right
## picture, as on the first frame; with it on, changes are played.
func refresh(animate: bool = true) -> void:
	if _window == null:
		return
	var day := PlayerState.day
	var minutes := PlayerState.minutes
	_date.text = Calendar.date_text(day)
	_season.text = Calendar.season(day)

	var phase := phase_at(minutes)
	if phase != _phase:
		_show_phase(phase, animate and _phase >= 0)
	var frame := arrow_frame_at(minutes)
	if frame != _arrow_frame:
		_arrow_frame = frame
		var atlas := _arrow.texture as AtlasTexture
		atlas.region = Rect2(ARROW_ORIGIN + Vector2(frame * ARROW_CELL, 0), Vector2.ONE * ARROW_CELL)
		if animate:
			_pop(_arrow, Vector2(1.3, 1.3), 0.5, Tween.TRANS_ELASTIC)
	var heat := heat_at(day, minutes)
	if heat != _heat:
		_heat = heat
		(_fill.texture as AtlasTexture).region = Rect2(
				FILL_ORIGIN + Vector2(heat * FILL_SIZE.x, 0), FILL_SIZE)
		if animate:
			_pop(_fill, Vector2(1.0, 1.25), 0.4, Tween.TRANS_BACK)


func set_ui_scale(value: int) -> void:
	ui_scale = clampi(value, 1, 8)
	_place()


## The name of the part of the day on show, for tests and debugging.
func phase_name() -> String:
	return PHASES[_phase]["name"] if _phase >= 0 else ""


func _show_phase(phase: int, animate: bool) -> void:
	var entry: Dictionary = PHASES[phase]
	var picture := _icon_region(PICTURE_ROW, entry["icon"])
	var sky := _icon_region(BACKDROP_ROW, entry["sky"])
	_phase = phase
	if _swap != null:
		_swap.kill()
	if not animate:
		# An empty region draws the whole sheet, so the back layer gets one too.
		(_sky_back.texture as AtlasTexture).region = sky
		(_sky.texture as AtlasTexture).region = sky
		(_picture.texture as AtlasTexture).region = picture
		_sky.modulate.a = 1.0
		_leaving.visible = false
		_picture.position = Vector2.ZERO
		_picture.scale = Vector2.ONE
		return

	# The outgoing picture and sky step back a layer, and the new ones come in
	# on top of them.
	(_sky_back.texture as AtlasTexture).region = (_sky.texture as AtlasTexture).region
	(_leaving.texture as AtlasTexture).region = (_picture.texture as AtlasTexture).region
	(_sky.texture as AtlasTexture).region = sky
	(_picture.texture as AtlasTexture).region = picture
	_leaving.visible = true
	_leaving.position = Vector2(0, _picture.position.y)
	_sky.modulate.a = 0.0
	var depth := WINDOW.size.y
	_picture.position = Vector2(0, depth)
	_picture.pivot_offset = Vector2(WINDOW.size.x * 0.5, WINDOW.size.y)
	_picture.scale = Vector2.ONE

	_swap = create_tween().set_parallel(true)
	# The old picture bobs up a hair, then sinks out of the bottom of the window.
	_swap.tween_property(_leaving, "position:y", depth, SWAP_TIME * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_swap.tween_property(_sky, "modulate:a", 1.0, SWAP_TIME * 0.6) \
			.set_delay(SWAP_TIME * 0.2)
	# The new one rises past its spot and settles back, and lands with a squash.
	_swap.tween_property(_picture, "position:y", 0.0, SWAP_TIME * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(SWAP_TIME * 0.4)
	_swap.chain().tween_property(_picture, "scale", Vector2(1.15, 0.85), 0.08)
	_swap.chain().tween_property(_picture, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_swap.chain().tween_callback(func() -> void: _leaving.visible = false)


## Swells `node` to `peak` from its pivot and lets it spring back.
func _pop(node: Control, peak: Vector2, seconds: float, trans: Tween.TransitionType) -> void:
	node.scale = peak
	create_tween().tween_property(node, "scale", Vector2.ONE, seconds) \
			.set_trans(trans).set_ease(Tween.EASE_OUT)


func _icon_region(row: int, column: int) -> Rect2:
	return Rect2(column * ICON_CELL + ICON_INSET, row * ICON_CELL + ICON_INSET,
			WINDOW.size.x, WINDOW.size.y)


## Anchored top-left, so the offsets are measured in from that corner. The
## scale grows the clock from there, out and down, never off the edge.
func _place() -> void:
	scale = Vector2.ONE * ui_scale
	offset_left = margin
	offset_right = margin
	offset_top = margin
	offset_bottom = margin


func _rect(parent: Control, sheet: Texture2D, region: Rect2, at: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	rect.texture = atlas
	rect.position = at
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _label(font: Font, color: Color, box: Rect2) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", UIFont.SMALL_SIZE)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = box.position
	label.size = box.size
	add_child(label)
	return label


func _on_clock(_value: int) -> void:
	refresh()
