class_name InventorySlot
extends Control

## One square of the inventory grid: the slot art, the item icon, its stack count
## and, for hotbar slots, the number key that selects it. It draws itself and
## only reports what the mouse does; the panel decides what that means.

signal pressed(index: int, button: int)
signal hover_started(index: int)
signal hover_ended(index: int)

# Slot art comes off the same sheet as the hotbar: light, a mid shade for
# hover, and the darkest shade for the held slot.
const HOVER_REGION := Rect2(281, 121, 30, 32)
const COUNT_COLOR := Color("fff4dc")
const OUTLINE_COLOR := Color("5a3d3d")
const KEY_COLOR := Color("90625d")

var index: int = 0
var item: String = "": set = set_item
var count: int = 0: set = set_count
## Drawn in the darkest shade: the hotbar slot the player is holding.
var held: bool = false: set = set_held
## Number key printed in the corner of hotbar slots. 0 prints nothing.
var hotkey: int = 0: set = set_hotkey
## Zoom on top of each item's own icon zoom.
var icon_scale: float = 1.0
## Off for the item that rides on the cursor, which is only an icon.
var show_background: bool = true

var _hover := false

func _init() -> void:
	custom_minimum_size = HUD.SLOT_REGION.size
	size = custom_minimum_size
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		# Only the two real buttons are ours. The wheel is left alone so it
		# travels up to the scroll area underneath.
		if button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT:
			pressed.emit(index, button)
			accept_event()


func _draw() -> void:
	if show_background:
		var region := HUD.SLOT_SELECTED_REGION if held \
				else (HOVER_REGION if _hover else HUD.SLOT_REGION)
		draw_texture_rect_region(HUD.SHEET, Rect2(Vector2.ZERO, size), region)
	var entry := ItemDB.info(item)
	if not entry.is_empty():
		var region: Rect2 = entry["region"]
		var icon_size := (region.size * icon_scale * float(entry["scale"])).round()
		draw_texture_rect_region(entry["sheet"],
				Rect2(((size - icon_size) * 0.5).round(), icon_size), region)
	if count > 1:
		var font := UIFont.title()
		var at := Vector2(0, size.y - 4)
		draw_string_outline(font, at, str(count), HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 3, UIFont.SIZE, 3, OUTLINE_COLOR)
		draw_string(font, at, str(count), HORIZONTAL_ALIGNMENT_RIGHT,
				size.x - 3, UIFont.SIZE, COUNT_COLOR)
	if hotkey > 0 and show_background:
		draw_string(UIFont.body(), Vector2(4, 11), str(hotkey),
				HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE, KEY_COLOR)


func _set_hover(on: bool) -> void:
	_hover = on
	queue_redraw()
	if on:
		hover_started.emit(index)
	else:
		hover_ended.emit(index)


func set_item(value: String) -> void:
	item = value
	queue_redraw()


func set_count(value: int) -> void:
	count = value
	queue_redraw()


func set_held(value: bool) -> void:
	held = value
	queue_redraw()


func set_hotkey(value: int) -> void:
	hotkey = value
	queue_redraw()
