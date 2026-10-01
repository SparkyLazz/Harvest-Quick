class_name Placed
extends StaticBody2D

## Something standing on the map, and the little it has to remember about
## standing there.
##
## A placed thing is solid — the player walks around a chest rather than
## through it — so this is a body first and a bookkeeper second. What it
## keeps is only what taking it back up needs: which item it came out of, and
## where it stands. Neither can be worked out afterwards from the node alone,
## because the same scene may be reachable from more than one item and the
## node's position is a point rather than a tile.
##
## Not everything here was set down by the player. A tree drawn into the farm
## before the game started is a [Placed] too — it has no [member source], and
## is picked up out of the world rather than back into the hand it came from.
##
## **Objects answer for themselves.** A swing arrives as [method hit] with
## the tool's name, and the thing decides whether that tool means anything to
## it: an axe fells a tree, a can waters a crop, and a fence post ignores
## both. The alternative — the player knowing which tool does what to which
## object — makes the player grow by a branch for every tool and every kind
## of thing, and there is no end to that.

## Emitted when it takes a hit that counts, with how many are left.
signal struck(remaining: int)
## Emitted when the last hit lands, just before it is taken out of the world.
signal broken

## The item this came out of, or null when it was not placed by the player.
var source: PlaceableData

## The tile its top-left corner stands on.
var origin: Vector2i

@export_group("Breaking")
## Which tool breaks it, named as an [member ItemData.action]. Empty means
## nothing does, which is right for anything that is only ever picked up.
@export var broken_by: StringName = &""

## How many hits of that tool it takes. One is a single swing.
@export var hits: int = 1

## What it leaves behind when broken, beyond whatever [method recover]
## returns. A tree drops wood; the tree itself is not an item.
@export var drops: Array[ItemData] = []

## How many of each, matched by position. A short list is padded with ones,
## so leaving it empty means one of everything.
@export var drop_counts: Array[int] = []

## Hits taken so far.
var _struck: int = 0

## Called by [WorldObjects] once the thing is in the world. Named for what
## happened rather than for what it sets, because a subclass overriding it is
## usually reacting to the event, not reading the arguments.
func placed_as(from: PlaceableData, at: Vector2i) -> void:
	source = from
	origin = at

## Answers a swing of [param action] landing on this. Returns whether the
## swing meant anything, so the player can tell a tool that worked from one
## that bounced off.
##
## The default is the one behaviour nearly everything wants: the right tool
## wears it down and eventually breaks it, and the wrong tool does nothing.
## Subclasses that answer differently — a crop drinking from a can — override
## this and call up for whatever they do not handle themselves.
func hit(action: StringName) -> bool:
	if action == &"" or action != broken_by:
		return false
	var total: int = maxi(hits, 1)
	# A blow that would finish it is checked before it is spent. Otherwise a
	# full satchel eats the swing: the hit counts, the break is refused, and
	# the player is left striking a thing that can no longer be broken.
	if _struck + 1 >= total and not can_take_drops():
		return false
	_struck += 1
	var left: int = total - _struck
	struck.emit(left)
	if left > 0:
		return true
	return _break()

## Whether a swing of [param action] would do anything, without doing it.
##
## The mirror of [method hit], and it exists because the cursor has to answer
## the same question every frame and must not water a crop to find out. A
## subclass that overrides one almost always overrides both; keeping them
## next to each other is the only thing stopping them drifting apart.
func accepts(action: StringName) -> bool:
	return action != &"" and action == broken_by

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

## Whether the satchel could hold everything breaking this would produce.
##
## Asked before anything is destroyed, because a drop with nowhere to go is
## worse than a swing that did nothing: the player loses the tree *and* the
## wood.
func can_take_drops() -> bool:
	for i in drops.size():
		var item: ItemData = drops[i]
		if item == null:
			continue
		if not Inventory.has_room_for(item, _drop_count(i)):
			return false
	return true

## Hands over the drops and takes the thing out of the world. Returns whether
## it went.
func _break() -> bool:
	if not can_take_drops():
		return false
	for i in drops.size():
		var item: ItemData = drops[i]
		if item != null:
			Inventory.add(item, _drop_count(i))
	broken.emit()
	_leave_world()
	return true

## How many of drop [param index] to give. Counts run out before drops do
## more often than the reverse, so a missing one means one.
func _drop_count(index: int) -> int:
	if index >= drop_counts.size():
		return 1
	return maxi(drop_counts[index], 1)

## Takes itself off the map.
func _leave_world() -> void:
	var world := get_tree().get_first_node_in_group("world_objects") as WorldObjects
	if world == null:
		queue_free()
		return
	var taken := world.remove(origin)
	if taken != null:
		taken.queue_free()
	else:
		queue_free()
