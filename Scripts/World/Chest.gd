class_name Chest
extends Placed

## A box with a hinged lid.
##
## The artist drew the lid opening as five frames and nothing else, so that
## one animation is played forward to open and backward to shut; there is no
## closing animation to keep in step with it, and no pair of sequences that
## could disagree about what half-open looks like.
##
## Storage is not here yet. What is here is the lid and the fact that the
## player can reach it, which is enough to see a chest placed, walked around
## and opened before anything is put inside one.

## Emitted when the lid finishes opening.
signal opened
## Emitted when the lid finishes shutting.
signal closed

## The one animation on the sheet: shut on the first frame, wide on the last.
const LID := &"lid"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _open: bool = false

func _ready() -> void:
	sprite.animation_finished.connect(_on_lid_finished)
	# Sitting on the shut frame rather than playing to it, so a chest that
	# has always been closed does not flap when the farm loads.
	sprite.animation = LID
	sprite.frame = 0

## Whether the lid is open, or on its way open.
func is_open() -> bool:
	return _open

func interact() -> bool:
	if _open:
		shut()
	else:
		open()
	return true

func open() -> void:
	if _open:
		return
	_open = true
	sprite.play(LID)

func shut() -> void:
	if not _open:
		return
	_open = false
	sprite.play_backwards(LID)

func _on_lid_finished() -> void:
	if _open:
		opened.emit()
	else:
		closed.emit()
