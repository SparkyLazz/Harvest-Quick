@tool
class_name PanelTabs
extends Control

## The tab strip on the right half of the inventory window.
##
## One button per page, one page per button, matched by position: the
## third button shows the third child of Pages. Both live in the scene, so
## adding a tab is adding a button and a page next to each other — this
## script only keeps the two in step and does not build either.
##
## The tabs stand above the page and the page is drawn after them, so its
## top edge covers the bottom of each tab and they read as folder tabs
## tucked behind it. The page ignores the mouse, so clicks fall through to
## the part of a tab hidden underneath.
##
## The pages are empty for now. They are where Settings, Encyclopedia,
## Statistics and Inventory will go.

## Emitted when a different page is brought up, with its index.
signal tab_changed(index: int)

## The page on show.
@export var current: int = 0:
	set(value):
		var count := tab_count()
		var clamped := clampi(value, 0, maxi(count - 1, 0))
		if clamped == current and _applied:
			return
		current = clamped
		_apply()

@onready var _bar: HBoxContainer = $Bar
@onready var _pages: Control = $Page/Pages

var _applied: bool = false

func _ready() -> void:
	for i in _bar.get_child_count():
		var button := _bar.get_child(i) as BaseButton
		if button == null:
			continue
		button.pressed.connect(_on_tab_pressed.bind(i))
	_apply()

## How many tabs the scene holds. The bar and the page stack should agree;
## if they ever do not, the smaller one wins so nothing reaches past its end.
func tab_count() -> int:
	if _bar == null or _pages == null:
		return 0
	return mini(_bar.get_child_count(), _pages.get_child_count())

func _on_tab_pressed(index: int) -> void:
	var was := current
	current = index
	if current != was:
		tab_changed.emit(current)

func _apply() -> void:
	if _bar == null or _pages == null:
		return
	_applied = true
	for i in tab_count():
		var button := _bar.get_child(i) as BaseButton
		if button != null:
			# The buttons share a ButtonGroup, which is what stops the
			# chosen tab un-pressing itself when it is clicked again.
			button.set_pressed_no_signal(i == current)
		(_pages.get_child(i) as CanvasItem).visible = i == current
