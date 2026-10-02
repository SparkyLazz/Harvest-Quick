class_name ScreenTransition
extends CanvasLayer

## The black that covers the screen while the player is going somewhere.
##
## A fade out, a beat of darkness, a fade in — the Harvest Moon doorway. The
## beat matters: a cross-fade with no hold reads as a stutter rather than as
## having gone somewhere, and the whole job of this is to make a teleport feel
## like travel.
##
## It owns the fade and nothing else. What happens while the screen is dark is
## handed in as a callable, so this knows nothing about players, doors or
## maps, and the same curtain serves a walk down a path, a night's sleep or a
## cut to a cutscene.
##
## It sits above everything, the HUD included, because a hotbar left bright
## over a black screen is the one thing that would give the trick away.
##
## Reached with get_tree().get_first_node_in_group("transition").

## Emitted once the screen is fully covered, before the hidden work is done.
signal covered
## Emitted when the screen is clear again.
signal revealed

## What the screen fades to.
@export var colour: Color = Color(0.05, 0.04, 0.07)

@export_group("Timing")
## Seconds to go dark.
@export var fade_out: float = 0.35
## Seconds spent fully dark, after the hidden work is done. Short, but not
## nothing — this is the beat that reads as distance covered.
@export var hold: float = 0.18
## Seconds to come back.
@export var fade_in: float = 0.4

var _sheet: ColorRect
var _busy: bool = false

func _ready() -> void:
	add_to_group("transition")
	# Above the HUD, whatever layer the HUD is on.
	layer = 128
	_sheet = ColorRect.new()
	_sheet.color = colour
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never takes a click: the screen being dark should not also mean the
	# game stops hearing the mouse.
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.modulate.a = 0.0
	_sheet.visible = false
	add_child(_sheet)

## Whether a transition is already under way. Anything that could start one
## should ask first, or two doorways in a row will fight over the curtain.
func is_busy() -> bool:
	return _busy

## Covers the screen, calls [param between], and uncovers it.
##
## Awaitable: the caller gets control back once the screen is clear again,
## which is the natural moment to give the player theirs back too.
func cross(between: Callable = Callable()) -> void:
	if _busy:
		return
	_busy = true
	_sheet.visible = true
	await _fade(1.0, fade_out)
	covered.emit()
	if between.is_valid():
		between.call()
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	await _fade(0.0, fade_in)
	_sheet.visible = false
	_busy = false
	revealed.emit()

func _fade(to: float, seconds: float) -> void:
	if seconds <= 0.0:
		_sheet.modulate.a = to
		return
	var tween := create_tween()
	tween.tween_property(_sheet, "modulate:a", to, seconds).set_trans(Tween.TRANS_SINE)
	await tween.finished
