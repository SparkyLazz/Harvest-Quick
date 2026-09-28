class_name PixelScrollBar
extends VSlider

## The menu's scrollbar: a knob that slides along a track, driving a
## [ScrollContainer] beside it.
##
## It is a [VSlider] rather than a [VScrollBar] because of what the art
## is. The slider set draws the knob as three whole sprites — a resting
## one, a lighter hover and a darker pressed — each a stubby rounded
## capsule eighteen pixels long. A scrollbar's grabber has to grow and
## shrink with how much there is to scroll, so wearing that sprite meant
## stretching an eighteen-pixel capsule over a couple of hundred, and it
## came out as a thin pill with nothing of the original shape left. A
## slider's grabber is an icon drawn at its own size and never stretched,
## which is what the sprite was drawn to be.
##
## The track is the one thing here that is meant to stretch: it is three
## tiles — a rounded cap, a length of shaft, a rounded cap — composed into
## one texture and nine-sliced down its length, so only the shaft repeats.
##
## The container keeps its own scrolling — the wheel, dragging, the keys —
## and only its bar is hidden. This slider mirrors it in both directions,
## so scrolling by any means moves the knob and moving the knob scrolls.

const TRACK: Texture2D = preload("res://Assets/UI/Sliders/Scroll_Track.png")
const KNOB: Texture2D = preload("res://Assets/UI/Sliders/Scroll_Grabber.png")
const KNOB_HOVER: Texture2D = preload("res://Assets/UI/Sliders/Scroll_Grabber_Hover.png")
const KNOB_PRESSED: Texture2D = preload("res://Assets/UI/Sliders/Scroll_Grabber_Pressed.png")
## Width of the art, and so of the column the bar needs.
const WIDTH: int = 7
## Rounded cap at either end of the track, in pixels. Everything between
## them is one repeating colour.
const TRACK_CAP_TOP: int = 4
const TRACK_CAP_BOTTOM: int = 2
## Left and right margins on the track, which must add up to its full
## width. A slider works out how thick to draw its track from the
## horizontal margins of the style box, so a box with none draws nothing
## at all; splitting the whole width between the two sides gives the
## right thickness and leaves no middle column to stretch.
const TRACK_SIDE_LEFT: int = 3
const TRACK_SIDE_RIGHT: int = WIDTH - TRACK_SIDE_LEFT

var _scroll: ScrollContainer
var _bar: VScrollBar
var _syncing: bool = false

## Takes over [param scroll]'s vertical scrolling and hides its own bar.
## Call before either is in the tree or after; neither cares.
static func attach(scroll: ScrollContainer) -> PixelScrollBar:
	var bar := PixelScrollBar.new()
	bar._scroll = scroll
	return bar

func _ready() -> void:
	_dress()
	focus_mode = Control.FOCUS_NONE
	scrollable = true
	step = 1.0

	if _scroll == null:
		return

	# The container still does all the scrolling; only its bar goes.
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER

	_bar = _scroll.get_v_scroll_bar()
	_bar.changed.connect(_follow_scroll)
	_bar.value_changed.connect(func(_value: float) -> void: _follow_scroll())
	value_changed.connect(_drive_scroll)
	_follow_scroll()

## Re-reads the container and shows or hides the knob accordingly. The
## menu calls this when a section is brought back, since a hidden bar
## hears nothing while its section is away.
func refresh() -> void:
	_follow_scroll()

# --- Syncing -----------------------------------------------------------

## Mirrors the container onto the knob. A slider counts up towards its
## top end and a scroll counts down from it, so the value is the distance
## still to go rather than the distance travelled: knob at the top means
## the content is at its start.
func _follow_scroll() -> void:
	if _bar == null or _syncing:
		return

	var travel: float = maxf(_bar.max_value - _bar.page, 0.0)
	_syncing = true
	max_value = travel
	page = 0.0
	set_value_no_signal(travel - _bar.value)
	_syncing = false

	# Nothing to scroll, nothing to show.
	visible = travel > 0.0

func _drive_scroll(new_value: float) -> void:
	if _bar == null or _syncing:
		return
	_syncing = true
	_bar.value = max_value - new_value
	_syncing = false

# --- Look --------------------------------------------------------------

func _dress() -> void:
	custom_minimum_size.x = WIDTH
	size.x = WIDTH

	add_theme_icon_override("grabber", KNOB)
	add_theme_icon_override("grabber_highlight", KNOB_HOVER)
	# A slider has no pressed grabber, only a disabled one. The darkest
	# of the three sprites is the closest thing the set has to greyed
	# out, so that is where it goes.
	add_theme_icon_override("grabber_disabled", KNOB_PRESSED)
	add_theme_stylebox_override("slider", _track())
	# A slider normally paints the travelled part of its track in a second
	# colour. A scrollbar has no such thing, so both halves are blank and
	# the track shows through whole.
	add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
	add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
	# Left centred, the knob would hang half off the track at either end.
	# A scrollbar's knob stays inside the trough it runs in.
	add_theme_constant_override("center_grabber", 0)

func _track() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = TRACK
	box.texture_margin_top = TRACK_CAP_TOP
	box.texture_margin_bottom = TRACK_CAP_BOTTOM
	box.texture_margin_left = TRACK_SIDE_LEFT
	box.texture_margin_right = TRACK_SIDE_RIGHT
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return box
