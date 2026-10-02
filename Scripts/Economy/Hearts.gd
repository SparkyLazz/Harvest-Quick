extends Node

## How many more times the player can fail before the run is over.
##
## Missing a payment used to end the run on the spot. It no longer does, and
## that is the whole point of this: a collector who kills you the first time
## you are forty coins short makes the player hoard, never gamble on a crop,
## and never find out what the forecast is for. Three strikes turns a bad week
## into a story instead of a reload.
##
## Counted in [b]half[/b] hearts, which looks like a strange unit until you see
## the art: the artist drew every heart full, half and empty, and
## [ProfilePanel] has shown half-hearts since before any of this existed. A
## pool that counted whole hearts would need converting at that boundary, and a
## conversion is where an off-by-one lives. So the pool speaks the row's
## language, [method lose_heart] is the one that knows a heart is two of them,
## and the half is already there for a penalty that is worth less than a whole.
##
## Reached as the [code]Hearts[/code] autoload.

## Emitted whenever the row changes, ready to hand to
## [method ProfilePanel.set_health].
signal changed(halves: int, max_halves: int)

## Emitted when some are lost, with how many and what is left.
signal lost(halves: int, remaining: int)

## Emitted when the last one goes. The run is over — this is the only place
## that is ever true, so whatever ends a run listens here and nowhere else.
signal emptied

## Hearts the player starts a run with. Three, because two is a coin flip and
## four is long enough that the first mistake stops mattering.
@export var starting_hearts: int = 3

## Half-hearts remaining.
var halves: int = 0
## Half-hearts the row can hold.
var max_halves: int = 0

func _ready() -> void:
	reset()

## Put the row back to the start of a run.
func reset() -> void:
	max_halves = starting_hearts * 2
	halves = max_halves
	changed.emit(halves, max_halves)

## Take [param count] half-hearts. Returns whether the player is still standing,
## so a caller can stop what it is doing without having to ask afterwards.
func lose(count: int = 1) -> bool:
	if count <= 0 or halves <= 0:
		return halves > 0
	halves = maxi(halves - count, 0)
	lost.emit(count, halves)
	changed.emit(halves, max_halves)
	if halves <= 0:
		emptied.emit()
		return false
	return true

## Take a whole heart. What a missed payment costs.
func lose_heart() -> bool:
	return lose(2)

## Give [param count] half-hearts back, never past the top of the row.
func heal(count: int = 1) -> void:
	if count <= 0 or halves >= max_halves:
		return
	halves = mini(halves + count, max_halves)
	changed.emit(halves, max_halves)

## Whole hearts left, halves included — 2.5 is two and a half.
func hearts() -> float:
	return halves / 2.0

## Whether the run is over.
func is_empty() -> bool:
	return halves <= 0
