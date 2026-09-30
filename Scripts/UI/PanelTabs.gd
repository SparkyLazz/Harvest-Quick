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
## The tabs sit behind the page, which is drawn after them, so the page's
## top edge hides however much of a tab is tucked below it. Unchosen tabs
## sit low and mostly hidden; the chosen one rises clear of the edge, the
## way a card lifts out of a hand when you pick it. That rise is the only
## thing marking the selection apart from the pressed texture, so it runs
## on every change rather than only the first.
##
## The page ignores the mouse, so clicks still fall through to the part of
## a tab hidden underneath it.

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
		_apply(_applied)

@export_group("Motion")
## Where a chosen tab sits, as a y offset inside the strip.
@export var tab_raised_y: float = 0.0
## Where the others sit. Further down means more of them is swallowed by
## the page drawn over the top.
@export var tab_tucked_y: float = 10.0
## Seconds for a tab to rise or drop. Zero puts them in place at once.
@export var tab_rise: float = 0.18
## How far past its resting place a rising tab overshoots. 1.0 is no kick.
@export var rise_overshoot: float = 1.0

@onready var _bar: Control = $Bar
@onready var _pages: Control = $Page/Pages

var _applied: bool = false
var _rises: Array[Tween] = []

func _ready() -> void:
	for i in _bar.get_child_count():
		var button := _bar.get_child(i) as BaseButton
		_rises.append(null)
		if button == null:
			continue
		button.pressed.connect(_on_tab_pressed.bind(i))
	_apply(false)

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

func _apply(animate: bool) -> void:
	if _bar == null or _pages == null:
		return
	_applied = true
	var instant := not animate or Engine.is_editor_hint() or tab_rise <= 0.0
	for i in tab_count():
		var button := _bar.get_child(i) as BaseButton
		if button != null:
			# The buttons share a ButtonGroup, which is what stops the
			# chosen tab un-pressing itself when it is clicked again.
			button.set_pressed_no_signal(i == current)
			_settle(i, button, i == current, instant)
		(_pages.get_child(i) as CanvasItem).visible = i == current

func _settle(index: int, button: Control, raised: bool, instant: bool) -> void:
	var target := tab_raised_y if raised else tab_tucked_y
	var tween: Tween = _rises[index] if index < _rises.size() else null
	if tween != null:
		tween.kill()
		_rises[index] = null
	if instant:
		button.position.y = target
		return
	if is_equal_approx(button.position.y, target):
		return
	var rise := create_tween()
	rise.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if raised and rise_overshoot > 1.0:
		var over := target - (tab_tucked_y - tab_raised_y) * (rise_overshoot - 1.0)
		rise.tween_property(button, "position:y", over, tab_rise * 0.6)
		rise.tween_property(button, "position:y", target, tab_rise * 0.4)
	else:
		rise.tween_property(button, "position:y", target, tab_rise)
	_rises[index] = rise
