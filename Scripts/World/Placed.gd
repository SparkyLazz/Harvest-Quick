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

## How many tiles it covers, counting right and down from [member origin].
##
## Whatever put it in the world sets this: [method placed_as] takes it from
## the item, and scenery sown from a [NatureKind] takes it from the kind. One
## tile is right for everything small, and is what a scene drawn by hand gets
## unless it says otherwise.
##
## It is here rather than only on [PlaceableData] because not everything in
## the world came out of an item. A tree has no item and still covers four
## tiles, and a tree the map has filed under one of them is a tree the axe
## misses from the other three.
@export var footprint: Vector2i = Vector2i.ONE

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

@export_group("Reaction")
## How far it recoils from a blow, in pixels. Zero is no recoil.
@export var hit_recoil: float = 2.5
## How far it squashes under one. 0.0 is no squash.
@export var hit_squash: float = 0.18
## How brightly it flashes. 0.0 is no flash.
@export var hit_flash: float = 0.7
## Seconds for the whole reaction.
@export var hit_time: float = 0.22

## Hits taken so far.
var _struck: int = 0
## The reaction currently playing, so a second blow restarts it rather than
## fighting the first for the same properties.
var _reaction: Tween

## Called by [WorldObjects] once the thing is in the world. Named for what
## happened rather than for what it sets, because a subclass overriding it is
## usually reacting to the event, not reading the arguments.
func placed_as(from: PlaceableData, at: Vector2i) -> void:
	source = from
	origin = at
	if from != null:
		footprint = from.footprint

## Every tile it covers.
##
## The one answer to "what ground is this standing on", so that the map files
## a thing under all of its tiles rather than under the corner it happens to
## be measured from.
func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in maxi(footprint.x, 1):
		for y in maxi(footprint.y, 1):
			out.append(origin + Vector2i(x, y))
	return out

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
	_struck += 1
	var left: int = total - _struck
	struck.emit(left)
	if left > 0:
		# It took the blow and is still standing, so it has to be seen to
		# take it. Felling it needs no such thing — the drops flying out of
		# it are the last blow made visible.
		react_to_hit()
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

## Recoils, squashes and flashes, so a blow that did not finish the job still
## reads as a blow.
##
## It leans away from the player rather than in a fixed direction, and finds
## them through the group rather than being told, so that [method hit] keeps
## the one argument the interaction model gives it. Only the player swings.
##
## The art is whatever sprite the scene happens to hold, because the scenes
## that are [Placed] do not agree on a name for it — [Decoration] has a
## Sprite, a chest has an AnimatedSprite2D — and a reaction that worked for
## only some of them would be worse than none.
func react_to_hit() -> void:
	var art := _art()
	if art == null:
		return
	if _reaction != null:
		_reaction.kill()

	var away := Vector2.UP
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and not global_position.is_equal_approx(player.global_position):
		away = (global_position - player.global_position).normalized()

	var rest_pos: Vector2 = art.get_meta(&"rest_position", art.position)
	art.set_meta(&"rest_position", rest_pos)
	var half := maxf(hit_time, 0.02) * 0.5

	# Parallel and sequential steps are switched explicitly rather than
	# chained. Chaining out of a parallel group does not sequence the way it
	# reads — it left this tween running and moving nothing at all — and
	# [Emote] had already learned the same lesson the same way.
	_reaction = create_tween()
	_reaction.set_parallel(true)
	(_reaction.tween_property(art, "position", rest_pos + away * hit_recoil, half)
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	(_reaction.tween_property(art, "scale",
			Vector2(1.0 + hit_squash, 1.0 - hit_squash), half)
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	var lit := 1.0 + hit_flash
	_reaction.tween_property(art, "modulate", Color(lit, lit, lit, 1.0), half * 0.4)

	# Settling back. The first of these is sequential, so it waits for the
	# group above; the rest ride alongside it.
	_reaction.set_parallel(false)
	(_reaction.tween_property(art, "position", rest_pos, half)
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	_reaction.set_parallel(true)
	(_reaction.tween_property(art, "scale", Vector2.ONE, half)
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	_reaction.tween_property(art, "modulate", Color.WHITE, half)

## The sprite this thing is drawn with, or null for one that is not.
func _art() -> Node2D:
	for child in get_children():
		if child is Sprite2D or child is AnimatedSprite2D:
			return child
	return null

## Throws the drops out and takes the thing out of the world. Returns whether
## it went, which is now always.
##
## It used to refuse to break when the satchel was full, so that the wood was
## not destroyed along with the tree. Drops are no longer handed over: they
## are thrown on the ground, and the ground holds as much as you like. A full
## satchel now means an item waiting in the grass, so there is nothing left
## to guard against and a tree can always be felled.
func _break() -> bool:
	# The parent is taken before leaving, because leaving frees this node and
	# a drop hung on it would go with it.
	var parent := get_parent()
	var from := global_position + Vector2(0.0, -6.0)
	for i in drops.size():
		var item: ItemData = drops[i]
		if item != null:
			Dropped.scatter(parent, from, item, _drop_count(i))
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
