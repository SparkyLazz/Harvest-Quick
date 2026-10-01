@tool
class_name InventoryPanel
extends Control

## The inventory window. Empty on purpose — it is the panel and nothing
## else, waiting for something to put inside it.
##
## The frame is one sprite cut nine ways. The margins are not guesses: the
## sprite's only uniform region is the parchment at x 19-38 and y 18-37, so
## everything outside that is corner or edge and is pinned. That keeps the
## four corner bolts round and the side planks from smearing, however far
## the window is dragged open.
##
## It opens and closes on [member toggle_action], which the project already
## binds to E, I and Escape.
##
## The window itself is also the backdrop a stack is put down on when the
## player changes their mind. Clicks reach the slots first — a child is
## picked before its parent, and the slots take what they answer — so
## anything arriving here landed on the frame, the parchment or the gap
## between two slots, and means "never mind".

## Emitted when the window opens.
signal opened
## Emitted when the window closes.
signal closed

## Input action that toggles the window.
@export var toggle_action: StringName = &"inventory"
## Start hidden. Off, the window is up from the first frame, which is
## handy while dressing it in the editor.
@export var closed_on_start: bool = true

@export_group("Motion")
## Seconds for the window to open or close. Zero makes it appear at once.
@export var open_time: float = 0.14
## How small the window starts before it springs open. 1.0 is no spring.
@export var open_from: float = 0.9

var _tween: Tween
## Whether the window is meant to be up. Not the same as [member visible],
## which stays true through the closing animation.
var _is_open: bool = false
## The scale this window was placed at. The open and close animations work
## relative to it, so whatever the scene set survives them — hardcoding
## Vector2.ONE here silently flattens a window placed at 2x or 4x.
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	pivot_offset = size * 0.5
	gui_input.connect(_on_backdrop_input)
	_base_scale = scale
	if Engine.is_editor_hint():
		return
	var close := get_node_or_null("Close") as BaseButton
	if close != null:
		close.pressed.connect(self.close)
	if closed_on_start:
		_is_open = false
		visible = false
		modulate.a = 0.0
		scale = _base_scale * open_from
	else:
		_is_open = true

func _unhandled_input(event: InputEvent) -> void:
	if toggle_action == &"" or not InputMap.has_action(toggle_action):
		return
	if event.is_action_pressed(toggle_action):
		toggle()
		get_viewport().set_input_as_handled()

## Puts a carried stack back when the click that would have placed it landed
## on the window rather than on a slot.
func _on_backdrop_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not Inventory.has_grab():
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
		return
	Inventory.return_grab()
	accept_event()

## Whether the window is up, or on its way up.
func is_open() -> bool:
	return _is_open

## Flips the window between open and shut.
func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	opened.emit()
	_animate(true)

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	closed.emit()
	_animate(false)

func _animate(opening: bool) -> void:
	pivot_offset = size * 0.5
	if _tween != null:
		_tween.kill()
		_tween = null
	if Engine.is_editor_hint() or open_time <= 0.0:
		modulate.a = 1.0 if opening else 0.0
		scale = _base_scale if opening else _base_scale * open_from
		visible = opening
		return
	if opening:
		scale = _base_scale * open_from
		modulate.a = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	# Alpha eases plainly — a springy curve would overshoot past opaque.
	(_tween.tween_property(self, "modulate:a", 1.0 if opening else 0.0, open_time)
		.set_trans(Tween.TRANS_SINE))
	(_tween.tween_property(
			self, "scale",
			_base_scale if opening else _base_scale * open_from, open_time)
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	if not opening:
		# Drop it out of the draw list only once it has finished shrinking.
		# A tween killed by a re-open never emits this, which is what we want.
		_tween.finished.connect(_on_close_finished)

func _on_close_finished() -> void:
	if _is_open:
		return
	visible = false
