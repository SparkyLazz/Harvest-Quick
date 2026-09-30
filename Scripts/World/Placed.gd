class_name Placed
extends StaticBody2D

## Something the player set down, and the little it has to remember about
## having been set down.
##
## A placed thing is solid — the player walks around a chest rather than
## through it — so this is a body first and a bookkeeper second. What it
## keeps is only what taking it back up needs: which item it came out of, and
## where it stands. Neither can be worked out afterwards from the node alone,
## because the same scene may be reachable from more than one item and the
## node's position is a point rather than a tile.
##
## Subclasses that do something when the player presses interact say so by
## implementing [method interact]. Doing nothing is a perfectly good answer —
## a fence post has nothing to offer — so this does nothing by default rather
## than making every silent object declare its silence.

## The item this came out of, or null when it was not placed by the player —
## a chest that was part of the farm from the start, say.
var source: PlaceableData

## The tile its top-left corner stands on.
var origin: Vector2i

## Called by [WorldObjects] once the thing is in the world. Named for what
## happened rather than for what it sets, because a subclass overriding it is
## usually reacting to the event, not reading the arguments.
func placed_as(from: PlaceableData, at: Vector2i) -> void:
	source = from
	origin = at

## Whatever this does when the player presses interact while facing it.
## Returns whether the press was spent, so the player can tell an object that
## answered from one that ignored it.
func interact() -> bool:
	return false

## What goes back in the satchel when this is taken up, or null if nothing
## does.
func recover() -> PlaceableData:
	if source != null and source.recoverable:
		return source
	return null
