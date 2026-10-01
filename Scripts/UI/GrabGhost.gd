class_name GrabGhost
extends Control

## The stack riding on the mouse while it is being moved from one slot to
## another.
##
## It lives in the HUD rather than in the inventory window, because the two
## places a stack can be put down are in different scenes: the backpack grid
## inside the window, and the real hotbar along the bottom of the screen. A
## ghost owned by the window could not be carried over the hotbar without
## being clipped by the window it came from.
##
## It is only ever a picture. The stack itself is in [Inventory], which is
## what makes it safe for this to be destroyed, hidden or rebuilt at any
## moment — there is nothing in here to lose.
##
## It ignores the mouse entirely, so the slot underneath still gets the click
## that puts the stack down. A ghost that could be clicked would make the
## last slot of a move unreachable, because the thing being moved would
## always be in the way of where it was going.

## How big the icon is drawn. The slot icons are 22 across; the carried one
## is a touch smaller so it reads as lifted off the board rather than as
## another slot sliding about.
@export var icon_size: Vector2 = Vector2(20.0, 20.0)

## Where the icon sits relative to the pointer. Down and right, clear of the
## cursor's own tip.
@export var pointer_offset: Vector2 = Vector2(2.0, 2.0)

## The font the count is written in.
@export var font: Font

## Colour of the count.
@export var count_colour: Color = Color(1, 1, 1)

@export_group("Motion")
## Seconds for the ghost to appear or disappear.
@export var fade_time: float = 0.08

var _icon: TextureRect
var _count: Label
var _fade: Tween

func _ready() -> void:
	# Over the window and over the hotbar both, whatever order the HUD
	# happens to hold them in.
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_build()
	Inventory.grab_changed.connect(_refresh)
	_refresh()
	set_process(false)

func _process(_delta: float) -> void:
	position = get_global_mouse_position() + pointer_offset

func _build() -> void:
	_icon = TextureRect.new()
	_icon.size = icon_size
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count = Label.new()
	_count.position = Vector2(0.0, icon_size.y - 10.0)
	_count.size = Vector2(icon_size.x, 12.0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		_count.add_theme_font_override("font", font)
	_count.add_theme_font_size_override("font_size", 9)
	_count.add_theme_color_override("font_color", count_colour)
	# An outline, because this one is read against whatever happens to be
	# under the mouse rather than against the parchment of a slot.
	_count.add_theme_color_override("font_outline_color", Color(0.18, 0.12, 0.11))
	_count.add_theme_constant_override("outline_size", 4)
	add_child(_count)

func _refresh() -> void:
	var item: ItemData = Inventory.grabbed_item()
	var count: int = Inventory.grabbed_count()
	var carrying := item != null and count > 0
	_icon.texture = item.icon if carrying else null
	_count.text = str(count) if carrying and count > 1 else ""
	# Followed only while there is something to follow with. An empty ghost
	# tracking the mouse every frame is a cost paid for nothing.
	set_process(carrying)
	if carrying:
		position = get_global_mouse_position() + pointer_offset
	_fade_to(1.0 if carrying else 0.0)

func _fade_to(alpha: float) -> void:
	if is_equal_approx(modulate.a, alpha):
		return
	if _fade != null:
		_fade.kill()
	if fade_time <= 0.0:
		modulate.a = alpha
		return
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, fade_time)
