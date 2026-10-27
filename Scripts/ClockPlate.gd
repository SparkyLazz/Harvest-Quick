class_name ClockPlate
extends Control

## The date and the time, on the same rounded plate as the hotbar, pinned to the
## top-right corner. Two lines: "Mon 1  Spring" over "6:00 am". It follows
## PlayerState's clock by signal, so it only redraws when the shown text changes.
##
## Sized in source pixels and scaled up whole, like the bars, so the pixel font
## stays on its grid.

const PLATE := preload("res://Assets/UI/Panel_Plate.png")
const PLATE_PATCH := 6
const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")
## The hour turns this colour from midnight on, as a nudge to get to bed.
const LATE_COLOR := Color("b5513f")
## Midnight, in Calendar's minutes.
const LATE := 24 * 60

## Inside the plate's border, in source pixels.
var padding := 6
## Gap from the screen's top and right edges, in screen pixels.
var margin := 10
## Whole-number zoom, set by the HUD to match its own.
var ui_scale := 2: set = set_ui_scale

var _plate: NinePatchRect
var _date: Label
var _time: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_plate = NinePatchRect.new()
	_plate.texture = PLATE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_plate.set_patch_margin(side, PLATE_PATCH)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	_date = _label(TEXT_COLOR)
	_time = _label(MUTED_COLOR)
	PlayerState.time_changed.connect(_on_clock)
	PlayerState.day_changed.connect(_on_clock)
	refresh()


## Rereads the clock and refits the plate around the text.
func refresh() -> void:
	if _plate == null:
		return
	var day := PlayerState.day
	_date.text = "%s  %s" % [Calendar.date_text(day), Calendar.season(day)]
	_time.text = Calendar.time_text(PlayerState.minutes)
	_time.add_theme_color_override("font_color",
			LATE_COLOR if PlayerState.minutes >= LATE else MUTED_COLOR)
	var font := UIFont.title()
	var line := font.get_height(UIFont.SIZE)
	# Measured against the widest the date can be, so the plate holds still as
	# the days go by instead of twitching a pixel narrower on short names.
	var widest := font.get_string_size("Wed 28  Summer", HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE).x
	var w := ceilf(widest) + padding * 2
	var h := ceilf(line * 2) + padding * 2
	_plate.size = Vector2(w, h)
	_date.position = Vector2(padding, padding)
	_time.position = Vector2(padding, padding + line)
	for label: Label in [_date, _time]:
		label.size = Vector2(w - padding * 2, line)
	scale = Vector2.ONE * ui_scale
	# Anchored top-right, so the offsets are measured back from that corner.
	offset_left = -w * ui_scale - margin
	offset_right = offset_left
	offset_top = margin
	offset_bottom = margin


func set_ui_scale(value: int) -> void:
	ui_scale = clampi(value, 1, 8)
	refresh()


func _label(color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UIFont.title())
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_plate.add_child(label)
	return label


func _on_clock(_value: int) -> void:
	refresh()
